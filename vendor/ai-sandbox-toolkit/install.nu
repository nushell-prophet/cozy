export def main [] { help install }

# Install Rust via rustup
export def rust [] {
    use rust.nu [install]; install
}

# Install nu_plugin_polars and register it with Nushell
export def polars [] {
    use polars.nu [install]; install
}

# Install topiary formatter with nushell support
export def topiary [] {
    use topiary.nu [install]; install
}

# Build zellij from source without web session sharing
export def zellij [] {
    use zellij.nu [install]; install
}
