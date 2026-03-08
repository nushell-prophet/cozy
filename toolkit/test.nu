# test.nu — Verify Docker sandbox image
#
# Usage:
#   nu test.nu test              # test with :latest tag
#   nu test.nu test -t v5        # test specific tag
#   nu test.nu test --keep       # keep sandbox for debugging
#   nu test.nu clean             # remove leftover test sandbox

const image = "nushell-ai-sandbox"
const sandbox = "claude-test"

# Each tool: [label, command, ...args] — runs the command to verify it launches
const tools = [
    ["brew: nu" nu "--version"]
    ["brew: fzf" fzf "--version"]
    ["brew: lazygit" lazygit "--version"]
    ["brew: hx" hx "--version"]
    ["brew: zellij" zellij "--version"]
    ["brew: broot" broot "--version"]
    ["brew: carapace" carapace "--version"]
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

const files = [
    "/usr/local/bin/pbcopy"
    "/home/agent/.config/nushell/autoload/module-imports.nu"
    "/home/agent/.config/nushell/autoload/cmd-stack-import.nu"
    "/home/agent/.config/nushell/autoload/hooks-config.nu"
    "/home/agent/.config/nushell/autoload/my_nu_completions.nu"
    "/home/agent/.config/nushell/autoload/standard_4002_aliasses.nu"
    "/home/agent/.config/nushell/autoload/mcp-server.nu"
    "/home/agent/.claude.json"
    "/home/agent/toolkit.nu"
]

const dirs = [
    "/home/agent/repos/ai-sandbox-toolkit"
    "/home/agent/repos/nu-goodies"
    "/home/agent/repos/nushell-kv"
    "/home/agent/repos/dotnu"
    "/home/agent/repos/numd"
    "/home/agent/repos/claude-nu"
    "/home/agent/repos/nu-cmd-stack"
    "/home/agent/repos/dotfiles"
    "/home/agent/.config/broot"
]

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

def ok [label: string, detail?: string]: nothing -> record {
    {label: $label, pass: true, detail: ($detail | default "")}
}

def fail [label: string, detail: string]: nothing -> record {
    {label: $label, pass: false, detail: $detail}
}

export def main [] { help main }

# Run checks against a fresh sandbox, clean up after
export def "main test" [
    --tag (-t): string = "latest"  # image tag to test
    --keep (-k)                    # keep sandbox after tests
] {
    let template = $"($image):($tag)"

    # Clean previous test sandbox if any
    do -i { ^docker sandbox stop $sandbox }
    do -i { ^docker sandbox rm $sandbox }

    let ws = [$nu.home-dir temp sandbox-test-ws] | path join
    mkdir $ws

    print $"Image: ($template)"
    print "Creating sandbox..."
    ^docker sandbox create --debug --load-local-template -t $template --name $sandbox claude $ws

    # Wait for readiness
    mut ready = false
    for _ in 1..15 {
        if not $ready {
            $ready = try { exec echo ok | ignore; true } catch { sleep 2sec; false }
        }
    }
    if not $ready {
        error make { msg: "Sandbox did not become ready" }
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
    $files | each {|f|
        let name = $f | path basename
        try {
            exec test -f $f | ignore
            ok $"file: ($name)"
        } catch {
            fail $"file: ($name)" $f
        }
    }
}

def check-dirs []: nothing -> list {
    $dirs | each {|d|
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
            fail "mcp: nushell" "autoload script did not patch settings.json"
        } else {
            fail "mcp: nushell" $"unexpected command: ($cmd)"
        }
    } catch {|e|
        fail "mcp: nushell" ($e.msg | str trim)
    }

    let pbcopy = try {
        exec test -x /usr/local/bin/pbcopy | ignore
        ok "pbcopy: executable"
    } catch {
        fail "pbcopy: executable" "not executable"
    }

    [$mcp $pbcopy]
}
