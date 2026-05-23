export def main [] { help rust }

# Install Rust via rustup.
#
# Safe to re-run — skips if rustc is already available.
export def install []: nothing -> nothing {
    # Why: sandbox proxy (host.docker.internal:3128) is flaky; cargo's default
    # 30s timeout with no retries fails on first hiccup. Originally set in
    # Dockerfile, restored here since rust moved to runtime install (commit
    # 22a7dbf dropped it). Idempotent — only writes if missing.
    let cargo_config = $nu.home-dir | path join .cargo config.toml
    if not ($cargo_config | path exists) {
        mkdir ($cargo_config | path dirname)
        {
            net: {retry: 5 git-fetch-with-cli: true}
            http: {timeout: 120}
            registries: {crates-io: {protocol: "sparse"}}
        } | save $cargo_config
    }

    if not (which rustc | is-empty) {
        print $"  (ansi green)rust(ansi reset): already installed"
        return
    }
    # Rust needs a C linker (cc) for compiling build scripts and native deps
    if (which cc | is-empty) {
        print "  Installing build-essential (C linker)..."
        ^sudo apt-get update -qq
        ^sudo apt-get install -y -qq build-essential
    }

    print "  Installing Rust via rustup..."
    ^sh -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    $env.PATH = ($env.PATH | prepend ($nu.home-dir | path join .cargo bin))

    # rustup adds `source $"($nu.home-path)/.cargo/env.nu"` to config.nu,
    # which breaks nushell — `home-path` doesn't exist (it's `home-dir`).
    # Remove it. (2026-02-28)
    let config = $nu.config-path
    let content = open --raw $config
    let bad_line = 'source $"($nu.home-path)/.cargo/env.nu"'
    if $bad_line in $content {
        $content | str replace $"($bad_line)\n" '' | save -f $config
        print $"  (ansi yellow)rust(ansi reset): removed erroneous line from config.nu"
    }

    print $"  (ansi green)rust(ansi reset): installed"
}
