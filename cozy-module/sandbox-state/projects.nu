use paths.nu *

# Why from $env.HOME and not a `~` const: the tests point HOME at a temp dir.
export def claude-projects-dir []: nothing -> path {
    $env.HOME | path join .claude projects
}

# Written by `restore`, read by `snapshot`. It lives in ~/.claude, which a new
# machine does not have, so its absence means "this machine was never restored".
# It holds this machine's id, and its mtime is the time of the last restore.
export def restored-marker []: nothing -> path {
    $env.HOME | path join .claude .cozy-projects-restored
}

# Keeps the machine id across restores; a marker without one gets a new id.
export def mark-restored []: nothing -> nothing {
    let marker = restored-marker
    let id = if ($marker | path exists) { open --raw $marker | str trim } else { '' }

    $id | default --empty { random uuid } | save --force $marker
}

# Which machine wrote the snapshot last, and when; it sits beside the snapshot.
export def last-snapshot-file [dst: path]: nothing -> path {
    $dst | path dirname | path join projects-last-snapshot.nuon
}

# Snapshot Claude Code project sessions to sandbox-state for preservation.
#
# Mirrors ~/.claude/projects/ into $env.WORKSPACE_DIR/sandbox-state/projects/.
# The workspace directory survives sandbox recreation, so snapshotted sessions
# can be restored into a fresh sandbox.
#
# A file the snapshot holds and ~/.claude/projects no longer does is moved to
# `projects-deleted/<timestamp>/` beside the snapshot, not deleted. After a
# restore, every snapshot file is also in ~/.claude/projects, so such a file was
# removed on purpose — by `claude-nu project-move`, or by hand.
#
# Refuses to run when the snapshot is not empty and `restore` has not run on
# this machine: there the missing files mean only that nothing was restored yet.
@category cozy-sandbox-state
export def snapshot [
    path?: path # Output directory (default: $env.WORKSPACE_DIR/sandbox-state/projects)
]: nothing -> nothing {
    let src = claude-projects-dir

    if not ($src | path exists) {
        error make --unspanned {msg: $"projects directory not found: ($src)"}
    }
    let dst = $path | default { sandbox-state-path 'projects' }

    mkdir $dst
    if not (restored-marker | path exists) {
        if (ls $dst | is-not-empty) {
            error make --unspanned {
                msg: $"($dst) holds sessions, and `projects restore` has not run on this machine"
                help: "a snapshot now would move every session missing here out of the snapshot; run `cozy sandbox-state projects restore` first"
            }
        }
        # An empty snapshot has nothing to restore, so this machine counts as restored.
        mark-restored
    }

    # Why only a warning: the sessions are moved aside, not lost, and one
    # machine is the usual case. Two machines on one sandbox-state each need a
    # restore before every snapshot, and this is the cheap sign that one did not.
    let me = open --raw (restored-marker) | str trim
    let last_file = last-snapshot-file $dst

    if ($last_file | path exists) {
        let last = open $last_file
        let restored = ls (restored-marker) | get 0.modified

        if $last.machine != $me and $last.time > $restored {
            print --stderr $"warning: another machine wrote this snapshot at ($last.time | format date '%Y-%m-%d %H:%M'), after the last restore here. Sessions it added and this machine lacks move to projects-deleted/. Run `cozy sandbox-state projects restore` before `snapshot` on each machine."
        }
    }

    let backup = $dst | path dirname | path join projects-deleted (date now | format date '%Y%m%d-%H%M%S')

    # Why two passes: `--backup` also saves the old version of every file it
    # updates, and a transcript grows on every turn — one pass would copy the
    # whole store into the backup on each snapshot. `--existing
    # --ignore-existing` transfers nothing, so this pass only deletes, and the
    # backup holds only what was deleted.
    ^rsync --archive --existing --ignore-existing --delete --backup $"--backup-dir=($backup)" --exclude='.DS_Store' $"($src)/" $"($dst)/"
    ^rsync --archive --exclude='.DS_Store' $"($src)/" $"($dst)/"
    {machine: $me time: (date now)} | save --force $last_file

    let count = ls $src | where type == dir | length

    print $"Snapshotted ($count) project\(s) to ($dst)"
    if ($backup | path exists) {
        let moved = glob $"($backup)/**/*" --no-dir | length

        print $"Moved ($moved) file\(s) gone from ($src) to ($backup)"
    }
}

# Restore Claude Code project sessions from sandbox-state.
#
# Copies sessions from $env.WORKSPACE_DIR/sandbox-state/projects/ into ~/.claude/projects/.
# Existing sessions with the same UUID are skipped (no overwrite).
# Leaves the marker that lets `snapshot` mirror this machine into the snapshot.
@category cozy-sandbox-state
export def restore [
    path?: path # Input directory (default: $env.WORKSPACE_DIR/sandbox-state/projects)
]: nothing -> nothing {
    let src = $path | default { sandbox-state-path 'projects' }

    if not ($src | path exists) {
        error make --unspanned {msg: $"projects directory not found: ($src)"}
    }
    let dst = claude-projects-dir

    mkdir $dst

    let project_dirs = ls $src | where type == dir

    if ($project_dirs | is-empty) {
        mark-restored
        print 'No projects to restore'
        return
    }

    for project in $project_dirs {
        let project_name = $project.name | path basename
        let project_dst = $dst | path join $project_name

        mkdir $project_dst

        # Copy files and dirs, skip existing (--ignore-existing)
        ^rsync --archive --ignore-existing --exclude='.DS_Store' $"($project.name)/" $"($project_dst)/"
    }
    mark-restored
    print $"Restored ($project_dirs | length) project\(s) into ($dst)"
}
