# test.nu — Verify Docker sandbox image
#
# Usage:
#   nu test.nu test              # test with :latest tag
#   nu test.nu test -t v5        # test specific tag
#   nu test.nu test --keep       # keep sandbox for debugging
#   nu test.nu clean             # remove leftover test sandbox

const image = "cozy"
const sandbox = "claude-test"

# Each tool: [label, command, ...args] — runs the command to verify it launches
const tools = [
    ["brew: nu" nu "--version"]
    ["brew: fzf" fzf "--version"]
    ["brew: lazygit" lazygit "--version"]
    ["brew: hx" hx "--version"]
    ["brew: zellij" zellij "--version"]
    ["brew: broot" broot "--version"]
    ["brew: delta" delta "--version"]
    ["brew: jj" jj version]
    ["base: git" git "--version"]
    ["base: curl" curl "--version"]
    ["base: python3" python3 "--version"]
    ["base: node" node "--version"]
    ["base: go" go version]
    ["base: rg" rg "--version"]
    ["base: jq" jq "--version"]
    ["base: gh" gh "--version"]
    ["apt: ps" ps "--version"]
    ["apt: file" file "--version"]
]

# Files a built sandbox must have, each tagged with the repo that owns it so a
# failure names where to go fix it (a bare path can't tell you which repo to
# edit). The cozy-owned autoload scripts are derived from
# docker-files/nushell-autoload/ — the same set bootstrap.nu copies in — so a
# newly added script is verified automatically instead of silently skipped, the
# way the old hardcoded list let git-safe-directory.nu slip through. Only
# hooks-config.nu stays explicit: it ships from the dotfiles repo, not this glob.
const autoload_dir = "/home/agent/.config/nushell/autoload"
const cozy_autoload_src = (path self | path dirname | path join .. docker-files nushell-autoload)

def expected-files []: nothing -> list {
    let cozy_autoload = glob ($cozy_autoload_src | path join '*.nu')
        | each {|f| [cozy ($autoload_dir | path join ($f | path basename))] }
    [
        [cozy "/home/agent/.local/bin/pbcopy"]
        ...$cozy_autoload
        [dotfiles ($autoload_dir | path join hooks-config.nu)]
        [cozy "/home/agent/.claude.json"]
    ]
}

# Repo dirs are derived from vendor.yml (the single source of truth for what
# cozy vendors) so a newly vendored module is verified automatically — the old
# hardcoded list had silently drifted to a stale subset. See expected-dirs.
const vendor_yml = (path self | path dirname | path join vendor.yml)

const envs = {
    HOME: "/home/agent"
    HELIX_RUNTIME: "/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime"
    XDG_CONFIG_HOME: "/home/agent/.config"
    XDG_DATA_HOME: "/home/agent/.local/share"
    XDG_CACHE_HOME: "/home/agent/.cache"
}

def --wrapped exec [...args: string]: nothing -> string {
    ^docker sandbox exec $sandbox ...$args
}

def ok [label: string detail?: string]: nothing -> record {
    {label: $label pass: true detail: ($detail | default "")}
}

def fail [label: string detail: string]: nothing -> record {
    {label: $label pass: false detail: $detail}
}

export def main [] { help main }

# Run checks against a fresh sandbox, clean up after
export def "main test" [
    --tag (-t): string = "latest" # image tag to test
    --keep (-k) # keep sandbox after tests
] {
    let template = $"($image):($tag)"

    # Clean previous test sandbox if any
    do -i { ^docker sandbox stop $sandbox }
    do -i { ^docker sandbox rm $sandbox }

    let ws = [$nu.home-dir temp sandbox-test-ws] | path join
    mkdir $ws

    print $"Image: ($template)"
    print "Creating sandbox..."
    ^docker sandbox create --debug -t $template --name $sandbox claude $ws

    # Wait for readiness
    mut ready = false
    for _ in 1..15 {
        if not $ready {
            $ready = try { exec echo ok | ignore; true } catch { sleep 2sec; false }
        }
    }
    if not $ready {
        error make {msg: "Sandbox did not become ready"}
    }
    print "Sandbox ready"

    let results = [
        ...(check-tools)
        ...(check-files)
        ...(check-dirs)
        ...(check-envs)
        ...(check-config)
    ]

    if not $keep {
        print "Cleaning up..."
        do -i { ^docker sandbox stop $sandbox }
        do -i { ^docker sandbox rm $sandbox }
        rm -rf $ws
    }

    print ""
    print ($results | select label pass)

    let failed = $results | where { not $in.pass }
    if ($failed | is-not-empty) {
        print $"\n(ansi red)($failed | length)/($results | length) failed:(ansi reset)"
        print ($failed | select label detail)
    } else {
        print $"\n(ansi green)All ($results | length) checks passed(ansi reset)"
    }
}

# Remove leftover test sandbox
export def "main clean" [] {
    do -i { ^docker sandbox stop $sandbox }
    do -i { ^docker sandbox rm $sandbox }
    let ws = [$nu.home-dir temp sandbox-test-ws] | path join
    if ($ws | path exists) { rm -rf $ws }
    print "Cleaned up"
}

# Verify each tool launches by running its version command
def check-tools []: nothing -> list {
    $tools | each {|t|
        let label = $t.0
        let args = $t | skip 1
        try {
            let out = exec ...$args | lines | first | default "" | str trim
            ok $label $out
        } catch {
            fail $label "launch failed"
        }
    }
}

def check-files []: nothing -> list {
    expected-files | each {|f|
        let owner = $f.0
        let path = $f.1
        let name = $path | path basename
        try {
            exec test -f $path | ignore
            ok $"file: ($name)" $"[($owner)]"
        } catch {
            fail $"file: ($name)" $"missing — fix in ($owner): ($path)"
        }
    }
}

# Sandbox dirs expected to exist: every vendored repo lands at ~/repos/<repo>,
# cozy ships its module under ~/repos/cozy/cozy-module, plus broot's config dir.
def expected-dirs []: nothing -> list<string> {
    open $vendor_yml | get repo
    | each {|r| $"/home/agent/repos/($r)" }
    | append [
        "/home/agent/repos/cozy/cozy-module"
        "/home/agent/.config/broot"
    ]
}

def check-dirs []: nothing -> list {
    expected-dirs | each {|d|
        let name = $d | path basename
        try {
            exec test -d $d | ignore
            ok $"dir: ($name)"
        } catch {
            fail $"dir: ($name)" $d
        }
    }
}

def check-envs []: nothing -> list {
    $envs | items {|name expected|
        try {
            let actual = exec printenv $name | str trim
            if $actual == $expected {
                ok $"env: ($name)" $actual
            } else {
                fail $"env: ($name)" $"expected ($expected), got ($actual)"
            }
        } catch {
            fail $"env: ($name)" "not set"
        }
    }
}

def check-config []: nothing -> list {
    # Run the autoload script explicitly (nu -c doesn't process autoload), then verify
    let mcp = try {
        exec nu /home/agent/.config/nushell/autoload/mcp-server.nu | ignore
        let json = exec cat /home/agent/.claude.json | from json
        let cmd = $json | get --optional mcpServers.nushell.command
        if ($cmd | default "" | str ends-with "nu") {
            ok "mcp: nushell" "autoload patched"
        } else if $cmd == null {
            fail "mcp: nushell" "autoload script did not patch .claude.json"
        } else {
            fail "mcp: nushell" $"unexpected command: ($cmd)"
        }
    } catch {|e|
        fail "mcp: nushell" ($e.msg | str trim)
    }

    let pbcopy = try {
        exec test -x /home/agent/.local/bin/pbcopy | ignore
        ok "pbcopy: executable"
    } catch {
        fail "pbcopy: executable" "not executable"
    }

    [$mcp $pbcopy]
}
