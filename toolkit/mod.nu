export def main [] { }

# Why: the submodules export every command so tests can `use` any helper; this file names the public ones.
# A named list flattens the namespace, so a file's subcommands go through an inline module of the same name.
# `main` is imported outside the wrapper: inside it would surface as `vendor vendor`.
export use vendor.nu [ main ]
module vendor { export use vendor.nu [ check ] }
export use vendor
export use docs.nu [ main ]
export use check.nu [ main ]
export use container.nu [ main ]
module container { export use container.nu [ attach refresh-egress reload-egress restart up ] }
export use container
export use sbxw.nu [ main ]
