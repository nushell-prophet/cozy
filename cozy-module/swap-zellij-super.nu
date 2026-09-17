# For hosts where Super never reaches the shell: swap the modifier out of
# ~/.config/zellij/config.kdl.
#
# Windows reserves Win+key for the OS, and macOS Terminal.app keeps every
# Cmd+key for itself, so the default zellij bindings (Super+...) are dead
# there. This rewrites them in place:
#   Super Shift X  → Alt Shift X
#   Super Alt X    → Ctrl Alt X   (Alt+Alt would be invalid)
#   Super X        → Alt X
#
# Then the resize keys, which are not letters: a terminal without the kitty
# keyboard protocol sends Option+Shift+= as "ESC +" and Option+Shift+- as
# "ESC _", and zellij folds Shift into letters only. So "Alt Shift +" would
# never match, while "Alt +" does:
#   Alt Shift +    → Alt +
#   Alt Shift =    → Alt =
#   Alt Shift -    → Alt _
#
# Replacements are ordered longest-first to avoid partial matches.
# The leading quote anchors replacements to bind strings only.
# Idempotent — running twice is a no-op.
@category cozy
export def main []: nothing -> nothing {
    let path = "~/.config/zellij/config.kdl" | path expand
    if not ($path | path exists) {
        error make --unspanned {msg: $"zellij config not found at ($path)"}
    }
    open $path --raw
    | str replace --all '"Super Shift ' '"Alt Shift '
    | str replace --all '"Super Alt ' '"Ctrl Alt '
    | str replace --all '"Super ' '"Alt '
    | str replace --all '"Alt Shift +"' '"Alt +"'
    | str replace --all '"Alt Shift ="' '"Alt ="'
    | str replace --all '"Alt Shift -"' '"Alt _"'
    | save --force $path
    print $"patched ($path)"
}
