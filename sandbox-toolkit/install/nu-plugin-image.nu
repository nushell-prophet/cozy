const repo_url = "https://github.com/fmotalleb/nu_plugin_image.git"

export def main [] { help nu-plugin-image }

# Build nu_plugin_image from source and register it with Nushell.
#
# Clones the repo, checks out the tag matching the running Nushell
# version, and builds with --locked to use pinned dependencies.
# Provides `to png` and `from png`.
# Requires Rust (use `toolkit install rust` first).
# Safe to re-run — pulls latest matching tag and rebuilds.
export def install []: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure cargo is available
    if (which cargo | is-empty) {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
        if (which cargo | is-empty) {
            error make { msg: "cargo not found — run `toolkit install rust` first" }
        }
    }

    let repo_dir = $nu.home-dir | path join git nu_plugin_image
    if not ($repo_dir | path exists) {
        print "  Cloning nu_plugin_image..."
        ^git clone $repo_url $repo_dir
    } else {
        print $"  (ansi green)nu_plugin_image(ansi reset): repo already cloned"
    }

    cd $repo_dir
    ^git fetch --tags

    # Plugin versions track Nushell versions — build the matching tag.
    let nu_ver = version | get version
    let tag = $"v($nu_ver)"
    print $"  Checking out ($tag)..."
    ^git checkout $tag

    print $"  Building nu_plugin_image ($tag) — this may take a few minutes..."
    ^cargo build --release --locked

    let bin = $repo_dir | path join target release nu_plugin_image
    let dest = $cargo_bin | path join nu_plugin_image
    cp $bin $dest

    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    print "  Registering plugin..."
    plugin add $dest
    print $"  (ansi green)image plugin(ansi reset): ($tag) registered — restart Nushell or run: plugin use image"
}
