# Bring up the caged Apple `container` run path — the `compose.yaml` equivalent.
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
#   nu toolkit/container-up.nu my-agent ~/path/to/project
#   nu toolkit/sbxw.nu my-agent --runtime container --workdir ~/path/to/project

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
# policy and has internet, so it should not change under us on a pull.
const egress_image = 'ubuntu/squid:latest@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029'
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
# startedDate), not a string. Same shape toolkit/sbxw.nu's completer reads.
def container-status [name: string]: nothing -> string {
    let rows = container-cli [ls --all --format json] | from json | where configuration.id == $name
    if ($rows | is-empty) { 'absent' } else { $rows | first | get status.state }
}

# `--internal` is the whole enforcement: a host-only network, no route out. The
# agent sits here alone with the proxy and can reach nothing else.
def ensure-network []: nothing -> nothing {
    if ((^container network list | complete).stdout | str contains $caged_network) {
        print $"  (ansi green)Network:(ansi reset) ($caged_network) already up"
        return
    }
    container-cli [network create --internal --subnet $caged_subnet $caged_network]
    print $"  (ansi green)Network:(ansi reset) created ($caged_network) ($caged_subnet), host-only"
}

def ensure-egress [policy: path, reload: bool]: nothing -> nothing {
    let status = container-status $egress_name
    if $reload and $status != 'absent' {
        container-cli [stop $egress_name]
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
        run -d --name $egress_name
        --network default
        --network $caged_network
        -v $"($policy):/etc/squid/policy:ro"
        $egress_image
        -f /etc/squid/policy/squid.conf -NYC
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

# Start a cozy agent container behind a human-managed egress allowlist.
export def main [
    name: string # name for the agent container
    workspace: path # host folder to mount and to expose as WORKSPACE_DIR
    --image: string = 'cozy:latest' # image built by `container build -t cozy:latest .`
    --policy: path # firewall policy directory (default: ~/.config/cozy/firewall)
    --workdir: path # start directory inside the container (default: the workspace)
    --memory: string = '8g' # RAM for the agent VM (Apple `container` defaults to 1g)
    --cpus: int = 6 # CPUs for the agent VM (Apple `container` defaults to 4)
    --reload-egress # recreate the proxy so an edited allowlist takes effect
]: nothing -> nothing {
    let ws = $workspace | path expand
    if not ($ws | path exists) {
        error make {msg: $"workspace ($ws) does not exist"}
    }

    let policy_dir = $policy | default ($nu.home-dir | path join .config cozy firewall) | path expand
    if not ($policy_dir | path exists) {
        error make {msg: $"no policy at ($policy_dir) — seed it once with `mkdir -p ~/.config/cozy and cp -r firewall ~/.config/cozy/firewall`. Keeping it outside this repo is what makes the allowlist human-managed."}
    }

    # Why: everything under the workspace is agent-writable, and this script plus
    # the firewall template are what build the cage on the next launch — an agent
    # that can edit them writes its own policy. compose.yaml states the same rule
    # for COZY_WORKSPACE but only in a comment; it has already been stepped on, so
    # here it is an error. To work on cozy itself, run the image without the cage.
    if (($cozy_root | path expand) + '/' | str starts-with (($ws | str trim --right --char '/') + '/')) {
        error make {msg: $"workspace ($ws) contains the cozy repo — the agent would be able to edit this script and the firewall template, which are read fresh at the next launch. Pick a workspace outside it."}
    }

    ensure-network
    ensure-egress $policy_dir $reload_egress
    let ip = egress-address
    print $"  (ansi green)Exit:(ansi reset) http://($ip):($proxy_port)"

    if (container-status $name) != 'absent' {
        error make {msg: $"a container named ($name) already exists — `container stop ($name); container delete ($name)` first"}
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
    container-cli [
        run -d --name $name
        --network $caged_network
        --no-dns
        --memory $memory
        --cpus ($cpus | into string)
        -e $"WORKSPACE_DIR=($ws)"
        -e $"HTTP_PROXY=http://($ip):($proxy_port)"
        -e $"HTTPS_PROXY=http://($ip):($proxy_port)"
        -e $"http_proxy=http://($ip):($proxy_port)"
        -e $"https_proxy=http://($ip):($proxy_port)"
        -e 'NO_PROXY=localhost,127.0.0.1,::1'
        -v $"($ws):($ws)"
        -w ($workdir | default $ws | path expand)
        $image
        sleep infinity
    ]
    print $"  (ansi green)Agent:(ansi reset) ($name) on ($caged_network), workspace ($ws)"

    print ""
    print $"  attach:  nu toolkit/sbxw.nu ($name) --runtime container --workdir ($ws)"
    print $"  check:   container exec ($name) nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'"
    print $"  refused: container logs -f ($egress_name)"
}
