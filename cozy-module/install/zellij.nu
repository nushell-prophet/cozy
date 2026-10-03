use rust.nu
use _clone-or-fail.nu
use _install-binary.nu

# Show the help of this module; `install` builds or downloads zellij.
export def main [] { help zellij }

# Build zellij from source without web session sharing, or download the release with --github.
#
# Clones the repo, checks out the latest release tag, and compiles
# with --no-default-features to exclude `web_server_capability`.
# Installs Rust automatically if not already present.
# Safe to re-run — pulls latest tag and rebuilds.
#
# If the compile is SIGKILL'd (OOM) in a small VM, re-run with
# --low-resource-compilation to lower peak RAM at the cost of runtime speed.
#
# --github downloads the latest release binary instead: no Rust, no build.
# It takes the release zellij publishes without web session sharing, the
# same as the source build; --web-server takes the full one instead.
export def install [
    --low-resource-compilation # Split codegen into smaller units to lower peak RAM (avoids OOM in small VMs)
    --github # Download the latest release binary instead of building
    --web-server # With --github, take the release with web session sharing
]: nothing -> nothing {
    let dest = $rust.cargo_bin | path join zellij

    # Why refuse instead of ignoring: a downloaded binary has no build to lower.
    if $github and $low_resource_compilation {
        error make {msg: "--github downloads a release build; it cannot honor --low-resource-compilation"}
    }
    # Why refuse instead of ignoring: the source build never has the web server.
    if $web_server and not $github {
        error make {msg: "--web-server needs --github; the source build is always without web session sharing"}
    }

    let tag = if $github {
        download $dest --web-server=$web_server
    } else {
        build $dest --low-resource-compilation=$low_resource_compilation
    }

    # Remove brew-installed zellij if present
    if (^brew list zellij | complete).exit_code == 0 {
        print "  Removing brew-installed zellij..."
        ^brew uninstall zellij
    }

    print $"  (ansi green)zellij(ansi reset): ($tag) installed to ($dest)"
}

# Builds the latest release tag from source into $dest; returns the tag.
def build [
    dest: path
    --low-resource-compilation
]: nothing -> string {
    rust install

    let repo_dir = $nu.home-dir | path join git zellij
    if not ($repo_dir | path exists) {
        print "  Cloning zellij..."
        _clone-or-fail https://github.com/zellij-org/zellij.git $repo_dir
    } else {
        print $"  (ansi green)zellij(ansi reset): repo already cloned"
    }

    cd $repo_dir
    ^git fetch --tags

    let tag = ^git tag --list 'v*' '--sort=-v:refname' | lines | first
    print $"  Checking out ($tag)..."
    ^git checkout $tag

    print "  Building zellij without web_server_capability (this may take a while)..."
    # --jobs 1 + lto=false to avoid OOM in sandbox VMs (limited RAM).
    # Why: zellij's release profile pins codegen-units=1 and opt-level=3, which
    # keep a single rustc's peak memory high; --jobs 1 + lto=false don't touch it.
    # Raising codegen-units splits the crate into smaller units, and dropping
    # opt-level to 0 removes the dominant memory consumer (optimization passes).
    # Together they trade runtime speed for a build that fits in a tiny VM.
    let low_resource_config = if $low_resource_compilation {
        [--config 'profile.release.codegen-units=256' --config 'profile.release.opt-level=0']
    } else { [] }
    ^cargo build --release --locked --jobs 1 --no-default-features --features plugins_from_target,vendored_curl --config 'profile.release.lto=false' ...$low_resource_config

    _install-binary ($repo_dir | path join target release zellij) $dest
    $tag
}

# Puts the latest release binary at $dest; returns its tag.
def download [
    dest: path
    --web-server
]: nothing -> string {
    let tag = http get https://api.github.com/repos/zellij-org/zellij/releases/latest | get tag_name
    let os = match $nu.os-info.name {
        linux => 'unknown-linux-musl'
        macos => 'apple-darwin'
        $other => { error make {msg: $"no zellij release build for OS ($other)"} }
    }
    let flavor = if $web_server { 'zellij' } else { 'zellij-no-web' }
    let url = $"https://github.com/zellij-org/zellij/releases/download/($tag)/($flavor)-($nu.os-info.arch)-($os).tar.gz"

    print $"  Downloading zellij ($tag) from ($url)..."
    let response = http get --raw --full --allow-errors $url
    if $response.status != 200 {
        error make {
            msg: $"no zellij release asset at ($url): HTTP ($response.status)"
            help: "a fresh release may still be uploading its assets; build from source instead (drop --github)"
        }
    }

    let tmp = mktemp --directory
    $response.body | save ($tmp | path join archive.tar.gz)
    ^tar --extract --gzip --file ($tmp | path join archive.tar.gz) --directory $tmp zellij
    mkdir ($dest | path dirname)
    _install-binary ($tmp | path join zellij) $dest
    rm --recursive $tmp
    $tag
}
