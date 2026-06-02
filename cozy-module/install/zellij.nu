use rust.nu
use _clone-or-fail.nu

export def main [] { help zellij }

# Build zellij from source without web session sharing.
#
# Clones the repo, checks out the latest release tag, and compiles
# with --no-default-features to exclude `web_server_capability`.
# Installs Rust automatically if not already present.
# Safe to re-run — pulls latest tag and rebuilds.
#
# If the compile is SIGKILL'd (OOM) in a small VM, re-run with
# --low-resource-compilation to lower peak RAM at the cost of runtime speed.
export def install [
    --low-resource-compilation # Split codegen into smaller units to lower peak RAM (avoids OOM in small VMs)
]: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure Rust is installed
    rust install
    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    let repo_dir = $nu.home-dir | path join git zellij
    if not ($repo_dir | path exists) {
        print "  Cloning zellij..."
        _clone-or-fail https://github.com/zellij-org/zellij.git $repo_dir
    } else {
        print $"  (ansi green)zellij(ansi reset): repo already cloned"
    }

    cd $repo_dir
    ^git fetch --tags

    let tag = ^git tag -l 'v*' --sort=-v:refname | lines | first
    print $"  Checking out ($tag)..."
    ^git checkout $tag

    print "  Building zellij without web_server_capability (this may take a while)..."
    # -j 1 + lto=false to avoid OOM in sandbox VMs (limited RAM).
    # Why: zellij's release profile pins codegen-units=1 and opt-level=3, which
    # keep a single rustc's peak memory high; -j 1 + lto=false don't touch it.
    # Raising codegen-units splits the crate into smaller units, and dropping
    # opt-level to 0 removes the dominant memory consumer (optimization passes).
    # Together they trade runtime speed for a build that fits in a tiny VM.
    let low_resource_config = if $low_resource_compilation {
        [--config 'profile.release.codegen-units=256' --config 'profile.release.opt-level=0']
    } else { [] }
    ^cargo build --release -j 1 --no-default-features --features plugins_from_target,vendored_curl --config 'profile.release.lto=false' ...$low_resource_config

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
