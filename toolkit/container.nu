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
#   nu toolkit/container.nu up my-cozy ~/path/to/project --ssh-agent  # sign with the host's keys
#   nu toolkit/container.nu restart my-cozy         # or just attach, which restarts a stopped pair
#   nu toolkit/container.nu reload-egress my-cozy   # after editing the allowlist
#   nu toolkit/container.nu refresh-egress          # move the pin to upstream's newest
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
#
# Why `--unspanned` on some errors and not others: a span prints the raise site
# plus that source line, which re-shows the message uninterpolated — a debugging
# anchor when an invariant broke, pure noise when the user just has to act. So a
# normal situation carrying its own fix (name taken, no workspace, no policy,
# wrong container) is raised unspanned; an unexpected one (a `container` call
# failed, the cage is open, upstream changed shape) keeps its span.

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
# throwaway container before it goes near the running cage; `refresh-egress`
# below is that rehearsal, and it proved this one.
const egress_image = 'ubuntu/squid@sha256:6c919903a7a60f3ddd27735cab4516e2991420d49dfc3247e5228de994172d8b'
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

# What `refresh-egress` needs to move the pin forward. The pin stays a digest —
# what changes is that finding the next one costs a command instead of an
# afternoon.
const egress_repo = 'ubuntu/squid'
# `latest` and `edge` are dead: upstream last moved them in Dec 2025, and they
# still resolve to a squid 6.6 build. The maintained stream is the tags naming
# both versions, `<squid>-<ubuntu>_edge`, so that is the family to search.
const egress_tag_pattern = '^\d+\.\d+-\d+\.\d+_edge$'
# The digest lives in exactly two files and in this one shape, which is what
# lets one regex rewrite both and `toolkit/check.nu egress-image` keep guarding
# them against each other.
const pin_pattern = 'ubuntu/squid@sha256:[0-9a-f]{64}'
const compose_yaml = ($cozy_root | path join 'compose.yaml')
const this_file = (path self)
# A name of its own so nothing here can touch the live proxy, whatever fails.
const rehearsal_name = 'cozy-egress-rehearsal'

# Why: every `container` call goes through here so an unsupported flag surfaces
# as the failing command and its stderr. Apple `container` is young and this
# script is written against its documentation, not against a machine — the first
# run is where the flags get proven, and a silent empty result would hide that.
#
# Arguments arrive in groups — a flag and its value per inner list — and are
# flattened here. Not one flat list, because topiary explodes a multi-line list
# to one token per line: that turned the two `run` invocations into 30-line
# ladders where a flag sat nowhere near its value. A list of single-line lists
# survives the formatter, so a call site reads like the command it runs.
#
# `list<list<string>>` is also what keeps every bareword a string. Nushell types
# a list literal against the parameter, and under `list<any>` (or behind `++`)
# the `infinity` that `sleep` wants becomes the float `inf` and fails the type
# check. The nesting is what carries that hint down to each group.
def container-cli [args: list<list<string>>]: nothing -> string {
    let argv = $args | flatten
    let r = ^container ...$argv | complete
    if $r.exit_code != 0 {
        error make {msg: $"`container ($argv | str join ' ')` failed:\n($r.stderr | str trim)"}
    }
    $r.stdout
}

# `container ls --format json` keys the name under configuration.id and the run
# state under status.state — `status` is a record (state, networks,
# startedDate), not a string.
def container-status [name: string]: nothing -> string {
    let rows = container-cli [[ls --all --format json]] | from json | where configuration.id == $name
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
        error make --unspanned {msg: $"($egress_name) is the egress proxy, not a cozy container. It is managed for you: `up` and `restart` start or recreate it, and `reload-egress <container>` applies an edited allowlist to it."}
    }
}

# Why whole tokens and not `str contains`: the substring test also accepted a
# leftover `cozy-caged-old` and returned "already up" for a network that isn't
# ours. `network ls --format json` would be exact, but Apple's ls/inspect schema
# is undocumented (see egress-address), so compare whitespace-separated tokens —
# that needs no column layout and no key names.
def caged-network-exists []: nothing -> bool {
    let names = container-cli [[network list]] | split row --regex '\s+'
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
    container-cli [[network create --internal --subnet $caged_subnet $caged_network]]
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

# Everything here waits on the same thing: a container VM that is still booting
# after `run -d` or `start` has returned. Three call sites hand-rolled the same
# `mut` + `for 1..15` + `sleep 1sec` shape, and each of them also slept once more
# after the attempt it was never going to retry. `null` from the closure means
# "not ready yet"; the first non-null answer is the result.
def poll [attempts: int action: closure]: nothing -> any {
    for i in 1..$attempts {
        let r = do $action
        if $r != null { return $r }
        if $i != $attempts { sleep 1sec }
    }
    null
}

def assert-caged [name: string]: nothing -> nothing {
    # Retried for the same reason egress-address is: `run -d` and `start` return
    # before the container's VM has finished booting, so the first execs fail
    # with nothing on stdout. An empty stdout is "not ready yet"; curl always
    # prints a status, even for a connection that never happened.
    # Every attempt came back empty: no status to judge, which the checks below
    # treat as an unproven cage — the same verdict the old empty-string default
    # produced.
    #
    # Defaulted to a whole record rather than reading `stdout` with
    # `get --optional`: the error message at the bottom reads `exit_code` and
    # `stderr` off this same value, and on a `null` those two raised "Data
    # cannot be accessed with a cell path" — replacing the cage diagnosis with a
    # nushell internal at exactly the moment the probe never answered.
    let probe = poll 15 {
        let r = ^container exec $name curl --silent --show-error --noproxy '*' --max-time 10 --output /dev/null --write-out '%{http_code}' $direct_probe | complete
        if ($r.stdout | str trim | is-empty) { null } else { $r }
    } | default {stdout: '' stderr: '' exit_code: 0}
    let code = $probe.stdout | str trim
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
        error make {msg: $"could not probe the cage from ($name): curl gave no status \(exit ($probe.exit_code))(if ($probe.stderr | is-not-empty) { $', stderr: ' + ($probe.stderr | str trim) }).($cleanup)"}
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
    container-cli [[exec $egress_name] [$squid_bin -k parse -f $policy_conf]]
    container-cli [[exec $egress_name] [$squid_bin -k reconfigure -f $policy_conf]]
    print $"  (ansi green)Proxy:(ansi reset) ($egress_name) re-read its policy mount in place — same address, no restart"
}

def ensure-egress [policy: path reload: bool]: nothing -> nothing {
    # The pin this *loaded copy* of the module carries — not necessarily what is
    # running. Why print it at all: the failure it makes visible is a stale
    # module. A REPL that did `use toolkit` before the pin moved recreates the
    # proxy from the old digest and still prints the usual green summary; the
    # squid 7.2 swap was nearly recorded as done that way, caught only by an
    # unrelated `container exec` afterwards. Silent wrong beats loud wrong is
    # backwards — so the code says out loud which pin it is acting on.
    print $"  (ansi green)Pin:(ansi reset) ($egress_image)"

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
    if $status != 'absent' { container-cli [[delete $egress_name]] }

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
        [run --detach]
        [--name $egress_name]
        [--network default]
        [--network $caged_network]
        [--env PEBBLE_VERBOSE=1]
        [--volume $"($policy):/etc/squid/policy:ro"]
        [$egress_image]
        [--args squid -f $policy_conf -NYC]
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
    let found = poll 15 {
        let r = ^container ls --all --format json | complete
        if $r.exit_code != 0 { return null }
        let addrs = $r.stdout
            | from json
            | where configuration.id == $egress_name
            | get --optional 0.status.networks
            | default []
            | where network == $caged_network
            | get ipv4Address
            | each { split row '/' | first }
        if ($addrs | is-empty) { null } else { $addrs }
    }
    if $found == null {
        error make {msg: $"($egress_name) never got an address on ($caged_network) — check `container logs ($egress_name)` and that it is attached to it"}
    }
    let ip = $found | first
    # Printed here rather than at each call site: all three printed this exact
    # line right after calling, and none of them varied it.
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"
    $ip
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
    container-cli [
        [exec --uid 0 $name]
        [sh -c $"sed --in-place '/ ($egress_name)$/d' /etc/hosts; echo '($ip) ($egress_name)' >> /etc/hosts"]
    ]
    print $"  (ansi green)Hosts:(ansi reset) ($egress_name) -> ($ip), mapped inside ($name)"
}

# The other half of --no-dns, which the flag cannot deliver on its own: it stops
# the runtime from *writing* a resolver, but the Debian base image already
# carries one — debuerreotype (the builder behind the official images) writes
# `nameserver 1.1.1.1` into every debian:*-slim. On the cage that address is
# unreachable, and the host-only network's default route black-holes the packets
# instead of refusing them, so each lookup waits out the glibc default: 5s
# timeout x 2 attempts x 2 nameservers = 20s. Measured on a live container as a
# 20.7s `git fetch`, all of it inside git-remote-https, but nothing is spared —
# apt, brew and any curl to a new host pay the same. Harmless before the cage
# landed (0d6ddff): on the default network 1.1.1.1 answered.
#
# Emptying the file is the fix, not shortening the timeout: with no nameserver
# line glibc falls back to 127.0.0.1, which refuses instantly. Nothing is lost —
# names are resolved by the proxy, and ($egress_name) comes from /etc/hosts.
#
# Unlike /etc/hosts the runtime does not regenerate this file, so one write lasts
# the container's life. Re-asserted on every start anyway: that is what repairs a
# container created before this existed.
def clear-resolver [name: string]: nothing -> nothing {
    container-cli [
        [exec --uid 0 $name]
        [sh -c $"echo '# cozy: no resolver — ($egress_name) resolves names' > /etc/resolv.conf"]
    ]
    print $"  (ansi green)Resolver:(ansi reset) cleared in ($name) — the cage has none, and the image's 1.1.1.1 costs 20s a lookup"
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
        error make --unspanned {msg: $"($name) has no HTTPS_PROXY — it was not created by `container.nu up`, so it has no exit at all \(a bare `container run` has no cage; `cozy verify`'s egress: rows fail on it by design)."}
    }
    if $baked != (proxy-url $egress_name) {
        error make --unspanned {msg: $"($name) was built with the fixed exit ($baked) instead of the name (proxy-url $egress_name) — a baked address cannot be updated, so it cannot follow the proxy. Recreate it once: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>`."}
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
    if ($id | all { is-not-empty }) {
        print $"  (ansi green)You:(ansi reset) ($id.0) <($id.1)> — the agent still commits as Claude"
        [--env $"COZY_GIT_USER_NAME=($id.0)" --env $"COZY_GIT_USER_EMAIL=($id.1)"]
    } else {
        if ($id | any { is-not-empty }) {
            print $"  (ansi yellow)You:(ansi reset) host `git config --global` has only one of user.name/user.email — forwarding neither"
        }
        []
    }
}

# `--ssh` is a boolean flag on `container run` and `container create`: the
# runtime mounts the host's agent socket into the container and sets the guest's
# own SSH_AUTH_SOCK to /var/host-services/ssh-auth.sock. So there is deliberately
# no `-e SSH_AUTH_SOCK` alongside it — the guest path belongs to the runtime, and
# a hand-written one would only fight it. Read off apple/container rather than
# guessed: `sshAuthSocketGuestPath` in Sources/Services/RuntimeLinux/Server/
# RuntimeService.swift, and the flag itself in Sources/Services/
# ContainerAPIService/Client/Flags.swift.
#
# Nothing is needed in `restart` or `attach`: `ssh: true` is stored in the
# container's configuration, and `container start` re-reads the *host's* current
# SSH_AUTH_SOCK on every start. That is the whole advantage over mounting the
# socket by hand — the mount follows an agent that moved across a logout instead
# of pointing at a dead path.
#
# What this does NOT buy inside the cage: git over ssh. squid allows CONNECT to
# 443 only, and ssh cannot speak to an HTTP proxy at all, so a `git@github.com:`
# remote fails here whatever the agent holds — README's "Egress firewall" already
# says so, and the error it produces blames your credentials instead. What the
# forwarded agent does buy is signing, which needs no network: with `git config
# gpg.format ssh` the host's key signs commits made inside the container without
# the key ever entering it.
def ssh-agent-args [enabled: bool]: nothing -> list<string> {
    if not $enabled { return [] }

    # Upstream only *logs a warning* when SSH_AUTH_SOCK is missing, then starts
    # the container with no socket at all: an explicitly requested forward that
    # silently did not happen, discovered much later inside the container. Refused
    # here instead, where the cause is still in hand.
    let sock = $env.SSH_AUTH_SOCK? | default ''
    if ($sock | is-empty) {
        error make --unspanned {msg: "--ssh-agent needs SSH_AUTH_SOCK and this shell has none. On macOS adding a key starts the system agent: `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`."}
    }
    if not ($sock | path exists) {
        error make --unspanned {msg: $"SSH_AUTH_SOCK names ($sock), which does not exist — the agent it points at is gone. Open a fresh login shell, or start one with `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`."}
    }

    # `ssh-add -l` exit 1 is "the agent answers but holds no keys" — a warning,
    # not an error: what gets mounted is a live socket, so a key added on the
    # host afterwards is usable inside immediately, with no recreation. Exit 2 is
    # "nothing answers at that socket", which is the same broken state as the
    # missing path above and is refused the same way.
    let r = ^ssh-add -l | complete
    if $r.exit_code == 2 {
        error make --unspanned {msg: $"SSH_AUTH_SOCK is ($sock) but no agent answers there: ($r.stderr | str trim)"}
    }
    if $r.exit_code == 1 {
        print $"  (ansi yellow)Agent:(ansi reset) the host agent currently holds no keys — `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` adds one, and it works inside without a restart"
    } else {
        # The count and nothing else. Fingerprints are not secret, but no part of
        # this job needs one printed, and key material must never pass through
        # this script at all.
        let n = $r.stdout | lines | where $it != '' | length
        # Spelled out rather than `key\(s)`: the escape works in `$"..."`, but a
        # parenthesis inside an interpolated string is this codebase's most
        # repeated mistake and is not worth risking for a plural.
        let word = if $n == 1 { 'key' } else { 'keys' }
        print $"  (ansi yellow)Agent:(ansi reset) forwarding the host ssh-agent, ($n) ($word) — anything inside the container can sign with them while it runs, though it can never read them. Prefer a key dedicated to this over your personal one."
    }
    [--ssh]
}

# The builder checks what it built — the same rule as assert-caged. A forward
# that did not land must not read as success, and the socket is one `exec` away.
# Exit 1 counts as reachable: an agent holding no keys still proves the socket
# arrived, which is all this asserts.
def assert-agent-reachable [name: string]: nothing -> nothing {
    let r = ^container exec $name ssh-add -l | complete
    if $r.exit_code not-in [0 1] {
        error make --unspanned {msg: $"($name) started, but `ssh-add -l` inside it cannot reach the forwarded agent, exit ($r.exit_code): ($r.stderr | str trim). Recreate it without --ssh-agent, or check that the host agent is still alive."}
    }
    print $"  (ansi green)Agent:(ansi reset) ($name) reaches the forwarded agent at /var/host-services/ssh-auth.sock"
}

# `path[:ro]` — the spelling `sbx run` uses for extra workspaces, kept identical
# so the two run paths take the same arguments.
def parse-workspace [entry: string]: nothing -> record<path: path, ro: bool> {
    let ro = $entry | str ends-with ':ro'
    let p = $entry | str replace --regex ':ro$' '' | path expand
    if not ($p | path exists) {
        error make --unspanned {msg: $"workspace ($p) does not exist"}
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
        error make --unspanned {msg: $"workspace ($ws.path) overlaps the cozy repo — the agent would be able to edit this script and the firewall template, which are read fresh at the next launch. Pick a folder outside it, or mount it read-only as ($ws.path):ro."}
    }
    if (paths-overlap $ws.path $policy) {
        error make --unspanned {msg: $"workspace ($ws.path) overlaps the firewall policy ($policy) — the agent would be able to edit its own allowlist, which the proxy re-reads on the next reload. Pick a folder outside it, or mount it read-only as ($ws.path):ro."}
    }
}

export def main []: nothing -> nothing {
    print "usage: nu toolkit/container.nu <up|restart|reload-egress|refresh-egress|attach> ... — `--help` on each"
}

# `oneof<path, nothing>` because an unset `--policy` flag is null, and a bare
# `path` parameter refuses null before the body's `default` ever runs.
def resolve-policy [policy: oneof<path, nothing>]: nothing -> path {
    let dir = $policy | default ($nu.home-dir | path join .config cozy firewall) | path expand
    if not ($dir | path exists) {
        error make --unspanned {msg: $"no policy at ($dir) — seed it once with `mkdir ~/.config/cozy; cp -r ($cozy_root)/firewall ~/.config/cozy/firewall`. Keeping it outside this repo is what makes the allowlist human-managed."}
    }
    $dir
}

# Start a cozy container behind a human-managed egress allowlist.
def "main up" [
    name: string # name for the cozy container
    ...workspaces: string # host folders to mount, each at its own absolute path; the first is WORKSPACE_DIR and the default start dir. Append `:ro` for read-only
    --image: string = 'cozy:latest' # image built by `container build --tag cozy:latest .`
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
    --workdir: path # start directory inside the container (default: the primary workspace)
    --memory: string = '8g' # RAM for the container VM (Apple `container` defaults to 1g)
    --cpus: int = 6 # CPUs for the container VM (Apple `container` defaults to 4)
    --ssh-agent # forward the host's ssh-agent socket, so the container can sign with your keys without holding them. Inside the cage this is for signing only — ssh cannot cross the HTTP proxy, so `git@github.com:` remotes still fail
]: nothing -> record {
    reject-proxy-name $name
    if ($workspaces | is-empty) {
        error make --unspanned {msg: "no workspace given — `container.nu up <name> <folder> [more:ro ...]`"}
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
        error make --unspanned {msg: $"a container named ($name) already exists — `nu toolkit/container.nu restart ($name)` brings it back, `nu toolkit/container.nu reload-egress ($name)` applies an edited allowlist to it, or `container stop ($name); container delete ($name)` to rebuild it"}
    }

    # Before ensure-network, deliberately: this reads only the host and can only
    # say no, and everything below it creates something. The same lesson the
    # already-exists check above carries — a refusal that lands after a network
    # and a proxy were built reads as "nothing happened" and leaves both behind.
    let ssh_args = ssh-agent-args $ssh_agent

    ensure-network
    # --policy picks the directory only when the proxy is (re)created — a
    # running proxy keeps the mount it was created with. Explicitly asked for
    # and silently ignored must not look the same.
    if $policy != null and (container-status $egress_name) == 'running' {
        print $"  (ansi yellow)Policy:(ansi reset) ($egress_name) is already running and keeps the policy directory it was created with — `container stop ($egress_name)` first to have it recreated with ($policy_dir)"
    }
    ensure-egress $policy_dir false
    let ip = egress-address

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
    # The three computed lists go in as groups of their own rather than spread
    # with `...`: container-cli takes list<list<string>>, so a list<string>
    # variable already is one group, and an empty one flattens away to nothing.
    # Never concatenate them with `++` — that loses the type hint the literal
    # carries, and the `infinity` at the bottom becomes the float `inf`, which
    # `sleep` then refuses.
    let mounts = $ws_list | each {|w| [--volume $"($w.path):($w.path)(if $w.ro { ':ro' } else { '' })"] } | flatten
    let git_identity = host-git-identity
    container-cli [
        [run --detach]
        [--name $name]
        [--network $caged_network]
        [--no-dns]
        [--memory $memory]
        [--cpus ($cpus | into string)]
        [--env $"WORKSPACE_DIR=($ws)"]
        [--env $"HTTP_PROXY=(proxy-url $egress_name)"]
        [--env $"HTTPS_PROXY=(proxy-url $egress_name)"]
        [--env $"http_proxy=(proxy-url $egress_name)"]
        [--env $"https_proxy=(proxy-url $egress_name)"]
        [--env 'NO_PROXY=localhost,127.0.0.1,::1']
        $git_identity
        $ssh_args
        $mounts
        [--workdir ($workdir | default $ws | path expand)]
        [$image sleep infinity]
    ]
    let mounted = $ws_list | each {|w| $"($w.path)(if $w.ro { ' (ro)' } else { '' })" } | str join ', '
    print $"  (ansi green)Container:(ansi reset) ($name) on ($caged_network), workspace ($mounted)"
    # The cage first: assert-caged also carries the boot wait, so by the time it
    # returns the container can take the root exec the mapping needs.
    assert-caged $name
    set-egress-hosts $name $ip
    clear-resolver $name
    if $ssh_agent { assert-agent-reachable $name }

    print ""
    print $"  attach:  use toolkit/container.nu; container attach ($name) --workdir ($ws)"
    print $"  check:   container exec ($name) nu --commands 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'"
    print $"  refused: container logs --follow ($egress_name)"

    summary $name running $ip | merge {workspaces: $ws_list ssh_agent: $ssh_agent}
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
def "main reload-egress" [
    name: string@"nu-complete container names" # the cozy container whose exit mapping is refreshed
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
]: nothing -> record {
    reject-proxy-name $name
    let policy_dir = resolve-policy $policy
    let container_state = container-status $name
    if $container_state == 'absent' {
        error make --unspanned {msg: $"no container named ($name) — nothing to reload for. A new container reads the current allowlist at startup: `nu toolkit/container.nu up ($name) <folder>`"}
    }

    # Not ensure-network: recreating a missing network would leave the existing
    # container attached to nothing while this command prints "live" — the same
    # state restart refuses, refused the same way.
    if not (caged-network-exists) {
        error make --unspanned {msg: $"($caged_network) is gone — ($name) has no cage, and a reload cannot re-attach it. Rebuild: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>` recreates the network."}
    }
    # Checked before the reload touches anything: a legacy container (fixed
    # exit) cannot follow a proxy that a recreation may move, and an error
    # *after* the policy already landed reads as "the reload failed".
    if $container_state == 'running' { assert-exit-by-name $name }
    ensure-egress $policy_dir true
    let ip = egress-address

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
def "main restart" [
    name: string@"nu-complete container names" # the cozy container to bring back
    --policy: path # firewall policy directory, read only if the proxy is gone and must be recreated (default: ~/.config/cozy/firewall)
]: nothing -> record {
    reject-proxy-name $name
    let container_state = container-status $name
    if $container_state == 'absent' {
        error make --unspanned {msg: $"no container named ($name) — nothing to restart. Create it: `nu toolkit/container.nu up ($name) <folder>`"}
    }

    # The one rebuild instruction left: the container was attached to the
    # network at creation, and nothing proves a container comes back into a
    # *recreated* network rather than around it — an unproven cage must not
    # come back quietly.
    if not (caged-network-exists) {
        error make --unspanned {msg: $"($caged_network) is gone — ($name) has no cage to come back to. Rebuild both: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>` recreates the network."}
    }
    let egress_state = container-status $egress_name
    if $egress_state == 'absent' {
        # A gone proxy used to force rebuilding the cozy container too — its env
        # held the old address, unreachable and unchangeable. The container
        # points at the name now, so a fresh proxy on a fresh address is fine:
        # it is mapped below like any other.
        ensure-egress (resolve-policy $policy) false
    } else if $egress_state != 'running' {
        container-cli [[start $egress_name]]
        print $"  (ansi green)Proxy:(ansi reset) started ($egress_name)"
    } else {
        print $"  (ansi green)Proxy:(ansi reset) ($egress_name) already running"
    }
    let ip = egress-address

    if $container_state != 'running' {
        container-cli [[start $name]]
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
    clear-resolver $name

    print ""
    print $"  attach:  use toolkit/container.nu; container attach ($name)"
    print $"  refused: container logs --follow ($egress_name)"

    summary $name running $ip
}

# Open the cozy container in a new WezTerm window, attached to its zellij
# session — the `container` twin of `toolkit/sbxw.nu`.
#
# Unlike `up` and `restart`, this one cannot be run as a script: the window is a
# background job and a job dies with the nu that spawned it. Run it from an
# interactive nu instead — `use toolkit/container.nu`, then `container attach`.
#
# Restarts the pair first when the container is not running, so this is also the
# whole launch path after the runtime itself came back.
def "main attach" [
    name: string@"nu-complete container names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
    --zellij-session: string = '' # zellij session name to use instead of the container name
    --workdir: path # start directory inside the container
    --policy: path # firewall policy directory, read only if the pair has to be restarted and the proxy is gone (default: ~/.config/cozy/firewall)
]: nothing -> any {
    # the window's job id — `job kill` it to close the window

    # A stopped container used to get a window regardless: `container exec -it`
    # cannot enter one, so the window opened on that error and nothing was said
    # here. Stopped is exactly what a runtime restart (`container system
    # stop/start`, an upgrade, a reboot) leaves behind, and the command a human
    # reaches for then is this one — `restart` is the one they have to remember
    # instead. So bring the pair back rather than open a window on a corpse:
    # restart starts the proxy, starts the container, re-proves the cage and
    # re-maps the exit, and the window then lands on something that answers.
    #
    # Not offered as a flag: a window on a container that is not running has no
    # other meaning to ask about.
    if (container-status $name) != 'running' {
        # Why the same call twice: an unset flag is null and `--policy: path`
        # rejects null at parse time, so "the flag was not given" cannot be
        # forwarded as a value.
        if $policy == null { main restart $name } else { main restart $name --policy $policy }
    }

    # Why --cwd: `container` has no notion of a workspace, so an exec starts
    # wherever the image left WORKDIR — pass it when the start directory matters.
    let exec_argv = [container exec --interactive --tty]
        | append (if ($workdir | is-not-empty) { [--cwd $workdir] } else { [] })
        | append $name

    attach-window $exec_argv ($zellij_session | default --empty $name) --config-file $config_file --background $background --no-job=$no_job
}

# Upstream's newest image in the maintained tag family. Errors rather than
# returning nothing, because a refresh that quietly found nothing to do looks
# exactly like one that could not reach the registry.
def newest-egress-tag []: nothing -> record {
    let body = try {
        http get $"https://hub.docker.com/v2/repositories/($egress_repo)/tags?page_size=100&ordering=last_updated"
    } catch {|e|
        error make {msg: $"could not reach Docker Hub to look for a newer proxy image: ($e.msg). Nothing was changed — the pin in the repo still names the image you are running."}
    }
    # `digest?`: some tags carry none at all. Where it is present it is the
    # multi-arch index digest, which is the kind the pin is — the per-platform
    # digests under `images` would never match it.
    let candidates = $body
        | get results
        | select name last_updated digest?
        | where name =~ $egress_tag_pattern
        | where digest != null
        | sort-by last_updated --reverse
    if ($candidates | is-empty) {
        error make {msg: $"no tag in ($egress_repo) matched ($egress_tag_pattern) with a digest. Upstream's tag naming has changed, so the search itself has to be re-read before its answer can be trusted — `http get https://hub.docker.com/v2/repositories/($egress_repo)/tags?page_size=100&ordering=last_updated | get results.name` prints the current list."}
    }
    $candidates | first
}

# Prove a candidate before it is written anywhere: it must come up, take our
# policy, and answer `-k parse`. Its own name, no networks, so the live proxy
# keeps running throughout and a candidate that fails costs only the time to
# find out.
#
# The launch shape is deliberately the same one ensure-egress uses. The thing
# being tested is our invocation against their image: when upstream changed the
# contract — a rock, `pebble enter`, `squid-gnutls` — the invocation is what
# broke, and this is where that must surface, rather than in a dead cage at a
# moment nobody chose.
def rehearse-egress [image: string policy: path]: nothing -> nothing {
    ^container stop $rehearsal_name | complete | ignore
    ^container delete $rehearsal_name | complete | ignore

    container-cli [
        [run --detach]
        [--name $rehearsal_name]
        [--env PEBBLE_VERBOSE=1]
        [--volume $"($policy):/etc/squid/policy:ro"]
        [$image]
        [--args squid -f $policy_conf -NYC]
    ]

    let listening = (
        poll 15 {
            let r = ^container logs $rehearsal_name | complete
            if (($r.stdout + $r.stderr) | str contains 'listening port') { true } else { null }
        } | default false
    )
    let parse = ^container exec $rehearsal_name $squid_bin -k parse -f $policy_conf | complete
    let logs = ^container logs $rehearsal_name | complete

    # Cleaned up before anything is raised: a failed rehearsal must not leave a
    # container behind for the next run to trip over.
    ^container stop $rehearsal_name | complete | ignore
    ^container delete $rehearsal_name | complete | ignore

    if not $listening {
        error make {msg: $"($image) never reported a listening port. The image's contract has probably changed again — check the launch arguments and the entrypoint before trusting it. The repo still pins ($egress_image), which is untouched.\n\nWhat it logged:\n($logs.stdout | str trim)\n($logs.stderr | str trim)"}
    }
    if $parse.exit_code != 0 {
        error make {msg: $"($image) came up but `($squid_bin) -k parse` failed, so the policy and this squid disagree. The repo still pins ($egress_image), which is untouched.\n\n($parse.stderr | str trim)"}
    }
}

# Both files are checked before either is written: a half-applied pin would
# leave the two run paths enforcing different proxies, which is the one thing
# `toolkit/check.nu egress-image` exists to prevent.
def write-egress-pin [digest: string]: nothing -> nothing {
    let files = [$this_file $compose_yaml]
    for file in $files {
        let hits = open --raw $file | lines | where $it =~ $pin_pattern | length
        if $hits != 1 {
            error make {msg: $"expected exactly one pinned digest in ($file), found ($hits) — nothing was rewritten. Both run paths must carry the same single literal; fix the file by hand and re-run."}
        }
    }
    for file in $files {
        open --raw $file | str replace --regex $pin_pattern $"($egress_repo)@($digest)" | save --force $file
    }
}

# Move the pin forward: ask upstream what is newest, prove it on a throwaway
# container, then write it into both files.
#
# Why a command and not a floating tag in the image field: compose.yaml cannot
# compute anything, so a self-updating pin would work on this path only and the
# two paths would drift — and they must enforce the identical proxy. Keeping the
# refresh a command keeps one literal in both files, keeps the repo an accurate
# record of what is running, and puts the moment a new image is adopted where a
# human is present. That last part is the point: the move to squid 7.2 failed to
# start at all, and meeting that here is a different thing from meeting it when
# the cage is needed.
def "main refresh-egress" [
    --policy: path # firewall policy directory used for the rehearsal (default: ~/.config/cozy/firewall)
]: nothing -> record {
    let policy_dir = resolve-policy $policy
    let current = $egress_image | split row '@' | last
    let newest = newest-egress-tag
    print $"  (ansi green)Upstream:(ansi reset) newest is ($newest.name), updated ($newest.last_updated)"

    if $newest.digest == $current {
        print $"  (ansi green)Pin:(ansi reset) already current — nothing to write"
        return {tag: $newest.name digest: $newest.digest changed: false}
    }

    print $"  (ansi yellow)Rehearsing:(ansi reset) ($newest.name) as ($rehearsal_name) — ($egress_name) keeps running"
    rehearse-egress $"($egress_repo)@($newest.digest)" $policy_dir
    print $"  (ansi green)Rehearsal:(ansi reset) came up, took the policy, answered -k parse"

    write-egress-pin $newest.digest
    print $"  (ansi green)Pin:(ansi reset) rewritten in compose.yaml and toolkit/container.nu"
    print ""
    print $"  review: git diff"
    print $"  adopt:  container stop ($egress_name); container delete ($egress_name); nu toolkit/container.nu restart <container>"

    {tag: $newest.name digest: $newest.digest changed: true}
}

# `main <sub>` is the name the script path dispatches on (`nu toolkit/container.nu
# up …`), but a module import leaves that `main` in the middle
# (`container main up`) — nushell collapses only the bare `main` into a module
# name. These aliases are what a module user calls, so both forms read the same.
#
# The defs above are deliberately not exported, and that is the half that was
# missing: exporting both put every command in the list twice, once as itself
# and once as its alias. Script mode is unaffected — dispatch finds `main <sub>`
# in the file's own scope whether it is exported or not (checked on nu 0.115),
# and `help toolkit container up` still prints the real command's flags through
# the alias expansion. Same shape as toolkit/check.nu, whose subcommands were
# never exported.
#
# Each alias repeats its command's first doc line because an alias shows its own
# comment as its description; with none, the list reads "Alias for `main up`".

# Start a cozy container behind a human-managed egress allowlist.
export alias up = main up

# Bring the pair back after the runtime itself restarted, or after a day off.
export alias restart = main restart

# Apply an edited allowlist to a container that is already up.
export alias reload-egress = main reload-egress

# Move the proxy pin forward: upstream's newest, rehearsed, then written to both files.
export alias refresh-egress = main refresh-egress

# Open the cozy container in a WezTerm window, restarting the pair if it is down.
export alias attach = main attach
