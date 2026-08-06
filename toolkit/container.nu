# The Apple `container` run path, as one command group — what `compose.yaml` plus
# `docker compose exec` are for the docker path.
#
# Apple `container` has no compose, so the three pieces compose declares are
# assembled here instead: a host-only network with no way out, a squid holding
# the allowlist dual-homed onto that network and the default one, and the cozy
# container attached to the caged network only. Same image, same policy
# directory, same residual risks as the docker path — see README's "Egress
# firewall".
#
# Requires macOS 26 or later: `container network create` does not exist before
# it, and on macOS 15 `--network` is an error. Without it there is no cage on
# this runtime at all, and `cozy verify`'s two `egress:` rows fail by design.
#
#   nu toolkit/container.nu up my-cozy ~/path/to/project
#   nu toolkit/container.nu up my-cozy ~/project-a ~/shared-libs:ro ~/docs:ro
#   nu toolkit/container.nu restart my-cozy
#   nu toolkit/container.nu reload-egress my-cozy   # after editing the allowlist
#
# `attach` is the exception — it opens the WezTerm window as a background job,
# which dies with a one-shot `nu <script>`, so it needs an interactive nu:
#
#   use toolkit/container.nu
#   container attach my-cozy --workdir ~/path/to/project
#
# Why a group per runtime rather than one command per job: everything here is
# specific to `container` — its flags, its two-address proxy, its lack of a
# workspace notion — and the three jobs share the cage helpers below. The sbx
# path stays in toolkit/sbxw.nu and knows nothing about any of it; the one thing
# the two paths genuinely share, opening the WezTerm window, lives in
# toolkit/wezterm.nu.

use ./wezterm.nu *

const cozy_root = (path self | path dirname | path dirname)

const caged_network = 'cozy-caged'
# Why: a /24 so telling the proxy's two homes apart is a plain prefix test.
# Apple `container` has no static-IP flag, so the proxy's address can only be
# discovered after it starts, and picking the right one of its two addresses
# needs the caged subnet known up front.
const caged_subnet = '192.168.216.0/24'

const egress_name = 'cozy-egress'
# Same pin as compose.yaml, deliberately: both paths must enforce the identical
# policy with the identical proxy, and this is the one container that holds the
# policy and has internet, so it should not change under us on a pull. The two
# literals are guarded against each other by `nu toolkit/check.nu egress-image`.
#
# Digest only, no tag: a tag next to a digest is ignored, so the `:latest` this
# carried read as a lie. Pinned 2026-08-06 to `7.2-26.04_edge` — squid 7.2 on
# Ubuntu 26.04. `:latest` is not the fresher alternative it looks like: upstream
# has not moved it in eight months and it still resolves to a squid 6.6 `_beta`
# build. Frozen means upstream CVE fixes never arrive; re-pin deliberately.
#
# This image is a rock — entrypoint `pebble enter`, squid supervised as a Pebble
# service — which is why the run arguments below carry `--args squid` and the
# binary named further down is not `squid`. Validate any future candidate on a
# throwaway container before it goes near the running cage; the rehearsal that
# proved this one is todo/20260806-221500-rehearse-squid7-proxy.nu.
const egress_image = 'ubuntu/squid@sha256:739595239b20999cbddcbd48eb56ec3dfa6df360166fa624fd66201d592dcf89'
const proxy_port = 3128
# The config path inside the proxy, shared by the run arguments and the reload.
# One literal because `squid -k` has to be pointed at the same file the running
# instance was started with: given another one it validates that instead, and
# reports success about a policy nobody is enforcing.
const policy_conf = '/etc/squid/policy/squid.conf'
# The binary, by absolute path. Not `squid`: this rock ships it as
# `squid-gnutls` and has no `squid` on PATH at all, so the bare name fails with
# `cannot find executable` — which is what every `-k` call below would hit.
const squid_bin = '/usr/sbin/squid-gnutls'

# Why: every `container` call goes through here so an unsupported flag surfaces
# as the failing command and its stderr. Apple `container` is young and this
# script is written against its documentation, not against a machine — the first
# run is where the flags get proven, and a silent empty result would hide that.
def container-cli [args: list<string>]: nothing -> string {
    let r = ^container ...$args | complete
    if $r.exit_code != 0 {
        error make {msg: $"`container ($args | str join ' ')` failed:\n($r.stderr | str trim)"}
    }
    $r.stdout
}

# `container ls --format json` keys the name under configuration.id and the run
# state under status.state — `status` is a record (state, networks,
# startedDate), not a string.
def container-status [name: string]: nothing -> string {
    let rows = container-cli [ls --all --format json] | from json | where configuration.id == $name
    if ($rows | is-empty) { 'absent' } else { $rows | first | get status.state }
}

def "nu-complete container names" []: nothing -> table<value: string, description: string> {
    # Why --all: stopped containers are the ones `restart` is for, and without it
    # every description reads `running`. `complete` because a completer that
    # errors when the runtime is down turns tab into a stack trace — no names is
    # the right answer then. The proxy is not offered: these commands manage the
    # cozy container, and running them against the proxy is refused anyway
    # (reject-proxy-name).
    let r = ^container ls --all --format json | complete
    if $r.exit_code != 0 { return [] }
    $r.stdout | from json
    | where configuration.id != $egress_name
    | each {|x| {value: $x.configuration.id description: $x.status.state} }
}

# `cozy-egress` pattern-matches like any container name, but it is the proxy —
# and the cozy commands are not harmless against it: assert-caged, probing from
# inside the dual-homed proxy, reaches the internet by design, so restart would
# stop the proxy over that "leak" and cut the exit of the running cozy
# container, with a diagnosis blaming the network. Refused by name instead.
def reject-proxy-name [name: string]: nothing -> nothing {
    if $name == $egress_name {
        error make {msg: $"($egress_name) is the egress proxy, not a cozy container. It is managed for you: `up` and `restart` start or recreate it, and `reload-egress <container>` applies an edited allowlist to it."}
    }
}

# Why whole tokens and not `str contains`: the substring test also accepted a
# leftover `cozy-caged-old` and returned "already up" for a network that isn't
# ours. `network ls --format json` would be exact, but Apple's ls/inspect schema
# is undocumented (see egress-address), so compare whitespace-separated tokens —
# that needs no column layout and no key names.
def caged-network-exists []: nothing -> bool {
    let names = container-cli [network list] | split row --regex '\s+'
    $caged_network in $names
}

# `--internal` is the whole enforcement: a host-only network, no route out. The
# cozy container sits here alone with the proxy and can reach nothing else.
#
# An existing network is still only a name. Nothing observable here proves it
# was created with --internal, and one made by hand or by an older version
# without it hands the caged container a route around the proxy — while this
# function prints green and the run continues to success. That is why
# assert-caged probes the finished cage from the container itself; the property
# is checked where it can be seen, not assumed here.
def ensure-network []: nothing -> nothing {
    if (caged-network-exists) {
        print $"  (ansi green)Network:(ansi reset) ($caged_network) already up — cage probed after the container starts"
        return
    }
    container-cli [network create --internal --subnet $caged_subnet $caged_network]
    print $"  (ansi green)Network:(ansi reset) created ($caged_network) ($caged_subnet), host-only"
}

# Reached with the proxy bypassed, from inside the cozy container, to prove the
# cage itself rather than the proxy in front of it. An IP literal, so no DNS is
# involved and --no-dns can't be mistaken for isolation. Same probe as
# cozy-module/verify.nu's `egress: no direct route` row, on purpose: that row is
# the on-demand check a human runs inside a sandbox, this one is the launch-time
# check the script owes for the cage it just built. A builder that reports
# success without looking at its own result is the gap being closed.
const direct_probe = 'https://1.1.1.1'

def assert-caged [name: string]: nothing -> nothing {
    # Retried for the same reason egress-address is: `run -d` and `start` return
    # before the container's VM has finished booting, so the first execs fail
    # with nothing on stdout. An empty stdout is "not ready yet"; curl always
    # prints a status, even for a connection that never happened.
    mut r = {stdout: '' stderr: '' exit_code: 0}
    for _ in 1..15 {
        $r = ^container exec $name curl -sS --noproxy '*' --max-time 10 -o /dev/null -w '%{http_code}' $direct_probe | complete
        if ($r.stdout | str trim | is-not-empty) { break }
        sleep 1sec
    }
    let code = $r.stdout | str trim
    # curl prints 000 and exits non-zero when the connection never happens —
    # that is the pass. Any real status means traffic left unfiltered. Anything
    # else (no curl, garbage) is an unproven cage, which is a failure too: the
    # whole point is that "we could not check" must not read as "it is fine".
    if $code == '000' {
        print $"  (ansi green)Cage:(ansi reset) ($name) cannot reach ($direct_probe) with the proxy bypassed"
        return
    }

    # Past this point the container is running and is not a proven cage, so stop it
    # before raising. Raising alone left it up with whatever route the probe just
    # found, for as long as the human takes to read the message — the leak the
    # error is about, still open. Stopped, not deleted: `container logs` and
    # `inspect` still work, and the messages below already say to delete.
    #
    # Not container-cli because: a failed stop must not replace the diagnosis
    # with its own error. Report what happened and let the real cause through.
    let stopped = ^container stop $name | complete
    let cleanup = if $stopped.exit_code == 0 {
        $" ($name) has been stopped."
    } else {
        $" ($name) could NOT be stopped and is still running: ($stopped.stderr | str trim)"
    }

    if ($code =~ '^\d{3}$') {
        error make {msg: $"($name) reached ($direct_probe) directly \(HTTP ($code)) — the cage is open and traffic bypasses the allowlist. ($caged_network) was almost certainly created without --internal: `container delete ($name)`, `container network delete ($caged_network)`, then re-run `up` to rebuild both.($cleanup)"}
    } else {
        error make {msg: $"could not probe the cage from ($name): curl gave no status \(exit ($r.exit_code))(if ($r.stderr | is-not-empty) { $', stderr: ' + ($r.stderr | str trim) }).($cleanup)"}
    }
}

# Squid re-reads its whole config on reconfigure — including the files quoted
# from it, which is what the allowlist is — so an edited policy reaches a
# *running* proxy without a new container. Recreation no longer strands the
# cozy container — since the exit moved to a name, its hosts mapping follows the
# proxy wherever it lands — but in-place still wins: nothing moves, nothing
# needs re-mapping, and it works the same whether that container is up or
# stopped. This used to stop, delete and re-run the proxy for every edit.
#
# `-k parse` first is the safety, not a nicety. It validates in a separate
# process and signals only if that succeeds, so a bad list dies in the validator
# while the running squid keeps enforcing the previous one. Sending SIGHUP by
# hand (`kill -HUP 1`) has the opposite failure: squid exits mid-reconfigure on
# a fatal ACL error — an entry that is a subdomain of a wildcard entry is one —
# which takes the proxy down and forces exactly the recreate this avoids. `-k`
# also finds squid through its pid file instead of assuming it is PID 1 — which
# is what keeps this working now that the image is a rock and Pebble, not squid,
# is process 1. Verified against it: `-k reconfigure` exits 0 and the log shows
# `Reconfiguring Squid Cache (version 7.2)` followed by a re-read of the policy.
#
# What a running proxy will NOT pick up is a different `--policy` directory: the
# mount is fixed at creation, so only a recreated proxy can change which host
# folder it reads. Hence the message names the mount, not the host path.
def reload-policy []: nothing -> nothing {
    container-cli [exec $egress_name $squid_bin -k parse -f $policy_conf]
    container-cli [exec $egress_name $squid_bin -k reconfigure -f $policy_conf]
    print $"  (ansi green)Proxy:(ansi reset) ($egress_name) re-read its policy mount in place — same address, no restart"
}

def ensure-egress [policy: path reload: bool]: nothing -> nothing {
    let status = container-status $egress_name
    if $status == 'running' {
        if $reload {
            reload-policy
        } else {
            print $"  (ansi green)Proxy:(ansi reset) ($egress_name) already running"
        }
        return
    }

    # Not running, so there is nothing to reconfigure and a reload needs no
    # special case: a proxy reads the policy at startup anyway. Recreated rather
    # than started, because `run` is where the mount and the two networks are
    # declared and an existing container may carry older ones. This path can
    # move the address; callers re-map the cozy container's hosts line
    # afterwards (set-egress-hosts).
    if $status != 'absent' { container-cli [delete $egress_name] }

    # Dual-homed: `default` is the only way out, the caged network is the only
    # way in. Repeating --network is what Apple's maintainers point to for this;
    # it is the one flag here with no example in the reference docs.
    #
    # The whole policy directory, one mount — not the two files individually. A
    # bind-mounted *file* pins an inode, so an editor that saves atomically
    # leaves the proxy reading the old copy and the edit silently never applies.
    #
    # PEBBLE_VERBOSE, and `--args squid` before the squid arguments, are both the
    # rock's doing. Pebble owns the command line: the layer file declares
    # `command: /usr/local/bin/entrypoint.sh [ -f /etc/squid/squid.conf -NYC ]`,
    # where the brackets are *default* arguments that `--args <service>` replaces
    # — without it Pebble's own parser takes `-f` and dies with `unknown flag
    # 'f'`. And Pebble keeps a service's output to itself unless asked, so
    # without PEBBLE_VERBOSE `container logs` carries Pebble's lines and nothing
    # from squid, which silences the refusal log the allowlist is managed by.
    container-cli [
        run
        -d
        --name
        $egress_name
        --network
        default
        --network
        $caged_network
        -e
        PEBBLE_VERBOSE=1
        -v
        $"($policy):/etc/squid/policy:ro"
        $egress_image
        --args
        squid
        -f
        $policy_conf
        -NYC
    ]
    print $"  (ansi green)Proxy:(ansi reset) started ($egress_name) with ($policy)"
}

# Why: Apple `container` has no static-IP flag and its `inspect` schema is
# undocumented, so this used to ask the proxy for its own addresses with
# `exec hostname -I` and keep the one matching the caged subnet. That broke on an
# image without `hostname` in it: the exec fails, the loop finds nothing, and 15
# seconds later `restart` dies claiming the proxy never got an address — while
# the proxy is up and perfectly healthy. A minimal image is not a strange thing
# to meet here, so asking the container to run a program was the wrong question.
#
# The runtime already knows. `container ls --format json` carries
# `status.networks`, a row per attachment with `network` naming it and
# `ipv4Address` in CIDR form — so the caged one is selected by name rather than
# guessed from an address prefix, and the image needs to contain nothing at all.
# Retried because the address appears when the container's VM finishes booting,
# not when `run -d` returns.
def egress-address []: nothing -> string {
    mut found = []
    for _ in 1..15 {
        let r = ^container ls --all --format json | complete
        if $r.exit_code == 0 {
            $found = $r.stdout
                | from json
                | where configuration.id == $egress_name
                | get --optional 0.status.networks
                | default []
                | where network == $caged_network
                | get ipv4Address
                | each { split row '/' | first }
            if ($found | is-not-empty) { break }
        }
        sleep 1sec
    }
    if ($found | is-empty) {
        error make {msg: $"($egress_name) never got an address on ($caged_network) — check `container logs ($egress_name)` and that it is attached to it"}
    }
    $found | first
}

def proxy-url [host: string]: nothing -> string { $"http://($host):($proxy_port)" }

# The one mutable link between the cozy container and its exit. Nothing on this
# network keeps its address across a start (probed 2026-08-02: even the cozy
# container's own address moved on a plain stop/start), so its *_PROXY env
# carries the proxy's *name* — the convention compose.yaml already uses with
# `egress` — and this line maps the name to wherever the proxy is right now.
# /etc/hosts because a host-only network has no DNS; written as root because the
# `agent` user has no sudo (`exec --uid 0` works regardless — probed on
# container CLI 1.1.0). The
# runtime regenerates the file on every start, so a stale mapping cannot
# survive — but only starts made by this script write a fresh one. A bare
# `container start` leaves the name unresolvable (loud: "could not resolve host
# cozy-egress") until `restart` runs.
def set-egress-hosts [name: string ip: string]: nothing -> nothing {
    container-cli [exec --uid 0 $name sh -c $"sed -i '/ ($egress_name)$/d' /etc/hosts; echo '($ip) ($egress_name)' >> /etc/hosts"]
    print $"  (ansi green)Hosts:(ansi reset) ($egress_name) -> ($ip), mapped inside ($name)"
}

# Guard for containers created before the exit moved to a name: their env
# carries a fixed address, which cannot be updated on an existing container, so
# they cannot follow the proxy. A one-time recreation is the only fix.
def assert-exit-by-name [name: string]: nothing -> nothing {
    let r = ^container exec $name printenv HTTPS_PROXY | complete
    let baked = $r.stdout | str trim
    # `printenv` on an unset var exits 1 with both streams empty; an exec that
    # failed outright also has empty stdout but says why on stderr. Tell them
    # apart, or a broken exec reads as "not created by up". Checked only on the
    # failure path: successful execs can still carry runtime noise on stderr
    # (probed: a SIGWINCH complaint on exit 0).
    if $r.exit_code != 0 and ($r.stderr | str trim | is-not-empty) {
        error make {msg: $"could not read HTTPS_PROXY from ($name): ($r.stderr | str trim)"}
    }
    if ($baked | is-empty) {
        error make {msg: $"($name) has no HTTPS_PROXY — it was not created by `container.nu up`, so it has no exit at all \(a bare `container run` has no cage; `cozy verify`'s egress: rows fail on it by design)."}
    }
    if $baked != (proxy-url $egress_name) {
        error make {msg: $"($name) was built with the fixed exit ($baked) instead of the name (proxy-url $egress_name) — a baked address cannot be updated, so it cannot follow the proxy. Recreate it once: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>`."}
    }
}

# What every subcommand returns, so the three answer the same question in the
# same shape. Why return anything when the run already prints: `print` reaches
# stdout only — it cannot be piped, and the nushell MCP does not capture it, so
# a caller gets an empty result. toolkit/docs.nu returns its summary for exactly
# that reason. The prints stay; they narrate a slow build while it runs.
def summary [name: string state: string ip: string]: nothing -> record {
    {
        container: $name
        state: $state
        exit: (proxy-url $ip)
        proxy: $egress_name
        network: $caged_network
    }
}

# Forward the host's own git identity as COZY_GIT_USER_* so the human's commits
# inside the container are the human's. The image ships only the
# `Agent <agent@sandbox>` placeholder, and the agent's GIT_AUTHOR_* env still
# overrides everything for commits made from its shell — see the
# git-identity.nu autoload, which turns these into ~/.gitconfig on shell start.
# Read here rather than stored anywhere: this script runs on the host, where
# `git config --global` already holds the right answer, so no personal name or
# address has to live in the repo or the image.
def host-git-identity []: nothing -> list<string> {
    let id = ['user.name' 'user.email']
        | each {|k|
            let r = ^git config --global --get $k | complete
            # Exit 1 is git's "key not set" — the expected miss. Anything else
            # is a broken config, which must not read as "no identity".
            if $r.exit_code not-in [0 1] {
                error make {msg: $"`git config --global --get ($k)` failed \(exit ($r.exit_code)): ($r.stderr | str trim)"}
            }
            $r.stdout | str trim
        }
    # All or nothing — the same rule git-identity.nu enforces on the writing
    # side. Half an identity is worse than none: the other half falls through to
    # the placeholder and commits land as `Someone <agent@sandbox>`, a name that
    # never existed. Reported here too, because here we can say what is missing.
    if ($id | all {|v| $v | is-not-empty }) {
        print $"  (ansi green)You:(ansi reset) ($id.0) <($id.1)> — the agent still commits as Claude"
        [-e $"COZY_GIT_USER_NAME=($id.0)" -e $"COZY_GIT_USER_EMAIL=($id.1)"]
    } else {
        if ($id | any {|v| $v | is-not-empty }) {
            print $"  (ansi yellow)You:(ansi reset) host `git config --global` has only one of user.name/user.email — forwarding neither"
        }
        []
    }
}

# `path[:ro]` — the spelling `sbx run` uses for extra workspaces, kept identical
# so the two run paths take the same arguments.
def parse-workspace [entry: string]: nothing -> record<path: path, ro: bool> {
    let ro = $entry | str ends-with ':ro'
    let p = $entry | str replace --regex ':ro$' '' | path expand
    if not ($p | path exists) {
        error make {msg: $"workspace ($p) does not exist"}
    }
    {path: $p ro: $ro}
}

# Overlap in either direction, both slash-terminated so `cozy-2` never matches
# `cozy`: a path above the target hands the target over wholesale, and a path
# *inside* it hands over a piece — mounting cozy/toolkit is mounting this very
# script.
def paths-overlap [a: path b: path]: nothing -> bool {
    let a = (($a | path expand | str trim --right --char '/') + '/')
    let b = (($b | path expand | str trim --right --char '/') + '/')
    ($a | str starts-with $b) or ($b | str starts-with $a)
}

# Why: everything the agent can write is what builds the cage on the next launch
# — this script, the firewall template, and above all the live policy the proxy
# re-reads on every reload — so no writable mount may overlap the cozy repo or
# the policy directory. compose.yaml states the same rule for COZY_WORKSPACE but
# only in a comment; it has already been stepped on, so here it is an error.
# `:ro` is exempt because it removes exactly the ability the rule is about:
# reading is fine, editing is not.
def reject-writable [ws: record<path: path, ro: bool> policy: path]: nothing -> nothing {
    if $ws.ro { return }
    if (paths-overlap $ws.path $cozy_root) {
        error make {msg: $"workspace ($ws.path) overlaps the cozy repo — the agent would be able to edit this script and the firewall template, which are read fresh at the next launch. Pick a folder outside it, or mount it read-only as ($ws.path):ro."}
    }
    if (paths-overlap $ws.path $policy) {
        error make {msg: $"workspace ($ws.path) overlaps the firewall policy ($policy) — the agent would be able to edit its own allowlist, which the proxy re-reads on the next reload. Pick a folder outside it, or mount it read-only as ($ws.path):ro."}
    }
}

export def main []: nothing -> nothing {
    print "usage: nu toolkit/container.nu <up|restart|reload-egress|attach> ... — `--help` on each"
}

# `oneof<path, nothing>` because an unset `--policy` flag is null, and a bare
# `path` parameter refuses null before the body's `default` ever runs.
def resolve-policy [policy: oneof<path, nothing>]: nothing -> path {
    let dir = $policy | default ($nu.home-dir | path join .config cozy firewall) | path expand
    if not ($dir | path exists) {
        error make {msg: $"no policy at ($dir) — seed it once with `mkdir ~/.config/cozy; cp -r ($cozy_root)/firewall ~/.config/cozy/firewall`. Keeping it outside this repo is what makes the allowlist human-managed."}
    }
    $dir
}

# Start a cozy container behind a human-managed egress allowlist.
export def "main up" [
    name: string # name for the cozy container
    ...workspaces: string # host folders to mount, each at its own absolute path; the first is WORKSPACE_DIR and the default start dir. Append `:ro` for read-only
    --image: string = 'cozy:latest' # image built by `container build -t cozy:latest .`
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
    --workdir: path # start directory inside the container (default: the primary workspace)
    --memory: string = '8g' # RAM for the container VM (Apple `container` defaults to 1g)
    --cpus: int = 6 # CPUs for the container VM (Apple `container` defaults to 4)
]: nothing -> record {
    reject-proxy-name $name
    if ($workspaces | is-empty) {
        error make {msg: "no workspace given — `container.nu up <name> <folder> [more:ro ...]`"}
    }
    let ws_list = $workspaces | each {|e| parse-workspace $e }
    # Only the first one can be WORKSPACE_DIR: the variable is single-valued and
    # `cozy sandbox-state` writes into it. Same rule as `sbx run`, where the first
    # path is the primary workspace and the session starts there.
    let ws = $ws_list | first | get path

    let policy_dir = resolve-policy $policy

    # Every mount, not just the primary: an extra folder is as writable as the
    # first one, so the overlap rule has to cover all of them.
    for w in $ws_list { reject-writable $w $policy_dir }

    # `up` creates; an existing name means the user wants restart or
    # reload-egress, so abort before anything is touched. The check used to sit
    # *below* ensure-egress, which made the reload workflow destructive: it
    # stopped and deleted the proxy the running container pointed at (fatal
    # back when that container held the proxy's address rather than its name),
    # then aborted here with "a container named X already exists" — an error
    # the user reads as "nothing happened".
    if (container-status $name) != 'absent' {
        error make {msg: $"a container named ($name) already exists — `nu toolkit/container.nu restart ($name)` brings it back, `nu toolkit/container.nu reload-egress ($name)` applies an edited allowlist to it, or `container stop ($name); container delete ($name)` to rebuild it"}
    }

    ensure-network
    # --policy picks the directory only when the proxy is (re)created — a
    # running proxy keeps the mount it was created with. Explicitly asked for
    # and silently ignored must not look the same.
    if $policy != null and (container-status $egress_name) == 'running' {
        print $"  (ansi yellow)Policy:(ansi reset) ($egress_name) is already running and keeps the policy directory it was created with — `container stop ($egress_name)` first to have it recreated with ($policy_dir)"
    }
    ensure-egress $policy_dir false
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"

    # --no-dns: a host-only network has no resolver, so configuring one buys
    # nothing but a timeout per lookup. Clients reach allowed hosts by handing
    # the name to the proxy, which resolves it on the default network.
    #
    # The proxy variables are not the enforcement — the missing route is. They
    # only tell clients where the one exit is, so a blocked request gets a clean
    # 403 instead of hanging. They carry the proxy's *name*, not its address:
    # env cannot be changed on an existing container, and no address here
    # survives a start — the name plus a rewritable /etc/hosts line
    # (set-egress-hosts) is what lets `restart` reconnect the pair instead of
    # demanding a rebuild. WORKSPACE_DIR has no other source outside sbx, and
    # `cozy sandbox-state` and `cozy dev-link` hard-error without it.
    #
    # Why --memory: Apple `container` gives a VM 1g by default, and one Claude
    # Code process holds ~300MB. Two of them fill the cgroup, the page cache is
    # squeezed to nothing, and the kernel evicts the agents' own code pages and
    # faults them straight back in — 53M file refaults and 74% system CPU in five
    # minutes, with no OOM kill to end it. Nothing is throttled and nothing dies;
    # it just grinds. Headroom for the page cache is the fix, so the default is
    # raised here rather than left to the runtime.
    #
    # --cpus is raised past the runtime's 4 for the same reason as --memory:
    # a cozy container runs several agents plus their tool processes, not one.
    # It buys parallelism, not relief from the thrash above — that was never a
    # shortage of CPU. Keep it at or below the host's core count; the VM cannot
    # conjure cores it does not have, and oversubscribing only adds scheduling.
    #
    # Every folder is mounted at its own host path — the cozy convention, and the
    # one that keeps a path copied from the host valid inside the container.
    #
    # Spread into the one list literal rather than concatenating lists with `++`:
    # nushell parses a list literal against the parameter's `list<string>` type,
    # so `infinity` stays the string `sleep` wants. Behind `++` that hint is lost
    # and it becomes the float `inf`, which then fails the type check.
    let mounts = $ws_list | each {|w| [-v $"($w.path):($w.path)(if $w.ro { ':ro' } else { '' })"] } | flatten
    let git_identity = host-git-identity
    container-cli [
        run
        -d
        --name
        $name
        --network
        $caged_network
        --no-dns
        --memory
        $memory
        --cpus
        ($cpus | into string)
        -e
        $"WORKSPACE_DIR=($ws)"
        -e
        $"HTTP_PROXY=(proxy-url $egress_name)"
        -e
        $"HTTPS_PROXY=(proxy-url $egress_name)"
        -e
        $"http_proxy=(proxy-url $egress_name)"
        -e
        $"https_proxy=(proxy-url $egress_name)"
        -e
        'NO_PROXY=localhost,127.0.0.1,::1'
        ...$git_identity
        ...$mounts
        -w
        ($workdir | default $ws | path expand)
        $image
        sleep
        infinity
    ]
    let mounted = $ws_list | each {|w| $"($w.path)(if $w.ro { ' (ro)' } else { '' })" } | str join ', '
    print $"  (ansi green)Container:(ansi reset) ($name) on ($caged_network), workspace ($mounted)"
    # The cage first: assert-caged also carries the boot wait, so by the time it
    # returns the container can take the root exec the mapping needs.
    assert-caged $name
    set-egress-hosts $name $ip

    print ""
    print $"  attach:  use toolkit/container.nu; container attach ($name) --workdir ($ws)"
    print $"  check:   container exec ($name) nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'"
    print $"  refused: container logs -f ($egress_name)"

    summary $name running $ip | merge {workspaces: $ws_list}
}

# Apply an edited allowlist to a container that is already up.
#
# Why its own subcommand and not `up --reload-egress`: `up`'s workspaces are
# required, and on this path they were read and then ignored — an existing
# container's mounts cannot be changed, so retyping the folders did nothing and
# typing a *different* folder said nothing either. Nothing else `up` takes
# (--image, --memory, --cpus, --workdir) applies to a reload. What is left is the
# container's name, and it is needed for one thing only: if the reload had to
# recreate the proxy on a new address, that container's hosts mapping is
# rewritten here to follow it.
export def "main reload-egress" [
    name: string@"nu-complete container names" # the cozy container whose exit mapping is refreshed
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
]: nothing -> record {
    reject-proxy-name $name
    let policy_dir = resolve-policy $policy
    let container_state = container-status $name
    if $container_state == 'absent' {
        error make {msg: $"no container named ($name) — nothing to reload for. A new container reads the current allowlist at startup: `nu toolkit/container.nu up ($name) <folder>`"}
    }

    # Not ensure-network: recreating a missing network would leave the existing
    # container attached to nothing while this command prints "live" — the same
    # state restart refuses, refused the same way.
    if not (caged-network-exists) {
        error make {msg: $"($caged_network) is gone — ($name) has no cage, and a reload cannot re-attach it. Rebuild: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>` recreates the network."}
    }
    # Checked before the reload touches anything: a legacy container (fixed
    # exit) cannot follow a proxy that a recreation may move, and an error
    # *after* the policy already landed reads as "the reload failed".
    if $container_state == 'running' { assert-exit-by-name $name }
    ensure-egress $policy_dir true
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"

    if $container_state == 'running' {
        # Re-asserted even after an in-place reload, where the address did not
        # move — a no-op then, and one code path instead of two claims.
        set-egress-hosts $name $ip
        print $"  (ansi green)Done:(ansi reset) the edited allowlist is live for ($name)"
    } else {
        # A stopped container needs no mapping: the runtime regenerates /etc/hosts
        # at start anyway, and `restart` writes the line right after. Saying
        # "live" about a container that is not running is what this used to
        # print.
        print $"  (ansi green)Done:(ansi reset) ($name) is ($container_state) — the allowlist is live; `nu toolkit/container.nu restart ($name)` starts it and maps its exit"
    }

    summary $name $container_state $ip | merge {policy: $policy_dir}
}

# Bring the pair back after the runtime itself restarted (`container system
# stop/start`, an upgrade, a reboot), or after you stopped them for the day.
# Also the fix after a bare `container start <name>`: the runtime regenerates
# /etc/hosts at start, so the container's exit mapping exists only once restart
# rewrites it.
#
# Why its own subcommand and not `up --restart`: it shares the cage helpers with
# `up` and none of its build steps — no network to create, no mounts to parse,
# no run arguments. It also fills the one state `up` cannot recover from, both
# containers existing *stopped rather than absent*: a plain `up` aborts on
# "already exists". restart starts what exists — recreating the proxy if it is
# gone — and re-maps the container's exit to wherever the proxy came up.
export def "main restart" [
    name: string@"nu-complete container names" # the cozy container to bring back
    --policy: path # firewall policy directory, read only if the proxy is gone and must be recreated (default: ~/.config/cozy/firewall)
]: nothing -> record {
    reject-proxy-name $name
    let container_state = container-status $name
    if $container_state == 'absent' {
        error make {msg: $"no container named ($name) — nothing to restart. Create it: `nu toolkit/container.nu up ($name) <folder>`"}
    }

    # The one rebuild instruction left: the container was attached to the
    # network at creation, and nothing proves a container comes back into a
    # *recreated* network rather than around it — an unproven cage must not
    # come back quietly.
    if not (caged-network-exists) {
        error make {msg: $"($caged_network) is gone — ($name) has no cage to come back to. Rebuild both: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>` recreates the network."}
    }
    let egress_state = container-status $egress_name
    if $egress_state == 'absent' {
        # A gone proxy used to force rebuilding the cozy container too — its env
        # held the old address, unreachable and unchangeable. The container
        # points at the name now, so a fresh proxy on a fresh address is fine:
        # it is mapped below like any other.
        ensure-egress (resolve-policy $policy) false
    } else if $egress_state != 'running' {
        container-cli [start $egress_name]
        print $"  (ansi green)Proxy:(ansi reset) started ($egress_name)"
    } else {
        print $"  (ansi green)Proxy:(ansi reset) ($egress_name) already running"
    }
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"

    if $container_state != 'running' {
        container-cli [start $name]
        print $"  (ansi green)Container:(ansi reset) started ($name)"
    } else {
        print $"  (ansi green)Container:(ansi reset) ($name) already running"
    }

    # The cage first, the exit second: a cage that came back open is a leak and
    # assert-caged stops the container over it, while a missing exit only leaves
    # the container with no way out. The restart is also where the cage is most
    # worth re-proving — the runtime rebuilt the network, we did not.
    assert-caged $name

    # Reconnect the exit: wherever the proxy came back, the container's hosts
    # line follows it. This repair is what restart is for — before the exit
    # moved to a name, all it could do here was detect the mismatch and demand a
    # rebuild.
    assert-exit-by-name $name
    set-egress-hosts $name $ip

    print ""
    print $"  attach:  use toolkit/container.nu; container attach ($name)"
    print $"  refused: container logs -f ($egress_name)"

    summary $name running $ip
}

# Open the cozy container in a new WezTerm window, attached to its zellij
# session — the `container` twin of `toolkit/sbxw.nu`.
#
# Unlike `up` and `restart`, this one cannot be run as a script: the window is a
# background job and a job dies with the nu that spawned it. Run it from an
# interactive nu instead — `use toolkit/container.nu`, then `container attach`.
export def "main attach" [
    name: string@"nu-complete container names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
    --zellij-session: string = '' # zellij session name to use instead of the container name
    --workdir: path # start directory inside the container
]: nothing -> any {   # the window's job id — `job kill` it to close the window
    # Why --cwd: `container` has no notion of a workspace, so an exec starts
    # wherever the image left WORKDIR — pass it when the start directory matters.
    let exec_argv = [container exec -it]
        | append (if ($workdir | is-not-empty) { [--cwd $workdir] } else { [] })
        | append $name

    attach-window $exec_argv ($zellij_session | default --empty $name) --config-file $config_file --background $background --no-job=$no_job
}

# `main <sub>` is the name the script path dispatches on (`nu toolkit/container.nu
# up …`), but a module imports it as `container main up` — nushell collapses only
# bare `main` into the module name. These aliases drop that `main` for module
# users, so the same four commands read the same way both ways. attach is not
# merely nicer for it: it has to be called from an imported module.
export alias up = main up
export alias restart = main restart
export alias reload-egress = main reload-egress
export alias attach = main attach
