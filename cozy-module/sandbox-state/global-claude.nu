const global_claude_md = '~/.claude/CLAUDE.md'

def sandbox-state-dir []: nothing -> path {
    if $env.WORKSPACE_DIR? == null {
        error make --unspanned {msg: "WORKSPACE_DIR not set — sandbox-state requires a mounted workspace"}
    }
    $env.WORKSPACE_DIR | path join sandbox-state
}

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = sandbox-state-dir
    mkdir $dir
    $dir | path join $filename
}

# Snapshot ~/.claude/CLAUDE.md to a timestamped file in sandbox-state.
#
# Each snapshot gets its own filename; restore picks the most recent by name.
export def snapshot [
    path?: path # Output file (default: $env.WORKSPACE_DIR/sandbox-state/global-claude-<timestamp>.md)
]: nothing -> nothing {
    let src = $global_claude_md | path expand
    if not ($src | path exists) {
        error make --unspanned {msg: $"global CLAUDE.md not found: ($src)"}
    }
    let out = $path | default (sandbox-state-path $"global-claude-(date now | format date '%Y%m%d-%H%M%S').md")
    open --raw $src | save --force $out
    print $"Snapshotted global CLAUDE.md to ($out)"
}

# Restore ~/.claude/CLAUDE.md from sandbox-state, overwriting the current file.
#
# Without a path, restores from the most recent global-claude-*.md in sandbox-state.
export def restore [
    path?: path # Input file (default: latest global-claude-*.md in $env.WORKSPACE_DIR/sandbox-state/)
]: nothing -> nothing {
    let src = if $path != null { $path } else {
        let dir = sandbox-state-dir
        let files = glob ($dir | path join 'global-claude-*.md') | sort
        if ($files | is-empty) {
            error make --unspanned {msg: $"no global-claude snapshots found in ($dir)"}
        }
        $files | last
    }
    if not ($src | path exists) {
        error make --unspanned {msg: $"file not found: ($src)"}
    }
    let dst = $global_claude_md | path expand
    mkdir ($dst | path dirname)
    open --raw $src | save --force $dst
    print $"Restored global CLAUDE.md from ($src) to ($dst)"
}
