# For Windows hosts: swap the Super modifier out of ~/.config/zellij/config.kdl.
#
# Windows reserves Win+key for the OS, so the default zellij bindings
# (Super+...) collide. This rewrites them in place:
#   Super Shift X  → Alt Shift X
#   Super Alt X    → Ctrl Alt X   (Alt+Alt would be invalid)
#   Super X        → Alt X
#
# Replacements are ordered longest-first to avoid partial matches.
# The leading quote anchors replacements to bind strings only.
# Idempotent — running twice is a no-op.
export def main []: nothing -> nothing {
    let path = "~/.config/zellij/config.kdl" | path expand
    if not ($path | path exists) {
        error make {msg: $"zellij config not found at ($path)"}
    }
    open $path --raw
    | str replace --all '"Super Shift ' '"Alt Shift '
    | str replace --all '"Super Alt '   '"Ctrl Alt '
    | str replace --all '"Super '       '"Alt '
    | save --force $path
    print $"patched ($path)"
}
