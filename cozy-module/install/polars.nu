use rust.nu
use _nu-release.nu

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
    let plugin_path = $rust.cargo_bin | path join nu_plugin_polars

    if $github {
        # Why the running version, never the latest release: a plugin loads only
        # into the nu it was built for, so a newer one fails at `plugin add`.
        let version = version | get version

        _nu-release $version nu_plugin_polars $plugin_path
        print $"  (ansi green)nu_plugin_polars(ansi reset): installed ($version)"
    } else {
        rust install

        if ($plugin_path | path exists) {
            print $"  (ansi green)nu_plugin_polars(ansi reset): already installed"
        } else {
            print "  Installing nu_plugin_polars (this may take several minutes)..."
            # --jobs 1 to avoid OOM in sandbox VMs (limited RAM).
            ^cargo install nu_plugin_polars --locked --jobs 1
            print $"  (ansi green)nu_plugin_polars(ansi reset): installed"
        }
    }

    # Register the plugin with Nushell
    print "  Registering plugin..."
    plugin add $plugin_path
    print $"  (ansi green)polars plugin(ansi reset): registered — restart Nushell or run: plugin use polars"
}
