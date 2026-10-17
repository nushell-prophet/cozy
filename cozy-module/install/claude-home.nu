# Fills ~/.claude for cozy; named apart from `claude` so it is not read as a Claude Code subcommand.

# Skill repos vendored under ~/repos; a later repo wins when both ship the same name.
const skill_repos = [my-claude-skills nushell-skills]

# Deploy cozy's Claude Code settings and every skill, agent, output style and mod
# of the vendored skill repos into ~/.claude.
# Why cozy and not dotfiles: dotfiles owns only ~/.config, where every file comes
# from the repo; ~/.claude also holds what Claude Code and bootstrap write themselves.
export def main [cozy_root: path]: nothing -> nothing {
    let claude_dir = $nu.home-dir | path join '.claude'
    mkdir $claude_dir

    # Why merge: Claude Code keeps its own keys in settings.json (/config, plugins),
    # and a re-run must not drop them; the shipped keys still win.
    let settings = $claude_dir | path join 'settings.json'
    let shipped = open ($cozy_root | path join 'docker-files' 'claude' 'settings.json')
    let current = if ($settings | path exists) { open $settings } else { {} }
    $current | merge deep $shipped | save --force $settings
    cp ($cozy_root | path join 'docker-files' 'claude' 'keybindings.json') $claude_dir

    let plugins = $skill_repos | each {|repo| $nu.home-dir | path join 'repos' $repo 'plugins' }
    let items = $plugins | each {|src|
        if not ($src | path exists) {
            error make {msg: $"($src) is missing — bootstrap Step 3 should have populated it from vendor/"}
        }
        [
            ...(glob ($src | path join '*' 'skills' '*') --no-file | each {|p| {kind: skills name: ($p | path basename) path: $p} })
            ...(glob ($src | path join '*' 'mods' '*') --no-file | each {|p| {kind: mods name: ($p | path basename) path: $p} })
            ...(glob ($src | path join '*' 'agents' '*.md') --no-dir | each {|p| {kind: agents name: ($p | path basename) path: $p} })
            ...(glob ($src | path join '*' 'output-styles' '*.md') --no-dir | each {|p| {kind: output-styles name: ($p | path basename) path: $p} })
        ]
    }
    | flatten
    | reverse | uniq-by kind name | reverse

    for item in $items {
        let dest = $claude_dir | path join $item.kind $item.name
        mkdir ($dest | path dirname)
        match $item.kind {
            skills => { ^rsync --archive --delete $"($item.path)/" $"($dest)/" }
            # Why no --delete: Claude Code writes generated typings into a mod's
            # .claude-plugin/types, and deleting them on every deploy is churn.
            mods => { ^rsync --archive $"($item.path)/" $"($dest)/" }
            _ => { cp $item.path $dest }
        }
    }
    print $"deployed ($items | length) skills, agents, output styles and mods into ($claude_dir)"
}
