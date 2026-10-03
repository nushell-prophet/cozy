# Replace vendored ~/repos/ copies with symlinks to the mounted workspace.
# Enables edit-and-test without rebuild: changes in the workspace are
# immediately visible to autoloaded modules.
#
# Run once after sandbox creation. Safe to re-run (idempotent).
@category cozy
export def main [
    --workspace (-w): path # workspace path (default: $env.WORKSPACE_DIR)
]: nothing -> table {
    let ws = $workspace | default $env.WORKSPACE_DIR?
    if $ws == null {
        error make --unspanned {
            msg: "workspace path not given and WORKSPACE_DIR not set"
            help: "pass --workspace"
        }
    }
    if not ($ws | path exists) {
        error make --unspanned {
            msg: $"workspace path ($ws) does not exist"
            help: "pass --workspace, or check WORKSPACE_DIR"
        }
    }

    let repos_dir = $nu.home-dir | path join repos

    ls $repos_dir
    | where type in [dir symlink]
    | get name
    | each {|repo_path|
        let name = $repo_path | path basename
        let target = $ws | path join $name
        let linked = try { (^readlink $repo_path | str trim) == ($target | path expand) } catch { false }

        let status = if not ($target | path exists) { 'skipped' } else if $linked { 'ok' } else {
            rm --recursive --force $repo_path
            ^ln -s $target $repo_path
            'linked'
        }
        {name: $name status: $status}
    }
}
