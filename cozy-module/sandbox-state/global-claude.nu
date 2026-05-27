const global_claude_md = '~/.claude/CLAUDE.md'
const sandbox_state_dir = '~/workspace/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

# Export ~/.claude/CLAUDE.md to a timestamped file in sandbox-state.
#
# Each export gets its own filename; import picks the most recent by name.
export def export [
    path?: path # Output file (default: ~/workspace/mounted/sandbox-state/global-claude-<timestamp>.md)
]: nothing -> nothing {
    let src = $global_claude_md | path expand
    if not ($src | path exists) {
        error make {msg: $"global CLAUDE.md not found: ($src)"}
    }
    let out = $path | default (sandbox-state-path $"global-claude-(date now | format date '%Y%m%d-%H%M%S').md")
    open --raw $src | save --force $out
    print $"Exported global CLAUDE.md to ($out)"
}

# Import ~/.claude/CLAUDE.md from sandbox-state, overwriting the current file.
#
# Without a path, imports from the most recent global-claude-*.md in sandbox-state.
export def import [
    path?: path # Input file (default: latest global-claude-*.md in ~/workspace/mounted/sandbox-state/)
]: nothing -> nothing {
    let src = if $path != null { $path } else {
        let dir = $sandbox_state_dir | path expand
        let files = glob ($dir | path join 'global-claude-*.md') | sort
        if ($files | is-empty) {
            error make {msg: $"no global-claude exports found in ($dir)"}
        }
        $files | last
    }
    if not ($src | path exists) {
        error make {msg: $"file not found: ($src)"}
    }
    let dst = $global_claude_md | path expand
    mkdir ($dst | path dirname)
    open --raw $src | save --force $dst
    print $"Imported global CLAUDE.md from ($src) to ($dst)"
}
