#!/usr/bin/env zsh
#
# `up` and `restart` for the Apple `container` run path, in zsh — the same two
# commands `toolkit/container.nu` provides, for a host with no nushell on it.
#
#   ./toolkit/container.zsh up my-cozy ~/path/to/project
#   ./toolkit/container.zsh up my-cozy ~/project-a ~/shared-libs:ro ~/docs:ro
#   ./toolkit/container.zsh up my-cozy ~/path/to/project --ssh-agent
#   ./toolkit/container.zsh restart my-cozy
#
# zsh, not POSIX sh: Apple `container` is macOS-only, and zsh is the macOS login
# shell — so the one host this can run on always has it. Arrays are what keep a
# `container run` argument list readable here.
#
# NOT a replacement. `toolkit/container.nu` stays the primary path and is the
# only one with `reload-egress`, `refresh-egress` and `attach`; it also carries
# the full reasoning behind every step below, which is not repeated here. When
# the two disagree, container.nu is right.
#
# Needs `container` (macOS 26+, for `container network create --internal`) and
# `jq` — the runtime's `ls` schema is JSON and nothing in zsh reads it.

emulate -L zsh
setopt err_exit no_unset pipe_fail

# --- constants -------------------------------------------------------------
# These mirror toolkit/container.nu. The proxy pin is guarded against drift by
# `nu toolkit/check.nu egress-image`, which compares all three copies
# (compose.yaml, container.nu, this file); the rest are not guarded.

# `$0` is the function name inside a zsh function (FUNCTION_ARGZERO), so the
# script's own name is captured here, at the top level, for the messages below.
typeset -r SELF=$0
typeset -r COZY_ROOT=${0:A:h:h}
typeset -r CAGED_NETWORK=cozy-caged
typeset -r CAGED_SUBNET=192.168.216.0/24
typeset -r EGRESS_NAME=cozy-egress
typeset -r EGRESS_IMAGE='ubuntu/squid@sha256:6c919903a7a60f3ddd27735cab4516e2991420d49dfc3247e5228de994172d8b'
typeset -r PROXY_PORT=3128
typeset -r ROOT_PATH=/usr/sbin:/usr/bin:/sbin:/bin
typeset -r POLICY_CONF=/etc/squid/policy/squid.conf
# An IP literal, so no DNS is involved and --no-dns cannot be mistaken for
# isolation. Same probe as cozy verify's `egress: no direct route` row.
typeset -r DIRECT_PROBE=https://1.1.1.1

typeset -r DEFAULT_IMAGE=cozy:latest
typeset -r DEFAULT_MEMORY=8g
typeset -r DEFAULT_CPUS=6

# --- output ----------------------------------------------------------------

if [[ -t 1 ]]; then
    typeset -r C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
    typeset -r C_GREEN='' C_YELLOW='' C_RESET=''
fi

say()  { print -r -- "  ${C_GREEN}$1${C_RESET} $2" }
warn() { print -r -- "  ${C_YELLOW}$1${C_RESET} $2" }
die()  { print -r -u2 -- "${C_YELLOW}error:${C_RESET} $*"; exit 1 }

# --- runtime plumbing ------------------------------------------------------

# One scratch file for every captured stderr, cleaned up on any exit.
typeset -g CLI_ERR
# An explicit template, not `mktemp -t cozy-container`: BSD mktemp appends the
# random suffix itself, GNU refuses a template with no X's in it.
CLI_ERR=$(mktemp "${TMPDIR:-/tmp}/cozy-container.XXXXXX") || { print -r -u2 -- 'error: mktemp failed'; exit 1 }
trap 'rm -f -- $CLI_ERR' EXIT
# Not `EXIT INT TERM` on the line above: a handler that returns *resumes* the
# script after the signal, and every retry loop below swallows the child's 130
# with `|| rc=$?` — so Ctrl-C during the cage probe killed one attempt and the
# poll went on to the next, 15 presses to escape. Exiting here runs the EXIT
# trap, which does the cleanup.
trap 'exit 130' INT TERM

# Why the answer comes back in a global rather than on stdout: `die` inside a
# `$(...)` exits the subshell, not the script — a refused command would print its
# message and let the caller carry on with an empty value. Every function below
# that can refuse writes its result to a global for the same reason.
typeset -g CLI_OUT=''

# Every `container` call goes through here so a failure raises with the command
# and its stderr, rather than an empty result the caller reads as success.
container_cli() {
    local rc=0
    CLI_OUT=$(command container "$@" 2>$CLI_ERR) || rc=$?
    if (( rc != 0 )); then
        die "\`container $*\` failed:
  $(<$CLI_ERR)"
    fi
}

typeset -g C_STATE=''

# `container ls --format json` keys the name under configuration.id and the run
# state under status.state — `status` is an object, not a string.
container_status() {
    container_cli ls --all --format json
    C_STATE=$(print -r -- "$CLI_OUT" | jq -r --arg n "$1" '
        [.[] | select(.configuration.id == $n)]
        | if length == 0 then "absent" else .[0].status.state end')
}

# Whole tokens, not a substring test: `cozy-caged-old` used to read as a match
# and report "already up" for a network that is not ours.
caged_network_exists() {
    container_cli network list
    local -a names=(${=CLI_OUT})
    (( ${names[(I)$CAGED_NETWORK]} ))
}

# Why a poll at all: `container run --detach` and `container start` both return
# before the container's VM has finished booting, so the first execs and the
# first address lookup come back empty. Retries a function until it exits 0.
poll() {
    local attempts=$1 i; shift
    for (( i = 1; i <= attempts; i++ )); do
        if "$@"; then return 0; fi
        if (( i != attempts )); then sleep 1; fi
    done
    return 1
}

proxy_url() { print -r -- "http://$1:$PROXY_PORT" }

# --- the cage --------------------------------------------------------------

# `cozy-egress` matches a container name like any other, but the cozy commands
# are not harmless against it: the cage probe below runs from inside the
# dual-homed proxy, reaches the internet by design, and would stop the proxy
# over that "leak" — cutting the exit of the running cozy container.
reject_proxy_name() {
    [[ $1 != $EGRESS_NAME ]] || die \
"$EGRESS_NAME is the egress proxy, not a cozy container. It is managed for you:
  \`up\` and \`restart\` start or recreate it, and \`nu toolkit/container.nu reload-egress <container>\`
  applies an edited allowlist to it."
}

typeset -g POLICY_DIR=''

resolve_policy() {
    local dir=${1:-$HOME/.config/cozy/firewall}
    dir=${~dir}
    dir=${dir:A}
    [[ -d $dir ]] || die \
"no policy at $dir — seed it once with:
  mkdir -p ~/.config/cozy && cp -R $COZY_ROOT/firewall ~/.config/cozy/firewall
Keeping it outside this repo is what makes the allowlist human-managed."
    POLICY_DIR=$dir
}

# `--internal` is the whole enforcement: a host-only network, no route out.
#
# An existing network is only a name — nothing observable here proves it was
# created with --internal, and one made by hand without it hands the caged
# container a route around the proxy while this function prints green. That is
# why assert_caged probes the finished cage from the container itself.
ensure_network() {
    if caged_network_exists; then
        say 'Network:' "$CAGED_NETWORK already up — cage probed after the container starts"
        return
    fi
    container_cli network create --internal --subnet $CAGED_SUBNET $CAGED_NETWORK
    say 'Network:' "created $CAGED_NETWORK ($CAGED_SUBNET), host-only"
}

typeset -g CAGE_TARGET='' PROBE_CODE='' PROBE_RC=0

# Success here means "we got a status to judge", not "the cage holds". An empty
# status is the still-booting case; curl always prints one otherwise.
_probe_cage() {
    PROBE_RC=0
    PROBE_CODE=$(command container exec $CAGE_TARGET \
        curl --silent --show-error --noproxy '*' --max-time 10 \
             --output /dev/null --write-out '%{http_code}' $DIRECT_PROBE \
        2>$CLI_ERR) || PROBE_RC=$?
    [[ -n $PROBE_CODE ]]
}

assert_caged() {
    local name=$1
    CAGE_TARGET=$name PROBE_CODE='' PROBE_RC=0
    poll 15 _probe_cage || true
    local err=$(<$CLI_ERR)

    # curl prints 000 and exits non-zero when the connection never happens —
    # that is the pass. Any real status means traffic left unfiltered. Anything
    # else is an unproven cage, which fails too: "we could not check" must not
    # read as "it is fine".
    if [[ $PROBE_CODE == 000 ]]; then
        say 'Cage:' "$name cannot reach $DIRECT_PROBE with the proxy bypassed"
        return
    fi

    # Past here the container is running and is not a proven cage, so stop it
    # before raising — otherwise the leak the error is about stays open for as
    # long as the human takes to read the message. Stopped, not deleted:
    # `container logs` and `inspect` still work.
    local cleanup
    if command container stop $name >/dev/null 2>&1; then
        cleanup=" $name has been stopped."
    else
        cleanup=" $name could NOT be stopped and is still running."
    fi

    if [[ $PROBE_CODE == [0-9][0-9][0-9] ]]; then
        die \
"$name reached $DIRECT_PROBE directly (HTTP $PROBE_CODE) — the cage is open and traffic
  bypasses the allowlist. $CAGED_NETWORK was almost certainly created without --internal:
  \`container delete $name\`, \`container network delete $CAGED_NETWORK\`, then re-run \`up\`.$cleanup"
    fi
    die "could not probe the cage from $name: curl gave no status (exit $PROBE_RC)${err:+, stderr: $err}.$cleanup"
}

# Recreated rather than started when it is not running: `run` is where the mount
# and the two networks are declared, and an existing container may carry older
# ones. This path can move the proxy's address; callers re-map the cozy
# container's /etc/hosts line afterwards.
ensure_egress() {
    local policy=$1

    # Said out loud because the failure it makes visible is a stale copy of this
    # script recreating the proxy from an old digest while printing green.
    say 'Pin:' "$EGRESS_IMAGE"

    # Not named `status`: that is a read-only zsh special, an alias for `$?`.
    container_status $EGRESS_NAME
    local state=$C_STATE
    if [[ $state == running ]]; then
        say 'Proxy:' "$EGRESS_NAME already running"
        return
    fi
    if [[ $state != absent ]]; then
        container_cli delete $EGRESS_NAME
    fi

    # Dual-homed: `default` is the only way out, the caged network the only way
    # in. Repeating --network is how Apple's maintainers spell this.
    #
    # The whole policy directory, one mount — not the two files individually: a
    # bind-mounted file pins an inode, so an editor that saves atomically leaves
    # the proxy reading the old copy and the edit silently never applies.
    #
    # `--args squid` and PEBBLE_VERBOSE are the image's doing: Pebble owns the
    # command line and the layer file's bracketed arguments are *defaults* that
    # --args replaces — without it Pebble's own parser takes `-f` and dies. And
    # Pebble keeps a service's output to itself unless asked, which would
    # silence the refusal log the allowlist is managed by.
    container_cli run --detach \
        --name $EGRESS_NAME \
        --network default \
        --network $CAGED_NETWORK \
        --env PEBBLE_VERBOSE=1 \
        --volume "$policy:/etc/squid/policy:ro" \
        $EGRESS_IMAGE \
        --args squid -f $POLICY_CONF -NYC
    say 'Proxy:' "started $EGRESS_NAME with $policy"
}

typeset -g EGRESS_IP=''

# The runtime already knows the address: `container ls --format json` carries
# status.networks, a row per attachment with `network` naming it and
# `ipv4Address` in CIDR form. Selected by network name rather than guessed from
# an address prefix, so the image needs to contain no `hostname` binary.
_probe_egress_addr() {
    local json
    json=$(command container ls --all --format json 2>/dev/null) || return 1
    EGRESS_IP=$(print -r -- "$json" | jq -r \
        --arg n "$EGRESS_NAME" --arg net "$CAGED_NETWORK" '
        [ .[] | select(.configuration.id == $n)
              | (.status.networks // [])[]
              | select(.network == $net)
              | .ipv4Address ]
        | .[0] // empty | split("/") | .[0]')
    [[ -n $EGRESS_IP ]]
}

egress_address() {
    EGRESS_IP=''
    poll 15 _probe_egress_addr || die \
"$EGRESS_NAME never got an address on $CAGED_NETWORK — check \`container logs $EGRESS_NAME\`
  and that it is attached to it"
    say 'Exit:' "$(proxy_url $EGRESS_IP)"
}

# Why: the image's PATH leads with agent-owned dirs (~/.local/bin, ~/.cargo/bin,
# linuxbrew), so a bare `sh` or `sed` in a uid-0 exec runs whatever the agent
# dropped there. Same two measures as `root-sh` in container.nu: the shell by
# absolute path, and PATH reset as the script's first statement.
root_sh() {
    container_cli exec --uid 0 $1 /bin/sh -c "PATH=$ROOT_PATH; export PATH; $2"
}

# The one mutable link between the cozy container and its exit. Nothing on this
# network keeps its address across a start, so the container's *_PROXY env
# carries the proxy's *name* and this line maps that name to wherever the proxy
# is right now. /etc/hosts because a host-only network has no DNS; written as
# root because the `agent` user has no sudo.
set_egress_hosts() {
    root_sh $1 "sed --in-place '/ $EGRESS_NAME\$/d' /etc/hosts; echo '$2 $EGRESS_NAME' >> /etc/hosts"
    say 'Hosts:' "$EGRESS_NAME -> $2, mapped inside $1"
}

# The other half of --no-dns, which the flag cannot deliver alone: it stops the
# runtime from writing a resolver, but the Debian base image already ships
# `nameserver 1.1.1.1`. On the cage that address is unreachable and the packets
# are black-holed rather than refused, so every lookup waits out glibc's
# 20s default. With no nameserver line glibc falls back to 127.0.0.1, which
# refuses instantly; names are resolved by the proxy anyway.
clear_resolver() {
    root_sh $1 "echo '# cozy: no resolver — $EGRESS_NAME resolves names' > /etc/resolv.conf"
    say 'Resolver:' "cleared in $1 — the cage has none, and the image's 1.1.1.1 costs 20s a lookup"
}

# Guard for containers created before the exit moved to a name: their env holds
# a fixed address, which cannot be changed on an existing container, so they
# cannot follow the proxy. A one-time recreation is the only fix.
assert_exit_by_name() {
    local name=$1 baked rc=0
    baked=$(command container exec $name printenv HTTPS_PROXY 2>$CLI_ERR) || rc=$?
    local err=$(<$CLI_ERR)

    # `printenv` on an unset var exits 1 with both streams empty; an exec that
    # failed outright also has empty stdout but says why on stderr. Tell them
    # apart, or a broken exec reads as "not created by up".
    if (( rc != 0 )) && [[ -n $err ]]; then
        die "could not read HTTPS_PROXY from $name: $err"
    fi
    [[ -n $baked ]] || die \
"$name has no HTTPS_PROXY — it was not created by \`up\`, so it has no exit at all
  (a bare \`container run\` has no cage; \`cozy verify\`'s egress: rows fail on it by design)."

    local want=$(proxy_url $EGRESS_NAME)
    [[ $baked == $want ]] || die \
"$name was built with the fixed exit $baked instead of the name $want — a baked address
  cannot be updated, so it cannot follow the proxy. Recreate it once:
  \`container delete $name\`, then \`$SELF up $name <folder>\`."
}

# --- host-side inputs ------------------------------------------------------

typeset -ga GIT_IDENT_ARGS=()

# Forward the host's own git identity so the human's commits inside the
# container are the human's. Read here rather than stored anywhere: this runs on
# the host, where `git config --global` already holds the answer.
host_git_identity() {
    GIT_IDENT_ARGS=()
    local -a id=()
    local k v rc
    for k in user.name user.email; do
        rc=0
        v=$(git config --global --get $k) || rc=$?
        # Exit 1 is git's "key not set" — the expected miss. Anything else is a
        # broken config, which must not read as "no identity".
        (( rc == 0 || rc == 1 )) || die "\`git config --global --get $k\` failed (exit $rc)"
        id+=("$v")
    done

    # All or nothing, the same rule the git-identity.nu autoload enforces on the
    # writing side: half an identity lands commits as `Someone <agent@sandbox>`,
    # a name that never existed.
    if [[ -n ${id[1]} && -n ${id[2]} ]]; then
        say 'You:' "${id[1]} <${id[2]}> — the agent still commits as Claude"
        GIT_IDENT_ARGS=(--env "COZY_GIT_USER_NAME=${id[1]}" --env "COZY_GIT_USER_EMAIL=${id[2]}")
    elif [[ -n ${id[1]} || -n ${id[2]} ]]; then
        warn 'You:' "host \`git config --global\` has only one of user.name/user.email — forwarding neither"
    fi
}

typeset -ga SSH_ARGS=()

# `--ssh` is a boolean flag on `container run`: the runtime mounts the host's
# agent socket and sets the guest's own SSH_AUTH_SOCK, so there is deliberately
# no --env SSH_AUTH_SOCK beside it. Nothing is needed in `restart` — `ssh: true`
# is stored in the container's configuration and `container start` re-reads the
# host's current socket on every start.
#
# What this does NOT buy inside the cage: git over ssh. squid allows CONNECT to
# 443 only and ssh cannot speak to an HTTP proxy, so `git@github.com:` remotes
# fail here whatever the agent holds. What it does buy is signing, which needs
# no network.
ssh_agent_args() {
    SSH_ARGS=()
    (( $1 )) || return 0

    # Upstream only logs a warning when SSH_AUTH_SOCK is missing and then starts
    # the container with no socket at all — an explicitly requested forward that
    # silently did not happen. Refused here, where the cause is still in hand.
    local sock=${SSH_AUTH_SOCK:-}
    [[ -n $sock ]] || die \
"--ssh-agent needs SSH_AUTH_SOCK and this shell has none. On macOS adding a key starts
  the system agent: \`ssh-add --apple-use-keychain ~/.ssh/id_ed25519\`."
    [[ -S $sock || -e $sock ]] || die \
"SSH_AUTH_SOCK names $sock, which does not exist — the agent it points at is gone.
  Open a fresh login shell, or start one with \`ssh-add --apple-use-keychain ~/.ssh/id_ed25519\`."

    # Exit 1 is "the agent answers but holds no keys" — a warning, not an error:
    # what gets mounted is a live socket, so a key added on the host afterwards
    # is usable inside immediately. Exit 2 is "nothing answers there".
    local out rc=0
    out=$(ssh-add -l 2>$CLI_ERR) || rc=$?
    if (( rc == 2 )); then
        die "SSH_AUTH_SOCK is $sock but no agent answers there: $(<$CLI_ERR)"
    elif (( rc == 1 )); then
        warn 'Agent:' "the host agent currently holds no keys — \`ssh-add --apple-use-keychain ~/.ssh/id_ed25519\` adds one, and it works inside without a restart"
    else
        # The count and nothing else. Fingerprints are not secret, but no part
        # of this job needs one printed, and key material must never pass
        # through this script at all.
        local -a keys=(${(f)out})
        local word=keys; (( $#keys == 1 )) && word=key
        warn 'Agent:' "forwarding the host ssh-agent, $#keys $word — anything inside the container can sign with them while it runs, though it can never read them. Prefer a key dedicated to this over your personal one."
    fi
    SSH_ARGS=(--ssh)
}

typeset -ga WS_PATHS=() WS_RO=()

# `path[:ro]` — the spelling `sbx run` uses for extra workspaces, kept identical
# so the two run paths take the same arguments.
parse_workspaces() {
    WS_PATHS=(); WS_RO=()
    local e p ro
    for e in "$@"; do
        if [[ $e == *:ro ]]; then ro=1; p=${e%:ro}; else ro=0; p=$e; fi
        p=${~p}
        p=${p:A}
        [[ -e $p ]] || die "workspace $p does not exist"
        WS_PATHS+=("$p"); WS_RO+=($ro)
    done
}

# Overlap in either direction, both slash-terminated so `cozy-2` never matches
# `cozy`: a path above the target hands the target over wholesale, and a path
# inside it hands over a piece.
paths_overlap() {
    local a=${1:A} b=${2:A}
    a=${a%/}/ ; b=${b%/}/
    [[ $a == "$b"* || $b == "$a"* ]]
}

# Everything the agent can write is what builds the cage on the next launch —
# this script, the firewall template, and above all the live policy the proxy
# re-reads on every reload — so no writable mount may overlap the cozy repo or
# the policy directory. `:ro` is exempt because it removes exactly the ability
# the rule is about.
reject_writable() {
    local p=$1 ro=$2 policy=$3
    (( ro )) && return 0
    if paths_overlap "$p" "$COZY_ROOT"; then
        die \
"workspace $p overlaps the cozy repo — the agent would be able to edit this script and
  the firewall template, which are read fresh at the next launch. Pick a folder outside
  it, or mount it read-only as ${p}:ro."
    fi
    if paths_overlap "$p" "$policy"; then
        die \
"workspace $p overlaps the firewall policy $policy — the agent would be able to edit its
  own allowlist, which the proxy re-reads on the next reload. Pick a folder outside it,
  or mount it read-only as ${p}:ro."
    fi
    return 0
}

hints() {
    local name=$1
    print
    print -r -- "  attach:  container exec --interactive --tty $name nu --login --execute 'zellij attach --create $name'"
    print -r -- "  check:   container exec $name nu --commands 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'"
    print -r -- "  refused: container logs --follow $EGRESS_NAME"
}

# --- up --------------------------------------------------------------------

cmd_up() {
    local image=$DEFAULT_IMAGE memory=$DEFAULT_MEMORY cpus=$DEFAULT_CPUS
    local policy_flag='' workdir='' ssh_agent=0
    local -a positional=()

    while (( $# )); do
        case $1 in
            --image)      image=$2;       shift 2 ;;
            --image=*)    image=${1#*=};  shift   ;;
            --policy)     policy_flag=$2; shift 2 ;;
            --policy=*)   policy_flag=${1#*=}; shift ;;
            --workdir)    workdir=$2;     shift 2 ;;
            --workdir=*)  workdir=${1#*=}; shift  ;;
            --memory)     memory=$2;      shift 2 ;;
            --memory=*)   memory=${1#*=}; shift   ;;
            --cpus)       cpus=$2;        shift 2 ;;
            --cpus=*)     cpus=${1#*=};   shift   ;;
            --ssh-agent)  ssh_agent=1;    shift   ;;
            --)           shift; positional+=("$@"); break ;;
            -*)           die "unknown flag $1 — see the header of $SELF" ;;
            *)            positional+=("$1"); shift ;;
        esac
    done

    (( $#positional >= 1 )) || die "usage: $SELF up <name> <folder> [more:ro ...] [flags]"
    local name=${positional[1]}
    shift positional
    reject_proxy_name $name
    (( $#positional >= 1 )) || die "no workspace given — \`$SELF up <name> <folder> [more:ro ...]\`"

    parse_workspaces "${positional[@]}"
    # Only the first can be WORKSPACE_DIR: the variable is single-valued and
    # `cozy sandbox-state` writes into it. Same rule as `sbx run`.
    local primary=${WS_PATHS[1]}

    resolve_policy "$policy_flag"
    local policy_dir=$POLICY_DIR

    # Every mount, not just the primary: an extra folder is as writable as the
    # first one.
    local i
    for (( i = 1; i <= $#WS_PATHS; i++ )); do
        reject_writable "${WS_PATHS[i]}" ${WS_RO[i]} "$policy_dir"
    done

    # Before anything is created, deliberately: `up` creates, and an existing
    # name means the user wants `restart` instead. A refusal that lands after a
    # network and a proxy were built reads as "nothing happened".
    container_status $name
    [[ $C_STATE == absent ]] || die \
"a container named $name already exists.
  \`$SELF restart $name\` brings it back, \`nu toolkit/container.nu reload-egress $name\` applies an
  edited allowlist, or \`container stop $name; container delete $name\` to rebuild it"

    # Also before ensure_network: this reads only the host and can only say no.
    ssh_agent_args $ssh_agent

    ensure_network
    # --policy picks the directory only when the proxy is (re)created — a
    # running proxy keeps the mount it was created with. Explicitly asked for
    # and silently ignored must not look the same.
    container_status $EGRESS_NAME
    if [[ -n $policy_flag && $C_STATE == running ]]; then
        warn 'Policy:' "$EGRESS_NAME is already running and keeps the policy directory it was created with — \`container stop $EGRESS_NAME\` first to have it recreated with $policy_dir"
    fi
    ensure_egress "$policy_dir"
    egress_address

    host_git_identity

    # Every folder is mounted at its own host path — the cozy convention, and
    # the one that keeps a path copied from the host valid inside the container.
    # Braces around every subscript, not `$WS_PATHS[i]:ro`: zsh reads a `:`
    # after a parameter as a history modifier, so that spelling applied `:r`
    # (remove extension) and left a bare `o` — `/x/policy:/x/policyo`.
    local -a mounts=() mounted=()
    for (( i = 1; i <= $#WS_PATHS; i++ )); do
        if (( WS_RO[i] )); then
            mounts+=(--volume "${WS_PATHS[i]}:${WS_PATHS[i]}:ro")
            mounted+=("${WS_PATHS[i]} (ro)")
        else
            mounts+=(--volume "${WS_PATHS[i]}:${WS_PATHS[i]}")
            mounted+=("${WS_PATHS[i]}")
        fi
    done

    local start_dir=$primary
    if [[ -n $workdir ]]; then start_dir=${~workdir}; start_dir=${start_dir:A}; fi

    # --no-dns: a host-only network has no resolver, so configuring one buys
    # nothing but a timeout per lookup (see clear_resolver for the other half).
    #
    # The proxy variables are not the enforcement — the missing route is. They
    # only tell clients where the one exit is, so a blocked request gets a clean
    # 403 instead of hanging. They carry the proxy's *name*, not its address:
    # env cannot be changed on an existing container and no address here
    # survives a start.
    #
    # --memory: Apple `container` gives a VM 1g and one Claude Code process
    # holds ~300MB. Two of them fill the cgroup, the page cache is squeezed to
    # nothing, and the kernel evicts the agents' own code pages and faults them
    # straight back in — no OOM kill to end it, it just grinds. Headroom for the
    # page cache is the fix. --cpus is raised past the runtime's 4 for
    # parallelism, not for that; keep it at or below the host's core count.
    local exit_url=$(proxy_url $EGRESS_NAME)
    container_cli run --detach \
        --name $name \
        --network $CAGED_NETWORK \
        --no-dns \
        --memory $memory \
        --cpus $cpus \
        --env "WORKSPACE_DIR=$primary" \
        --env "HTTP_PROXY=$exit_url" \
        --env "HTTPS_PROXY=$exit_url" \
        --env "http_proxy=$exit_url" \
        --env "https_proxy=$exit_url" \
        --env 'NO_PROXY=localhost,127.0.0.1,::1' \
        "${GIT_IDENT_ARGS[@]}" \
        "${SSH_ARGS[@]}" \
        "${mounts[@]}" \
        --workdir "$start_dir" \
        $image sleep infinity
    say 'Container:' "$name on $CAGED_NETWORK, workspace ${(j:, :)mounted}"

    # The cage first: assert_caged also carries the boot wait, so by the time it
    # returns the container can take the root exec the mapping needs.
    assert_caged $name
    set_egress_hosts $name $EGRESS_IP
    clear_resolver $name
    if (( ssh_agent )); then assert_agent_reachable $name; fi

    hints $name
}

# The builder checks what it built — the same rule as assert_caged. Exit 1
# counts as reachable: an agent holding no keys still proves the socket arrived.
assert_agent_reachable() {
    local rc=0
    command container exec $1 ssh-add -l >/dev/null 2>$CLI_ERR || rc=$?
    if (( rc != 0 && rc != 1 )); then
        die \
"$1 started, but \`ssh-add -l\` inside it cannot reach the forwarded agent, exit $rc:
  $(<$CLI_ERR)
  Recreate it without --ssh-agent, or check that the host agent is still alive."
    fi
    say 'Agent:' "$1 reaches the forwarded agent at /var/host-services/ssh-auth.sock"
}

# --- restart ---------------------------------------------------------------

# Bring the pair back after the runtime itself restarted (`container system
# stop/start`, an upgrade, a reboot), or after you stopped them for the day.
# Also the fix after a bare `container start <name>`: the runtime regenerates
# /etc/hosts at start, so the exit mapping exists only once restart rewrites it.
cmd_restart() {
    local policy_flag=''
    local -a positional=()
    while (( $# )); do
        case $1 in
            --policy)   policy_flag=$2;      shift 2 ;;
            --policy=*) policy_flag=${1#*=}; shift   ;;
            --)         shift; positional+=("$@"); break ;;
            -*)         die "unknown flag $1 — see the header of $SELF" ;;
            *)          positional+=("$1"); shift ;;
        esac
    done
    (( $#positional == 1 )) || die "usage: $SELF restart <name> [--policy DIR]"

    local name=${positional[1]}
    reject_proxy_name $name

    container_status $name
    local container_state=$C_STATE
    [[ $container_state != absent ]] || die \
"no container named $name — nothing to restart. Create it: \`$SELF up $name <folder>\`"

    # The one rebuild instruction left: the container was attached to the
    # network at creation, and nothing proves it comes back into a *recreated*
    # network rather than around it — an unproven cage must not come back
    # quietly.
    caged_network_exists || die \
"$CAGED_NETWORK is gone — $name has no cage to come back to. Rebuild both:
  \`container delete $name\`, then \`$SELF up $name <folder>\` recreates the network."

    container_status $EGRESS_NAME
    local egress_state=$C_STATE
    if [[ $egress_state == absent ]]; then
        # A gone proxy no longer forces rebuilding the cozy container: it points
        # at the name, so a fresh proxy on a fresh address is mapped below like
        # any other.
        resolve_policy "$policy_flag"
        ensure_egress "$POLICY_DIR"
    elif [[ $egress_state != running ]]; then
        container_cli start $EGRESS_NAME
        say 'Proxy:' "started $EGRESS_NAME"
    else
        say 'Proxy:' "$EGRESS_NAME already running"
    fi
    egress_address

    if [[ $container_state != running ]]; then
        container_cli start $name
        say 'Container:' "started $name"
    else
        say 'Container:' "$name already running"
    fi

    # The cage first, the exit second: a cage that came back open is a leak and
    # assert_caged stops the container over it, while a missing exit only leaves
    # the container with no way out. The restart is also where the cage is most
    # worth re-proving — the runtime rebuilt the network, we did not.
    assert_caged $name
    assert_exit_by_name $name
    set_egress_hosts $name $EGRESS_IP
    clear_resolver $name

    hints $name
}

# --- entry point -----------------------------------------------------------

usage() {
    print -r -- "usage: $SELF <up|restart> ... — see the header of this file

  $SELF up <name> <folder> [more:ro ...] [--image I] [--policy DIR] [--workdir W]
                        [--memory 8g] [--cpus 6] [--ssh-agent]
  $SELF restart <name> [--policy DIR]

reload-egress, refresh-egress and attach live only in \`nu toolkit/container.nu\`."
}

main() {
    (( $# )) || { usage; exit 1 }

    for dep in container jq; do
        (( $+commands[$dep] )) || die "\`$dep\` is not on PATH — this script needs both \`container\` and \`jq\`"
    done

    local sub=$1; shift
    case $sub in
        up)      cmd_up "$@" ;;
        restart) cmd_restart "$@" ;;
        -h|--help|help) usage ;;
        *)       usage; exit 1 ;;
    esac
}

main "$@"
