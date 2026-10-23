use rust.nu
use _clone-or-fail.nu
use _install-binary.nu
use _nu-release.nu

# Show the help of this module; `install` runs the nushell build.
export def main [] { help nushell }

# Build nushell from source.
#
# By default builds the latest release tag. Use --dev to build
# from main branch (bleeding edge).
# Installs Rust automatically if not already present.
# Safe to re-run — pulls latest and rebuilds.
#
# --github downloads the latest release binary instead: no Rust, no build.
export def install [
    --dev # Build from main branch instead of latest release
    --no-mcp # Build without MCP support
    --github # Download the latest release binary instead of building
]: nothing -> nothing {
    let dest = $rust.cargo_bin | path join nu

    if $github {
        # Why refuse instead of ignoring: main has no release, and the release
        # binary is built with MCP — either flag would silently not happen.
        if $dev or $no_mcp {
            error make {msg: "--github downloads the latest release build; it cannot honor --dev or --no-mcp"}
        }
        let tag = http get https://api.github.com/repos/nushell/nushell/releases/latest | get tag_name

        _nu-release $tag nu $dest
        report $dest
        return
    }

    rust install

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
        # Why: upstream has legacy tags like 0_5_0 and v0.96.0; version sort ranks
        # '_' above '.', so 0_5_0 would win. Keep only dot-separated version tags.
        let tag = ^git tag --list '--sort=-v:refname'
            | lines
            | where $it =~ '^\d+(\.\d+)+$'
            | first

        ^git checkout $tag
        $tag
    }

    print $"  Building nushell ($label) — this may take a while..."
    let features = if $no_mcp {
        let defaults = open Cargo.toml | get features.default

        if "mcp" in $defaults {
            [--no-default-features --features ($defaults | where $it != "mcp" | str join ",")]
        } else {
            print $"  (ansi yellow)Warning(ansi reset): 'mcp' not in default features — building with all defaults"
            []
        }
    } else { [] }

    # --jobs 1 + lto=false to avoid OOM in sandbox VMs (limited RAM).
    ^cargo build --release --locked --jobs 1 --config 'profile.release.lto=false' ...$features

    _install-binary ($repo_dir | path join target release nu) $dest

    report $dest
}

export def report [dest: path]: nothing -> nothing {
    let version = ^$dest --version | str trim

    print $"  (ansi green)nushell(ansi reset): ($version) installed to ($dest)"
    # Why: the shell you ran this from keeps executing the old binary until it
    # restarts, so the version above won't match what `version` reports here.
    print "  Restart nushell to use it."
}
