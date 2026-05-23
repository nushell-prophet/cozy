# Merge default settings into ~/.claude/settings.json.
# Existing user values take precedence — defaults only fill in what's missing.
# Safe to re-run: no-op when all defaults are already present.
export def --env claude-settings [] {
    let settings_path = $nu.home-dir | path join .claude settings.json
    let defaults = {effortLevel: high cleanupPeriodDays: 999}

    if ($settings_path | path exists) {
        let current = open $settings_path
        let merged = $defaults | merge $current
        if $merged != $current {
            $merged | save -f $settings_path
        }
    } else {
        mkdir ($settings_path | path dirname)
        $defaults | save -f $settings_path
    }

    # "max" effort only works via env var, not settings.json
    $env.CLAUDE_CODE_EFFORT_LEVEL = "max"
}
