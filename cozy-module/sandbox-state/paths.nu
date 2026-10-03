# Helpers shared by the sandbox-state modules; `mod.nu` does not re-export this file.

# The sandbox-state directory inside the mounted workspace; errors when no workspace is mounted.
export def sandbox-state-dir []: nothing -> path {
    if $env.WORKSPACE_DIR? == null {
        error make --unspanned {msg: "WORKSPACE_DIR not set — sandbox-state requires a mounted workspace"}
    }
    $env.WORKSPACE_DIR | path join sandbox-state
}

# Path of a file under sandbox-state, creating the directory when missing.
export def sandbox-state-path [filename: string]: nothing -> path {
    let dir = sandbox-state-dir
    mkdir $dir
    $dir | path join $filename
}
