use _install-binary.nu

# Show the help of this module; `install` runs the nu_plugin_polars build.
export def main [] { help polars }

# Install nu_plugin_polars and register it with Nushell.
#
# Installs Rust automatically if not already present.
# Compiles from source — may take several minutes.
# Safe to re-run — skips the cargo build when the plugin binary is already
# there; `plugin add` re-registers on every run.
#
# --github takes the binary from the nushell release whose tag equals the
# running `nu` version instead: no Rust, no build, and the binary is replaced
# on every run.
export def install [
    --github # Download the prebuilt plugin from the nushell release matching the running nu
]: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin
    let plugin_path = $cargo_bin | path join nu_plugin_polars

    if $github {
        download $plugin_path
    } else {
        # Ensure Rust is installed
        use rust.nu
        rust install
        if $cargo_bin not-in $env.PATH {
            $env.PATH = ($env.PATH | prepend $cargo_bin)
        }

        if ($plugin_path | path exists) {
            print $"  (ansi green)nu_plugin_polars(ansi reset): already installed"
        } else {
            print "  Installing nu_plugin_polars (this may take several minutes)..."
            # -j 1 to avoid OOM in sandbox VMs (limited RAM).
            ^cargo install nu_plugin_polars --locked -j 1
            print $"  (ansi green)nu_plugin_polars(ansi reset): installed"
        }
    }

    # Register the plugin with Nushell
    print "  Registering plugin..."
    plugin add $plugin_path
    print $"  (ansi green)polars plugin(ansi reset): registered — restart Nushell or run: plugin use polars"
}

# Puts nu_plugin_polars from the nushell release tarball at $dest.
def download [dest: path]: nothing -> nothing {
    # Why the running version, never the latest release: a plugin loads only
    # into the nu it was built for, so a newer one fails at `plugin add`.
    let version = version | get version
    let os = match $nu.os-info.name {
        linux => 'unknown-linux-gnu'
        macos => 'apple-darwin'
        $other => { error make {msg: $"no nushell release build for OS ($other)"} }
    }
    let target = $"($nu.os-info.arch)-($os)"
    let archive = $"nu-($version)-($target)"
    let url = $"https://github.com/nushell/nushell/releases/download/($version)/($archive).tar.gz"

    print $"  Downloading nu_plugin_polars ($version) from ($url)..."
    let response = http get --raw --full --allow-errors $url
    if $response.status != 200 {
        error make {
            msg: $"no nushell release asset for nu ($version) on ($target): HTTP ($response.status)"
            help: "a dev build of nu has no release; build the plugin from source with `cozy install polars`"
        }
    }

    let tmp = mktemp --directory
    $response.body | save ($tmp | path join archive.tar.gz)
    ^tar --extract --gzip --file ($tmp | path join archive.tar.gz) --directory $tmp $"($archive)/nu_plugin_polars"
    mkdir ($dest | path dirname)
    _install-binary ($tmp | path join $archive nu_plugin_polars) $dest
    rm --recursive $tmp
    print $"  (ansi green)nu_plugin_polars(ansi reset): installed ($version)"
}
