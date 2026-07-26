# The Apple `container` run path, as one command group — what `compose.yaml` plus
# `docker compose exec` are for the docker path.
#
# Apple `container` has no compose, so the three pieces compose declares are
# assembled here instead: a host-only network with no way out, a squid holding
# the allowlist dual-homed onto that network and the default one, and the agent
# attached to the caged network only. Same image, same policy directory, same
# residual risks as the docker path — see README's "Egress firewall".
#
# Requires macOS 26 or later: `container network create` does not exist before
# it, and on macOS 15 `--network` is an error. Without it there is no cage on
# this runtime at all, and `cozy verify`'s two `egress:` rows fail by design.
#
#   nu toolkit/container.nu up my-agent ~/path/to/project
#   nu toolkit/container.nu up my-agent ~/project-a ~/shared-libs:ro ~/docs:ro
#   nu toolkit/container.nu restart my-agent
#   nu toolkit/container.nu attach my-agent --workdir ~/path/to/project
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
# carried read as a lie. Pinned 2026-07-24, squid 6.13. Frozen also means
# upstream CVE fixes never arrive; re-pin deliberately.
const egress_image = 'ubuntu/squid@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029'
const proxy_port = 3128

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

def "nu-complete container names" [] {
    # Why --all: stopped containers are the ones `restart` is for, and without it
    # every description reads `running`.
    ^container ls --all --format json | from json
    | each {|x| {value: $x.configuration.id description: $x.status.state} }
}

# Why whole tokens and not `str contains`: the substring test also accepted a
# leftover `cozy-caged-old` and returned "already up" for a network that isn't
# ours. `network ls --format json` would be exact, but Apple's ls/inspect schema
# is undocumented (see egress-address), so compare whitespace-separated tokens —
# that needs no column layout and no key names.
def caged-network-exists []: nothing -> bool {
    let names = (^container network list | complete).stdout | split row --regex '\s+' | str trim
    $caged_network in $names
}

# `--internal` is the whole enforcement: a host-only network, no route out. The
# agent sits here alone with the proxy and can reach nothing else.
#
# An existing network is still only a name. Nothing observable here proves it
# was created with --internal, and one made by hand or by an older version
# without it hands the agent a route around the proxy — while this function
# prints green and the run continues to success. That is why assert-caged
# probes the finished cage from the agent itself; the property is checked where
# it can be seen, not assumed here.
def ensure-network []: nothing -> nothing {
    if (caged-network-exists) {
        print $"  (ansi green)Network:(ansi reset) ($caged_network) already up — cage probed after the agent starts"
        return
    }
    container-cli [network create --internal --subnet $caged_subnet $caged_network]
    print $"  (ansi green)Network:(ansi reset) created ($caged_network) ($caged_subnet), host-only"
}

# Reached with the proxy bypassed, from inside the agent, to prove the cage
# itself rather than the proxy in front of it. An IP literal, so no DNS is
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

    # Past this point the agent is running and is not a proven cage, so stop it
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

def ensure-egress [policy: path reload: bool]: nothing -> nothing {
    let status = container-status $egress_name
    if $reload and $status != 'absent' {
        # Only a *running* container can be stopped: `container stop` on a
        # stopped one exits non-zero, which container-cli turns into an abort.
        # Reached by the documented reload workflow itself — stop everything for
        # the day, edit the allowlist, re-run — where the proxy is stopped, not
        # absent, and the run died before touching the policy.
        if $status == 'running' { container-cli [stop $egress_name] }
        container-cli [delete $egress_name]
        print $"  (ansi green)Proxy:(ansi reset) removed ($egress_name) to reload the policy"
    } else if $status == 'running' {
        print $"  (ansi green)Proxy:(ansi reset) ($egress_name) already running"
        return
    } else if $status != 'absent' {
        container-cli [delete $egress_name]
    }

    # Dual-homed: `default` is the only way out, the caged network is the only
    # way in. Repeating --network is what Apple's maintainers point to for this;
    # it is the one flag here with no example in the reference docs.
    #
    # The whole policy directory, one mount — not the two files individually. A
    # bind-mounted *file* pins an inode, so an editor that saves atomically
    # leaves the proxy reading the old copy and the edit silently never applies.
    container-cli [
        run
        -d
        --name
        $egress_name
        --network
        default
        --network
        $caged_network
        -v
        $"($policy):/etc/squid/policy:ro"
        $egress_image
        -f
        /etc/squid/policy/squid.conf
        -NYC
    ]
    print $"  (ansi green)Proxy:(ansi reset) started ($egress_name) with ($policy)"
}

# Why: Apple `container` has no static-IP flag and its `inspect` schema is
# undocumented, so the proxy is asked for its own addresses. It is dual homed,
# so keep the one inside the caged subnet — the only address the agent can
# reach. Retried because the address appears when the container's VM finishes
# booting, not when `run -d` returns.
def egress-address []: nothing -> string {
    let prefix = ($caged_subnet | split row '.' | first 3 | str join '.') + '.'
    mut found = []
    for _ in 1..15 {
        let r = ^container exec $egress_name hostname -I | complete
        if $r.exit_code == 0 {
            $found = $r.stdout | split row ' ' | str trim | where {|a| $a | str starts-with $prefix }
            if ($found | is-not-empty) { break }
        }
        sleep 1sec
    }
    if ($found | is-empty) {
        error make {msg: $"($egress_name) never got an address in ($caged_subnet) — check `container logs ($egress_name)` and that it is attached to ($caged_network)"}
    }
    $found | first
}

def proxy-url [ip: string]: nothing -> string { $"http://($ip):($proxy_port)" }

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
        | each {|k| do { ^git config --global --get $k } | complete | get stdout | str trim }
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

# Why: everything the agent can write is what builds the cage on the next launch
# — this script and the firewall template — so an agent with the cozy repo in a
# writable mount writes its own policy. compose.yaml states the same rule for
# COZY_WORKSPACE but only in a comment; it has already been stepped on, so here
# it is an error. `:ro` is exempt because it removes exactly the ability the rule
# is about: reading cozy is fine, editing it is not.
def reject-writable-cozy [ws: record<path: path, ro: bool>]: nothing -> nothing {
    if $ws.ro { return }
    if (($cozy_root | path expand) + '/' | str starts-with (($ws.path | str trim --right --char '/') + '/')) {
        error make {msg: $"workspace ($ws.path) contains the cozy repo — the agent would be able to edit this script and the firewall template, which are read fresh at the next launch. Pick a folder outside it, or mount it read-only as ($ws.path):ro."}
    }
}

export def main []: nothing -> nothing {
    print "usage: nu toolkit/container.nu <up|restart|attach> ... — `--help` on each"
}

# Start a cozy agent container behind a human-managed egress allowlist.
export def "main up" [
    name: string # name for the agent container
    ...workspaces: string # host folders to mount, each at its own absolute path; the first is WORKSPACE_DIR and the default start dir. Append `:ro` for read-only
    --image: string = 'cozy:latest' # image built by `container build -t cozy:latest .`
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
    --workdir: path # start directory inside the container (default: the primary workspace)
    --memory: string = '8g' # RAM for the agent VM (Apple `container` defaults to 1g)
    --cpus: int = 6 # CPUs for the agent VM (Apple `container` defaults to 4)
    --reload-egress # recreate the proxy so an edited allowlist takes effect
]: nothing -> nothing {
    if ($workspaces | is-empty) {
        error make {msg: "no workspace given — `container.nu up <name> <folder> [more:ro ...]`"}
    }
    let ws_list = $workspaces | each {|e| parse-workspace $e }
    # Only the first one can be WORKSPACE_DIR: the variable is single-valued and
    # `cozy sandbox-state` writes into it. Same rule as `sbx run`, where the first
    # path is the primary workspace and the agent starts there.
    let ws = $ws_list | first | get path

    let policy_dir = $policy | default ($nu.home-dir | path join .config cozy firewall) | path expand
    if not ($policy_dir | path exists) {
        error make {msg: $"no policy at ($policy_dir) — seed it once with `mkdir -p ~/.config/cozy and cp -r firewall ~/.config/cozy/firewall`. Keeping it outside this repo is what makes the allowlist human-managed."}
    }

    # Every mount, not just the primary: an extra folder is as writable as the
    # first one, so the cozy-repo rule has to cover all of them.
    for w in $ws_list { reject-writable-cozy $w }

    # Why this is read before anything is touched: the proxy's address is baked
    # into the agent's env at creation and cannot be changed afterwards, so
    # whether an agent already exists decides what recreating the proxy means.
    # The check used to sit *below* ensure-egress, which made the documented
    # `--reload-egress` workflow destructive: it stopped and deleted the proxy
    # the running agent pointed at, then aborted here with "a container named X
    # already exists" — leaving that agent with a dead exit and an error message
    # the user reads as "nothing happened".
    let agent_state = container-status $name
    if $agent_state != 'absent' and not $reload_egress {
        error make {msg: $"a container named ($name) already exists — `nu toolkit/container.nu restart ($name)` brings it back, or `container stop ($name); container delete ($name)` to rebuild it"}
    }

    ensure-network
    # Apple `container` has no static-IP flag, so a recreated proxy may or may
    # not come back on the same address. Capture it first; that is the only way
    # to tell a live allowlist reload from one that stranded the agent.
    let old_ip = if $reload_egress and (container-status $egress_name) == 'running' { egress-address } else { null }
    ensure-egress $policy_dir $reload_egress
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"

    if $agent_state != 'absent' {
        # old_ip is null when the proxy was not running to be read — which is
        # what "stop everything, edit the list, re-run" produces. The address the
        # agent was built with is then unknowable from here, so neither "still
        # the same" nor "changed" can be claimed. Say so, and name the one place
        # the answer does exist: the agent's own environment, which `restart`
        # reads for exactly this reason.
        if $old_ip == null {
            error make {msg: $"($egress_name) was not running, so the exit address ($name) was built with could not be read — it may or may not still be ($ip). `nu toolkit/container.nu restart ($name)` starts it and compares the two. If they disagree, recreate the agent \(`container stop ($name); container delete ($name)`, then `up` without --reload-egress)."}
        }
        if $old_ip == $ip {
            # A stopped agent reaches here too: its baked exit is still correct,
            # but nothing was started. Saying "live" about a container that is
            # not running is what this used to print.
            if $agent_state == 'running' {
                print $"  (ansi green)Done:(ansi reset) ($name) keeps its exit at ($ip) — the edited allowlist is live"
            } else {
                print $"  (ansi green)Done:(ansi reset) ($name) is ($agent_state) and keeps its exit at ($ip) — the edited allowlist is live for it. Start it: `nu toolkit/container.nu restart ($name)`"
            }
            return
        }
        error make {msg: $"the proxy came back at ($ip), not ($old_ip) — ($name) still points at the old address and now has no way out. Recreate it: `container stop ($name); container delete ($name)`, then `up` without --reload-egress."}
    }

    # --no-dns: a host-only network has no resolver, so configuring one buys
    # nothing but a timeout per lookup. Clients reach allowed hosts by handing
    # the name to the proxy, which resolves it on the default network.
    #
    # The proxy variables are not the enforcement — the missing route is. They
    # only tell clients where the one exit is, so a blocked request gets a clean
    # 403 instead of hanging. WORKSPACE_DIR has no other source outside sbx, and
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
        $"HTTP_PROXY=(proxy-url $ip)"
        -e
        $"HTTPS_PROXY=(proxy-url $ip)"
        -e
        $"http_proxy=(proxy-url $ip)"
        -e
        $"https_proxy=(proxy-url $ip)"
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
    print $"  (ansi green)Agent:(ansi reset) ($name) on ($caged_network), workspace ($mounted)"
    assert-caged $name

    print ""
    print $"  attach:  nu toolkit/container.nu attach ($name) --workdir ($ws)"
    print $"  check:   container exec ($name) nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'"
    print $"  refused: container logs -f ($egress_name)"
}

# Bring the pair back after the runtime itself restarted (`container system
# stop/start`, an upgrade, a reboot), or after you stopped them for the day.
#
# Why its own subcommand and not `up --restart`: it shares the cage helpers with
# `up` and none of its build steps — no network to create, no mounts to parse,
# no run arguments — and `--restart --reload-egress` would mean nothing. It also
# fills the one state `up` cannot recover from, both containers *stopped rather
# than absent*: a plain `up` aborts on "already exists", and --reload-egress
# cannot read the address the agent was built with, because the proxy it would
# read it from is not running either.
export def "main restart" [
    name: string@"nu-complete container names" # the agent container to bring back
]: nothing -> nothing {
    let agent_state = container-status $name
    if $agent_state == 'absent' {
        error make {msg: $"no container named ($name) — nothing to restart. Create it: `nu toolkit/container.nu up ($name) <folder>`"}
    }

    # Both of these rebuild instructions delete the agent rather than repair it,
    # for the same reason: the exit address is baked into its environment at
    # creation, so an agent whose proxy is gone cannot be pointed at a new one.
    if not (caged-network-exists) {
        error make {msg: $"($caged_network) is gone — ($name) has no cage to come back to. Rebuild both: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>` recreates the network."}
    }
    let egress_state = container-status $egress_name
    if $egress_state == 'absent' {
        error make {msg: $"($egress_name) is gone, and a new one may land on a different address than ($name) was built with — which cannot be read from a proxy that no longer exists. Rebuild both: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>`."}
    }

    if $egress_state != 'running' {
        container-cli [start $egress_name]
        print $"  (ansi green)Proxy:(ansi reset) started ($egress_name)"
    } else {
        print $"  (ansi green)Proxy:(ansi reset) ($egress_name) already running"
    }
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) (proxy-url $ip)"

    if $agent_state != 'running' {
        container-cli [start $name]
        print $"  (ansi green)Agent:(ansi reset) started ($name)"
    } else {
        print $"  (ansi green)Agent:(ansi reset) ($name) already running"
    }

    # The cage first, the exit second: a cage that came back open is a leak and
    # assert-caged stops the container over it, while a stale exit only leaves
    # the agent with no way out. The restart is also where the cage is most
    # worth re-proving — the runtime rebuilt the network, we did not.
    assert-caged $name

    # The one place the address the agent was built with still exists. Apple
    # `container` has no static-IP flag, so a proxy that just restarted may have
    # come back somewhere else, and nothing inside the agent would say so: its
    # requests would simply hang against an address nobody answers.
    let baked = (^container exec $name printenv HTTPS_PROXY | complete).stdout | str trim
    if ($baked | is-empty) {
        error make {msg: $"($name) has no HTTPS_PROXY — it was not created by `container.nu up`, so it has no exit at all \(a bare `container run` has no cage; `cozy verify`'s egress: rows fail on it by design)."}
    }
    if $baked != (proxy-url $ip) {
        error make {msg: $"($name) points at ($baked) but ($egress_name) came back at (proxy-url $ip) — it now has no way out, and the address cannot be changed on an existing container. Recreate it: `container delete ($name)`, then `nu toolkit/container.nu up ($name) <folder>`."}
    }

    print ""
    print $"  attach:  nu toolkit/container.nu attach ($name)"
    print $"  refused: container logs -f ($egress_name)"
}

# Open the agent in a new WezTerm window, attached to its zellij session — the
# `container` twin of `nu toolkit/sbxw.nu`.
export def "main attach" [
    name: string@"nu-complete container names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
    --zellij-session: string = '' # zellij session name to use instead of the container name
    --workdir: path # start directory inside the container
] {
    # Why --cwd: `container` has no notion of a workspace, so an exec starts
    # wherever the image left WORKDIR — pass it when the start directory matters.
    let exec_argv = [container exec -it]
        ++ (if ($workdir | is-not-empty) { [--cwd $workdir] } else { [] })
        ++ [$name]

    attach-window $exec_argv ($zellij_session | default --empty $name) --config-file $config_file --background $background --no-job=$no_job
}
