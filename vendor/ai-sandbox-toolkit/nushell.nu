export def main [] { help nushell }

# Build nushell from source.
#
# By default builds the latest release tag. Use --dev to build
# from main branch (bleeding edge).
# Requires Rust (use `toolkit install rust` first).
# Safe to re-run — pulls latest and rebuilds.
export def install [
    --dev  # Build from main branch instead of latest release
]: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure cargo is available
    if (which cargo | is-empty) {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
        if (which cargo | is-empty) {
            error make { msg: "cargo not found — run `toolkit install rust` first" }
        }
    }

    let repo_dir = $nu.home-dir | path join git nushell
    if not ($repo_dir | path exists) {
        print "  Cloning nushell..."
        ^git clone https://github.com/nushell/nushell.git $repo_dir
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
        let tag = ^git tag -l '[0-9]*' --sort=-v:refname | lines | first
        ^git checkout $tag
        $tag
    }

    print $"  Building nushell ($label) — this may take a while..."
    # Thin LTO to avoid OOM in sandbox VMs (same rationale as zellij.nu).
    ^cargo build --release --config 'profile.release.lto="thin"'

    let bin = $repo_dir | path join target release nu
    let dest = $cargo_bin | path join nu
    cp $bin $dest

    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    let version = ^($dest) --version | str trim
    print $"  (ansi green)nushell(ansi reset): ($version) installed to ($dest)"
}
