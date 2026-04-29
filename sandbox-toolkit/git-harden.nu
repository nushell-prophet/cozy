# Harden a git repo against concurrent-access corruption on a shared mount.
# Sets gc.auto=0 and receive.autoGc=false in the repo's own .git/config, so
# both host and sandbox git honor the settings regardless of who triggers an
# operation. Mitigates pack/index corruption from VirtioFS torn writes when
# both sides hit .git concurrently (e.g. host lazygit while a sandbox is live).
#
# Why repo-local and not the sandbox's user config: the Dockerfile already
# sets these in ~/.config/git/config inside the sandbox, but host-triggered
# gc (including via lazygit, `git push file://...`, or plain `git gc`) runs
# with the host's git binary and reads the host's ~/.config/git/ — not the
# sandbox's. Repo-local config lives on the shared mount, so both sides
# honor it regardless of which git ran the operation.

def git-config-get [repo: path key: string]: nothing -> any {
    let r = do { git -C $repo config --get $key } | complete
    if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

export def main [
    path: path = '.' # target repo, or parent for --all
    --all (-a) # harden every git repo in immediate subdirs of path
]: nothing -> table {
    let targets = if $all {
        ls $path
        | where type in [dir symlink]
        | get name
        | where {|p| ($p | path join .git | path exists) }
    } else {
        if not (($path | path join .git | path exists)) {
            error make {msg: $"not a git repo: ($path)"}
        }
        [$path]
    }

    $targets | each {|p|
        let before_gc = git-config-get $p 'gc.auto'
        let before_recv = git-config-get $p 'receive.autoGc'
        ^git -C $p config gc.auto 0
        ^git -C $p config receive.autoGc false
        {
            repo: ($p | path expand | path basename)
            prev_gc_auto: ($before_gc | default '(unset)')
            prev_receive_autogc: ($before_recv | default '(unset)')
        }
    }
}
