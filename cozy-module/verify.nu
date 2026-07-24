# Shared post-build verification for cozy sandboxes.
#
# Run from inside a sandbox via `cozy verify`. The checks take a `run` closure
# that executes an argv list in the target and returns {stdout, exit}, so the
# check logic stays independent of how the command is carried.
#
# Every expected value is derived from repo sources that ship into the sandbox
# (vendored-repos.nuon, docker-files/nushell-autoload/, install/bootstrap.nu),
# so the checklist can't drift from the build the way a hand-kept list does.

const cozy_module = (path self | path dirname)
const manifest = ($cozy_module | path join vendored-repos.nuon)
const autoload_src = ($cozy_module | path join .. docker-files nushell-autoload)
const bootstrap = ($cozy_module | path join install bootstrap.nu)

# Paths are evaluated here but the commands run in the target, so they must be
# the sandbox's absolute paths — not the host caller's $nu.home-dir.
const home = "/home/agent"
const autoload_dir = "/home/agent/.config/nushell/autoload"
const repos = "/home/agent/repos"

# Binaries that must launch. No machine-readable source of truth — they're
# spread across the base image and bootstrap.nu's `brew install` — so this is
# the one place they're named. pbcopy has no --version; checked in check-pbcopy.
const tools = [
    [nu "--version"] [fd "--version"] [bat "--version"] [rg "--version"]
    [delta "--version"] [jj version] [vd "--version"]
    [hx "--version"] [lazygit "--version"] [zellij "--version"]
    [topiary "--version"] [claude "--version"] [broot "--version"]
    [git-lfs "--version"] [git "--version"] [jq "--version"]
]

# Hosts whose TLS must terminate at the origin, not at the sbx egress proxy.
# Only hosts carrying traffic the proxy has no business reading belong here.
const tls_passthrough_hosts = [api.anthropic.com]

# Canary for the default-deny rule. Must never appear in any allowlist. Chosen
# because it *succeeds* when there is no cage — a name that can't resolve (.invalid)
# would fail identically whether the policy is on or the network is simply down.
# Under a working policy the request dies at the proxy and never reaches IANA.
#
# Plain http, not https, and that is the whole point: a refused http request
# gets a real 403 block page from the proxy, while every flavour of no-network
# (dead proxy, unresolvable proxy name, timeout) yields no status at all. Over
# https the refusal is a failed CONNECT, which is indistinguishable from a
# broken firewall — and a broken firewall must never read as a pass.
const egress_canary = 'http://example.com'

# Reached directly, with the proxy bypassed, to prove the cage itself rather
# than the proxy in front of it. An IP literal so no DNS is involved. Any answer
# at all means a route out exists that the allowlist never sees.
const egress_direct_probe = 'https://1.1.1.1'

def ok [label: string detail?: string]: nothing -> record {
    {label: $label pass: true detail: ($detail | default "")}
}
def fail [label: string detail: string]: nothing -> record {
    {label: $label pass: false detail: $detail}
}

# cozy-owned autoload scripts, derived from the dir bootstrap.nu copies in (so a
# new script is verified automatically), plus the two non-autoload files cozy
# installs and the one autoload script that ships from the dotfiles repo, not
# this glob. Each row carries the owning repo so a failure names where to fix it.
def expected-files []: nothing -> list {
    let cozy_autoload = glob ($autoload_src | path join '*.nu')
        | each {|f| {owner: cozy, path: ($autoload_dir | path join ($f | path basename))} }
    [
        {owner: cozy, path: ($home | path join .local bin pbcopy)}
        ...$cozy_autoload
        {owner: dotfiles, path: ($autoload_dir | path join hooks-config.nu)}
        {owner: cozy, path: ($home | path join .claude.json)}
    ]
}

# Every vendored repo lands at ~/repos/<name> — the manifest already includes
# cozy — plus cozy's module dir and broot's config dir.
def expected-dirs []: nothing -> list<string> {
    open $manifest | get name
    | each {|r| $repos | path join $r }
    | append [
        ($repos | path join cozy cozy-module)
        ($home | path join .config broot)
    ]
}

# Runtime env cozy sets, parsed from the export block bootstrap.nu writes to
# /etc/sandbox-persistent.sh — the same values check.nu guards across the
# Dockerfile and kit. No `^` anchor: the first export shares its line with the
# `let env_exports = '...` that opens the block. $HOME is expanded the way the
# sandbox resolves it.
def expected-envs []: nothing -> record {
    open --raw $bootstrap
    | parse --regex '(?m)export[ \t]+(?<k>\w+)="(?<v>[^"]*)"'
    | reduce --fold {} {|row acc|
        $acc | insert $row.k ($row.v | str replace --all '$HOME' $home)
    }
}

def check-tools [run: closure]: nothing -> list {
    $tools | each {|t|
        let r = do $run $t
        if $r.exit == 0 { ok $"bin: ($t.0)" ($r.stdout | lines | first | default '') } else { fail $"bin: ($t.0)" 'launch failed' }
    }
}

def check-files [run: closure]: nothing -> list {
    expected-files | each {|f|
        let name = ($f.path | path basename)
        let r = do $run [test -f $f.path]
        if $r.exit == 0 { ok $"file: ($name)" $"[($f.owner)]" } else { fail $"file: ($name)" $"missing — fix in ($f.owner): ($f.path)" }
    }
}

def check-dirs [run: closure]: nothing -> list {
    expected-dirs | each {|d|
        let r = do $run [test -d $d]
        if $r.exit == 0 { ok $"dir: ($d | path basename)" } else { fail $"dir: ($d | path basename)" $d }
    }
}

# Read env from a login shell, not this process. Why: the git identity and
# JJ_CONFIG live only in /etc/sandbox-persistent.sh, which a login shell sources
# but a directly-spawned nu does not — so reading `$env`/`printenv` here false-
# fails when verify runs under the nushell MCP tool (its nu isn't a login child).
# A login shell is also the true contract: it catches a real regression where the
# base image stops sourcing the persistent file, which a plain file read wouldn't.
def check-envs [run: closure]: nothing -> list {
    let actual = (do $run [bash -lc printenv]).stdout
        | lines
        | parse '{k}={v}'
        | reduce --fold {} {|row acc| $acc | insert $row.k $row.v }
    expected-envs | items {|name expected|
        let got = $actual | get --optional $name
        if $got == null {
            fail $"env: ($name)" 'not set (checked a login shell)'
        } else if $got == $expected {
            ok $"env: ($name)" $got
        } else {
            fail $"env: ($name)" $"expected ($expected), got ($got)"
        }
    }
}

# A bare `sbx exec` doesn't start a nushell session, so the autoload
# may not have patched ~/.claude.json yet. Run it explicitly first (idempotent
# self-heal), then list. Registered-but-not-connected is a real fault, not a
# cold-start artifact — `claude mcp list` actively probes the server.
def check-mcp [run: closure]: nothing -> record {
    do $run [nu ($autoload_dir | path join mcp-server.nu)] | ignore
    let r = do $run [claude mcp list]
    if not ($r.stdout | str contains 'nushell') {
        fail 'mcp: nushell' 'not registered'
    } else if ($r.stdout | str contains 'Connected') {
        ok 'mcp: nushell' 'connected'
    } else {
        fail 'mcp: nushell' 'registered but not connected'
    }
}

def check-pbcopy [run: closure]: nothing -> record {
    let r = do $run [test -x ($home | path join .local bin pbcopy)]
    if $r.exit == 0 { ok 'pbcopy: executable' } else { fail 'pbcopy: executable' 'not executable' }
}

def check-bootstrap-parses [run: closure]: nothing -> record {
    let path = ($repos | path join cozy cozy-module install bootstrap.nu)
    let r = do $run [nu --ide-check 0 $path]
    let errs = $r.stdout | lines | where {|l| $l | str contains '"severity":"error"' }
    # Narrower than ensure-nu.sh's gate: --ide-check parses only, where `use`
    # also evaluates the top level. A file that passes here can still fail there.
    if ($errs | is-empty) { ok 'bootstrap.nu parses' } else { fail 'bootstrap.nu parses' $"($errs | length) parse error\(s) on the shipped nu" }
}

def check-catalog [run: closure]: nothing -> record {
    let r = do $run [grep -c fd ($home | path join .claude CLAUDE.md)]
    if $r.exit == 0 { ok 'CLAUDE.md catalog' } else { fail 'CLAUDE.md catalog' 'tool catalog (step 6) not appended' }
}

def check-topiary [run: closure]: nothing -> record {
    let r = do $run [nu -c "'def main [] { 1 }' | save -f /tmp/cozy-verify.nu; topiary format /tmp/cozy-verify.nu"]
    if $r.exit == 0 { ok 'topiary formats .nu' } else { fail 'topiary formats .nu' 'grammar/symlink missing (bootstrap step 8)' }
}

def check-git-xdg [run: closure]: nothing -> record {
    let r = do $run [git config --list --show-origin]
    if ($r.stdout | str contains '.config/git/config') { ok 'git config: XDG' } else { fail 'git config: XDG' 'runtime git config not from ~/.config/git/config' }
}

# cozy's global ignore patterns must still resolve after sbx sets
# core.excludesFile (which shadows git's XDG default). The patterns are derived
# from the sandbox's canonical ~/.config/git/ignore — the git-global-ignore
# autoload mirrors that file into the active excludesFile. Run the autoload
# first (idempotent self-heal, same as check-mcp), then assert every canonical
# pattern is reported ignored. check-ignore needs a work tree, but a global
# excludesFile applies in any repo, so init a throwaway in /tmp — don't depend
# on ~/repos/cozy being a repo: it's a real clone under the sbx kit, a symlink
# in a cozy-dev sandbox, and plain COPYs (no .git) under the Dockerfile.
def check-git-ignore [run: closure]: nothing -> record {
    do $run [nu ($autoload_dir | path join git-global-ignore.nu)] | ignore
    let want = (do $run [cat ($home | path join .config git ignore)]).stdout | lines | where {|l| ($l | str trim) | is-not-empty }
    if ($want | is-empty) { return (fail 'git ignore: patterns' 'canonical ~/.config/git/ignore missing or empty') }
    let tmp = '/tmp/cozy-verify-ignore'
    do $run [git init -q $tmp] | ignore
    let r = do $run ([git -C $tmp check-ignore] | append $want)
    let got = $r.stdout | lines
    let unignored = $want | where {|p| $p not-in $got }
    if ($unignored | is-empty) { ok 'git ignore: patterns' ($want | str join ' ') } else { fail 'git ignore: patterns' $"not ignored: ($unignored | str join ', ') — sbx excludesFile shadowing XDG default" }
}

# The sbx egress proxy can decrypt anything: its CA sits in the sandbox trust
# bundle. Today it only uses that on hosts it refuses, to serve a readable block
# page — allowed hosts are CONNECT-tunneled and keep the origin's own cert. That
# split is policy, not architecture; it can change with no signal inside the
# sandbox, and Certificate Transparency doesn't watch a local CA. So assert it
# for the hosts that carry our secrets: the presented cert must not be issued by
# the proxy CA. Expected value is the CA's own CN, read from PROXY_CA_CERT_B64,
# so a renamed or rotated CA can't slip past. Only check here that needs network.
def check-tls-passthrough [run: closure]: nothing -> list {
    # Null when no proxy CA exists at all (the compose path has none — squid
    # refuses the CONNECT instead of forging a cert). Nothing to compare against
    # then, but the handshake still runs: it is this suite's only positive
    # control, the one check that proves an allowlisted host is truly reachable.
    let ca_cn = (do $run [bash -lc 'printenv PROXY_CA_CERT_B64 | base64 -d | openssl x509 -noout -subject -nameopt RFC2253']).stdout
        | parse --regex 'CN=(?<cn>[^,]+)'
        | get --optional cn.0
    $tls_passthrough_hosts | each {|h|
        let r = do $run [bash -lc $"curl -sS -o /dev/null -v https://($h) 2>&1"]
        let issuer = $r.stdout
            | lines
            | where {|l| $l =~ '^\*\s+issuer:' }
            | get --optional 0
            | default ''
            | parse --regex 'CN=(?<cn>.+)$'
            | get --optional cn.0
        if $issuer == null {
            fail $"tls: ($h)" 'no TLS handshake — unreachable through the proxy'
        } else if $ca_cn != null and $issuer == $ca_cn {
            fail $"tls: ($h)" $"intercepted — cert issued by ($ca_cn); TLS terminates at the proxy"
        } else {
            ok $"tls: ($h)" $"issuer ($issuer)"
        }
    }
}

# curl's status as a 3-char string, or null when curl produced no status at all
# (missing binary, or the transport lost stdout). '000' is curl's own marker for
# "never got an answer" and is returned as-is — the callers below read those two
# cases very differently, so they must not collapse into one.
def http-code [run: closure cmd: string]: nothing -> any {
    (do $run [bash -lc $cmd]).stdout
    | str trim
    | parse --regex '^(?<n>\d{3})$'
    | get --optional n.0
}

# Is an egress allowlist actually in force? Both run paths are supposed to have
# one — sbx supplies its own proxy, the Debian image gets one from compose.yaml —
# but a bare `docker run cozy` has none, and nothing else in the build would say
# so. Two independent properties, because either alone can be faked:
#
#   - the cage: no way out except the proxy. Probed directly with the proxy
#     bypassed, so `docker run -e HTTPS_PROXY=... ` on a normal bridge network
#     can't dress an uncaged container up as a caged one.
#   - the policy: the proxy defaults to deny. Probed over plain http so that a
#     refusal (403 block page) stays distinguishable from a proxy that is simply
#     down (no status). A broken firewall must fail, never pass.
def check-egress-cage [run: closure]: nothing -> list {
    let direct = http-code $run $"curl -sS --noproxy '*' --max-time 10 -o /dev/null -w '%{http_code}' ($egress_direct_probe)"
    let route = if $direct == null {
        fail 'egress: no direct route' 'could not probe — no usable curl'
    } else if $direct == '000' {
        ok 'egress: no direct route' $"($egress_direct_probe) unreachable without the proxy"
    } else {
        fail 'egress: no direct route' $"($egress_direct_probe) answered ($direct) with the proxy bypassed — traffic can leave unfiltered"
    }

    # Pointed at the proxy with -x rather than left to the environment: curl
    # honours only the lowercase `http_proxy` for http URLs (httpoxy), and sbx
    # sets just the uppercase one, so an env-driven canary would skip the proxy
    # entirely and fail on DNS instead of testing anything.
    let proxy = (do $run [bash -lc 'printenv HTTPS_PROXY https_proxy HTTP_PROXY http_proxy'])
        | get stdout
        | lines
        | get --optional 0
        | default ''
    let deny = if ($proxy | is-empty) {
        fail 'egress: default deny' 'no *_PROXY set — there is no filtered exit at all'
    } else {
        let canary = http-code $run $"curl -sS -x ($proxy) --max-time 20 -o /dev/null -w '%{http_code}' ($egress_canary)"
        if $canary == null {
            fail 'egress: default deny' 'could not probe — no usable curl'
        } else if $canary == '000' {
            fail 'egress: default deny' $"no answer for ($egress_canary) — a refusal would be a 403; ($proxy) looks down"
        } else if ($canary | into int) >= 400 {
            ok 'egress: default deny' $"($egress_canary) blocked with ($canary)"
        } else {
            fail 'egress: default deny' $"($egress_canary) fetched ($canary) — the allowlist is not in force"
        }
    }

    [$route $deny]
}

# Run every check with the given transport; one row per check.
export def run-checks [run: closure]: nothing -> table {
    [
        ...(check-tools $run)
        ...(check-files $run)
        ...(check-dirs $run)
        ...(check-envs $run)
        (check-mcp $run)
        (check-pbcopy $run)
        (check-bootstrap-parses $run)
        (check-catalog $run)
        (check-topiary $run)
        (check-git-xdg $run)
        (check-git-ignore $run)
        ...(check-tls-passthrough $run)
        ...(check-egress-cage $run)
    ]
}

# Transport that runs each command locally, in the current sandbox.
export def local-runner []: nothing -> closure {
    {|argv|
        let cmd = $argv | first
        let rest = $argv | skip 1
        let r = (run-external $cmd ...$rest) | complete
        {stdout: ($r.stdout | str trim), exit: $r.exit_code}
    }
}

# Print a colored pass/fail summary as a side effect, then return the results
# table. Why: a printed-only result is unconsumable — the nushell MCP captures
# the return value, not stdout, so `cozy verify` surfaced `[]` while the table
# went nowhere a caller could reach. Humans still see the full table via the
# returned value's auto-view; only the summary line needs an explicit print.
export def report [results: table]: nothing -> table {
    let failed = $results | where not pass
    if ($failed | is-not-empty) {
        print $"(ansi red)($failed | length)/($results | length) checks failed(ansi reset)"
        print ($failed | select label detail)
    } else {
        print $"(ansi green)All ($results | length) checks passed(ansi reset)"
    }
    $results | select label pass detail
}

# `cozy verify` — run the post-build checks against the sandbox we are inside.
# Returns the results table (and prints a summary) so callers can act on it,
# e.g. `cozy verify | where not pass`.
export def main []: nothing -> table {
    if not ('/etc/sandbox-persistent.sh' | path exists) {
        error make {msg: 'not inside a cozy sandbox (no /etc/sandbox-persistent.sh)'}
    }
    report (run-checks (local-runner))
}
