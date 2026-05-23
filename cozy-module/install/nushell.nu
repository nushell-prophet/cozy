use rust.nu
use _clone-or-fail.nu

export def main [] { help nushell }

# Build nushell from source.
#
# By default builds the latest release tag. Use --dev to build
# from main branch (bleeding edge).
# Installs Rust automatically if not already present.
# Safe to re-run — pulls latest and rebuilds.
export def install [
    --dev # Build from main branch instead of latest release
    --no-mcp # Build without MCP support
]: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure Rust is installed
    rust install
    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    let repo_dir = $nu.home-dir | path join git nushell
    if not ($repo_dir | path exists) {
        print "  Cloning nushell..."
        _clone-or-fail https://github.com/nushell/nushell.git $repo_dir
    } else {
        print $"  (ansi green)nushell(ansi reset): repo already cloned"
    }

    cd $repo_dir

    let label = if $dev {
        ^git checkout main
        ^git pull --ff-only
        let rev = ^git rev-parse --short HEAD
        $"main \(($rev)\)"
    } else {
        ^git fetch --tags
        let tag = ^git tag -l '[0-9]*' --sort='-v:refname' | lines | first
        ^git checkout $tag
        $tag
    }

    print $"  Building nushell ($label) — this may take a while..."
    # -j 1 + lto=false to avoid OOM in sandbox VMs (limited RAM).
    if $no_mcp {
        let defaults = open Cargo.toml | get features.default
        if "mcp" in $defaults {
            let features = $defaults | where {|x| $x != "mcp" } | str join ","
            ^cargo build --release -j 1 --config 'profile.release.lto=false' --no-default-features --features $features
        } else {
            print $"  (ansi yellow)Warning(ansi reset): 'mcp' not in default features — building with all defaults"
            ^cargo build --release -j 1 --config 'profile.release.lto=false'
        }
    } else {
        ^cargo build --release -j 1 --config 'profile.release.lto=false'
    }

    let bin = $repo_dir | path join target release nu
    let dest = $cargo_bin | path join nu
    cp $bin $dest

    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    let version = ^($dest) --version | str trim
    print $"  (ansi green)nushell(ansi reset): ($version) installed to ($dest)"
}
