export def main [] { help polars }

# Install nu_plugin_polars and register it with Nushell.
#
# Installs Rust automatically if not already present.
# Compiles from source — may take several minutes.
# Safe to re-run — skips steps already done.
export def install []: nothing -> nothing {
    let cargo_bin = $nu.home-dir | path join .cargo bin

    # Ensure Rust is installed
    use rust.nu
    rust install
    if $cargo_bin not-in $env.PATH {
        $env.PATH = ($env.PATH | prepend $cargo_bin)
    }

    let plugin_path = $cargo_bin | path join nu_plugin_polars
    if ($plugin_path | path exists) {
        print $"  (ansi green)nu_plugin_polars(ansi reset): already installed"
    } else {
        print "  Installing nu_plugin_polars (this may take several minutes)..."
        # -j 1 to avoid OOM in sandbox VMs (limited RAM).
        ^cargo install nu_plugin_polars -j 1
        print $"  (ansi green)nu_plugin_polars(ansi reset): installed"
    }

    # Register the plugin with Nushell
    print "  Registering plugin..."
    plugin add $plugin_path
    print $"  (ansi green)polars plugin(ansi reset): registered — restart Nushell or run: plugin use polars"
}
