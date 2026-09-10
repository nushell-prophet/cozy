# End-to-end install: brew tools, vendored modules, dotfiles, skills,
# broot, topiary, Claude Code + nushell MCP.
# Container vs. host is auto-detected via filesystem markers (see bootstrap.nu).
# The installer consumes the committed vendor/ snapshot as-is; refreshing it is
# `toolkit/vendor.nu`'s job, run on the host before a build.
export use bootstrap.nu

# Install claude code using official installer script
@category cozy-install
export def claude []: nothing -> nothing {
    use claude.nu [ install ]; install
}

# Install Rust via rustup
@category cozy-install
export def rust []: nothing -> nothing {
    use rust.nu [ install ]; install
}

# Install nu_plugin_polars and register it with Nushell
@category cozy-install
export def polars []: nothing -> nothing {
    use polars.nu [ install ]; install
}

# Install topiary formatter with nushell support
@category cozy-install
export def topiary []: nothing -> nothing {
    use topiary.nu [ install ]; install
}

# Build zellij from source without web session sharing.
# Pass --low-resource-compilation if the build is OOM-killed in a small VM.
@category cozy-install
export def zellij [
    --low-resource-compilation # Split codegen into smaller units to lower peak RAM (avoids OOM in small VMs)
]: nothing -> nothing {
    use zellij.nu [ install ]; install --low-resource-compilation=$low_resource_compilation
}

# Build nushell from source (latest release or --dev for main)
@category cozy-install
export def nushell [
    --dev # Build from main branch instead of latest release
    --no-mcp # Build without MCP support
]: nothing -> nothing {
    use nushell.nu [ install ]; install --dev=$dev --no-mcp=$no_mcp
}

# Build nu_plugin_image (to png / from png) and register it
@category cozy-install
export def nu-plugin-image []: nothing -> nothing {
    use nu-plugin-image.nu [ install ]; install
}
