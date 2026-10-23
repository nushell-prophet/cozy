use rust.nu
use _clone-or-fail.nu
use _install-binary.nu

const repo_url = "https://github.com/fmotalleb/nu_plugin_image.git"

# Show the help of this module; `install` runs the nu_plugin_image build.
export def main [] { help nu-plugin-image }

# Build nu_plugin_image from source and register it with Nushell.
#
# Clones the repo, checks out the tag matching the running Nushell
# version, and builds with --locked to use pinned dependencies.
# Provides `to png` and `from png`.
# Installs Rust automatically if not already present.
# Safe to re-run — pulls latest matching tag and rebuilds.
export def install []: nothing -> nothing {
    rust install

    let repo_dir = $nu.home-dir | path join git nu_plugin_image

    if not ($repo_dir | path exists) {
        print "  Cloning nu_plugin_image..."
        _clone-or-fail $repo_url $repo_dir
    } else {
        print $"  (ansi green)nu_plugin_image(ansi reset): repo already cloned"
    }

    cd $repo_dir
    ^git fetch --tags

    # Plugin versions track Nushell versions — build the matching tag.
    let tag = $"v(version | get version)"

    print $"  Checking out ($tag)..."
    ^git checkout $tag

    print $"  Building nu_plugin_image ($tag) — this may take a few minutes..."
    # --jobs 1 to avoid OOM in sandbox VMs (limited RAM).
    # Not thin LTO because: even thin LTO OOM-kills the linker in sandbox VMs.
    ^cargo build --release --locked --jobs 1 --config 'profile.release.lto=false'

    let bin = $repo_dir | path join target release nu_plugin_image
    let dest = $rust.cargo_bin | path join nu_plugin_image

    _install-binary $bin $dest

    print "  Registering plugin..."
    plugin add $dest
    print $"  (ansi green)image plugin(ansi reset): ($tag) registered — restart Nushell or run: plugin use image"
}
