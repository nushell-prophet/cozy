const claude_projects_dir = '~/.claude/projects'
const sandbox_state_dir = '~/workspace/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

# Export Claude Code project sessions to sandbox-state for preservation.
#
# Copies ~/.claude/projects/ into ~/workspace/mounted/sandbox-state/projects/.
# The mounted directory survives sandbox recreation, so exported sessions
# can be imported into a fresh sandbox.
export def export [
    path?: path # Output directory (default: ~/workspace/mounted/sandbox-state/projects)
]: nothing -> nothing {
    let src = $claude_projects_dir | path expand
    if not ($src | path exists) {
        error make {msg: $"projects directory not found: ($src)"}
    }
    let dst = $path | default (sandbox-state-path 'projects')
    mkdir $dst
    ^rsync -a --exclude='.DS_Store' $"($src)/" $"($dst)/"
    let count = ls $src | where type == dir | length
    print $"Exported ($count) project\(s) to ($dst)"
}

# Import Claude Code project sessions from sandbox-state.
#
# Copies sessions from ~/workspace/mounted/sandbox-state/projects/ into ~/.claude/projects/.
# Existing sessions with the same UUID are skipped (no overwrite).
export def import [
    path?: path # Input directory (default: ~/workspace/mounted/sandbox-state/projects)
]: nothing -> nothing {
    let src = $path | default (sandbox-state-path 'projects')
    if not ($src | path exists) {
        error make {msg: $"projects directory not found: ($src)"}
    }
    let dst = $claude_projects_dir | path expand
    mkdir $dst

    let project_dirs = ls $src | where type == dir
    if ($project_dirs | is-empty) {
        print 'No projects to import'
        return
    }

    mut imported = 0
    for project in $project_dirs {
        let project_name = $project.name | path basename
        let project_dst = $dst | path join $project_name
        mkdir $project_dst

        # Copy files and dirs, skip existing (--ignore-existing)
        ^rsync -a --ignore-existing --exclude='.DS_Store' $"($project.name)/" $"($project_dst)/"
        $imported += 1
    }
    print $"Imported ($imported) project\(s) into ($dst)"
}
