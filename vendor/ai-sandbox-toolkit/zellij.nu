export def main [] { help zellij }

# Build zellij from source without web session sharing.
#
# Clones the repo, checks out the latest release tag, and compiles
# with --no-default-features to exclude `web_server_capability`.
# Requires Rust (use `toolkit rust install` first).
# Safe to re-run — pulls latest tag and rebuilds.
export def install []: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure cargo is available
    if (which cargo | is-empty) {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
        if (which cargo | is-empty) {
            error make { msg: "cargo not found — run `toolkit rust install` first" }
        }
    }

    let repo_dir = $nu.home-dir | path join git zellij
    if not ($repo_dir | path exists) {
        print "  Cloning zellij..."
        ^git clone https://github.com/zellij-org/zellij.git $repo_dir
    } else {
        print $"  (ansi green)zellij(ansi reset): repo already cloned"
    }

    cd $repo_dir
    ^git fetch --tags

    let tag = ^git tag -l 'v*' --sort=-v:refname | lines | first
    print $"  Checking out ($tag)..."
    ^git checkout $tag

    print "  Building zellij without web_server_capability (this may take a while)..."
    # Use thin LTO instead of full — nearly same performance, much less memory.
    # Full LTO (zellij default) OOM-kills the linker in sandbox VMs.
    ^cargo build --release --no-default-features --features plugins_from_target,vendored_curl --config 'profile.release.lto="thin"'

    # Remove brew-installed zellij if present
    if (^brew list zellij | complete).exit_code == 0 {
        print "  Removing brew-installed zellij..."
        ^brew uninstall zellij
    }

    let bin = $repo_dir | path join target release zellij
    let dest = $cargo_bin | path join zellij
    cp $bin $dest

    # Ensure ~/.cargo/bin is in PATH
    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    print $"  (ansi green)zellij(ansi reset): ($tag) installed to ($dest)"
}
