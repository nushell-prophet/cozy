# Replace vendored ~/repos/ copies with symlinks to the mounted workspace.
# Enables edit-and-test without rebuild: changes in the workspace are
# immediately visible to autoloaded modules.
#
# Run once after sandbox creation. Safe to re-run (idempotent).
export def main [
    --workspace (-w): path # workspace path (default: $env.WORKSPACE_DIR)
]: nothing -> table {
    let ws = $workspace | default ($env.WORKSPACE_DIR? | default '')
    if $ws == '' {
        error make {msg: 'no workspace mounted — pass --workspace or set $env.WORKSPACE_DIR'}
    }

    let repos_dir = $nu.home-dir | path join repos

    ls $repos_dir
    | where type in [dir symlink]
    | get name
    | each {|repo_path|
        let name = $repo_path | path basename
        let target = $ws | path join $name

        if not ($target | path exists) {
            {name: $name status: skipped}
        } else {
            let already = try {
                let existing = ^readlink $repo_path | str trim
                $existing == ($target | path expand)
            } catch {
                false
            }

            if $already {
                {name: $name status: ok}
            } else {
                rm -rf $repo_path
                ^ln -s $target $repo_path
                {name: $name status: linked}
            }
        }
    }
}
