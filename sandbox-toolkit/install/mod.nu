# Install claude code using official installer script
export def claude [] {
    use claude.nu [ install ]; install
}

# Install Rust via rustup
export def rust [] {
    use rust.nu [ install ]; install
}

# Install nu_plugin_polars and register it with Nushell
export def polars [] {
    use polars.nu [ install ]; install
}

# Install topiary formatter with nushell support
export def topiary [] {
    use topiary.nu [ install ]; install
}

# Build zellij from source without web session sharing
export def zellij [] {
    use zellij.nu [ install ]; install
}

# Build nushell from source (latest release or --dev for main)
export def nushell [
    --dev # Build from main branch instead of latest release
    --no-mcp # Build without MCP support
] {
    use nushell.nu [ install ]; install --dev=$dev --no-mcp=$no_mcp
}

# Build nu_plugin_image (to png / from png) and register it
export def nu-plugin-image [] {
    use nu-plugin-image.nu [ install ]; install
}
