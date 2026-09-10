const claude_projects_dir = '~/.claude/projects'

# The sandbox-state directory inside the mounted workspace; errors when no workspace is mounted.
def sandbox-state-dir []: nothing -> path {
    if $env.WORKSPACE_DIR? == null {
        error make --unspanned {msg: "WORKSPACE_DIR not set — sandbox-state requires a mounted workspace"}
    }
    $env.WORKSPACE_DIR | path join sandbox-state
}

# Path of a file under sandbox-state, creating the directory when missing.
def sandbox-state-path [filename: string]: nothing -> path {
    let dir = sandbox-state-dir
    mkdir $dir
    $dir | path join $filename
}

# Snapshot Claude Code project sessions to sandbox-state for preservation.
#
# Copies ~/.claude/projects/ into $env.WORKSPACE_DIR/sandbox-state/projects/.
# The workspace directory survives sandbox recreation, so snapshotted sessions
# can be restored into a fresh sandbox.
@category cozy-sandbox-state
export def snapshot [
    path?: path # Output directory (default: $env.WORKSPACE_DIR/sandbox-state/projects)
]: nothing -> nothing {
    let src = $claude_projects_dir | path expand
    if not ($src | path exists) {
        error make --unspanned {msg: $"projects directory not found: ($src)"}
    }
    let dst = $path | default (sandbox-state-path 'projects')
    mkdir $dst
    ^rsync -a --exclude='.DS_Store' $"($src)/" $"($dst)/"
    let count = ls $src | where type == dir | length
    print $"Snapshotted ($count) project\(s) to ($dst)"
}

# Restore Claude Code project sessions from sandbox-state.
#
# Copies sessions from $env.WORKSPACE_DIR/sandbox-state/projects/ into ~/.claude/projects/.
# Existing sessions with the same UUID are skipped (no overwrite).
@category cozy-sandbox-state
export def restore [
    path?: path # Input directory (default: $env.WORKSPACE_DIR/sandbox-state/projects)
]: nothing -> nothing {
    let src = $path | default (sandbox-state-path 'projects')
    if not ($src | path exists) {
        error make --unspanned {msg: $"projects directory not found: ($src)"}
    }
    let dst = $claude_projects_dir | path expand
    mkdir $dst

    let project_dirs = ls $src | where type == dir
    if ($project_dirs | is-empty) {
        print 'No projects to restore'
        return
    }

    for project in $project_dirs {
        let project_name = $project.name | path basename
        let project_dst = $dst | path join $project_name
        mkdir $project_dst

        # Copy files and dirs, skip existing (--ignore-existing)
        ^rsync -a --ignore-existing --exclude='.DS_Store' $"($project.name)/" $"($project_dst)/"
    }
    print $"Restored ($project_dirs | length) project\(s) into ($dst)"
}
