# Detect the host platform from the Docker sandbox workspace path.
#
# Docker sandbox mounts the host workspace at its original path,
# so WORKSPACE_DIR reveals the host OS via path conventions:
#   /Users/...         → macos
#   /c/... C:/... or /mnt/... → windows
#   anything else      → linux
export def main []: nothing -> string {
    let workspace = $env.WORKSPACE_DIR? | default ""
    if ($workspace | str starts-with "/Users/") {
        "macos"
    } else if ($workspace =~ '^/:?[a-zA-Z]/') or ($workspace | str starts-with "/mnt/") {
        "windows"
    } else {
        "linux"
    }
}

# Activate platform-specific configs for the detected (or given) host.
#
# Transforms config files in place. Idempotent — skips files already
# matching the target platform.
# Currently handles: zellij keybindings (Super→Alt for Windows).
export def apply [
    platform?: string # override auto-detection
]: nothing -> nothing {
    let host = $platform | default (main)

    if $host == "macos" {
        print $"Platform: ($host) — configs are macOS-native, nothing to transform"
        return
    }

    let transforms = [
        [name path];
        [zellij ("~/.config/zellij/config.kdl" | path expand)]
    ]
        | where { $in.path | path exists }

    if ($transforms | is-empty) {
        print $"Platform: ($host) — no config files found to transform"
        return
    }

    let applied = $transforms | each {|t|
            let original = open $t.path --raw
            let transformed = transform $host $t.name $original
            if $original == $transformed {
                null
            } else {
                $transformed | save --force $t.path
                $t.name
            }
        } | compact

    if ($applied | is-empty) {
        print $"Platform: ($host) — all configs already transformed"
    } else {
        print $"Platform: ($host) — transformed: ($applied | str join ', ')"
    }
}

# Apply platform-specific transformations to a config's content.
def transform [host: string name: string content: string]: nothing -> string {
    match $name {
        "zellij" => (transform-zellij $host $content)
        _ => $content
    }
}

# Transform zellij config for a target platform.
#
# The macOS config uses Super (Cmd) for global shortcuts. On Windows,
# Win+key is reserved by the OS, so we remap modifiers.
#
# Replacements are ordered longest-first to avoid partial matches.
# The leading quote anchors replacements to bind strings only.
#
# Convention in config.kdl: compound modifiers use title case
# ("Super Shift", "Super Alt") with Super always first.
def transform-zellij [host: string content: string]: nothing -> string {
    if $host == "windows" {
        $content
        | str replace --all '"Super Shift ' '"Alt Shift '
        | str replace --all '"Super Alt ' '"Ctrl Alt '
        | str replace --all '"Super ' '"Alt '
    } else {
        $content
    }
}
