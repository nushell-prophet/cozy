# Install the commit-msg hook that stamps a Change-Id trailer on every new commit.
#
# The id names a change across the rewrites that destroy a sha — amend, rebase, squash — so a
# reference from one repo into another can survive them. The hook is one tracked shell script,
# `hooks/commit-msg` beside this file: it fires on host commits too (lazygit on macOS), where `nu`
# is not on the PATH, so it stays `#!/bin/sh`. Its contract — add an id, never replace one; leave a
# comment-only message alone — is documented in the "Change-Id" section of the mono-repo-tooling-spec
# specification. Why here and not in that repo's toolkit: a cross-repo reference needs the id on
# both sides, and not every repo on the machine lives in the monorepo.
const hook = path self hooks/commit-msg

# Why the common git dir and not `core.hooksPath`: the hook lands where every worktree of the
# repository shares it, and the setting that could point at a tracked directory lives in
# `.git/config`, which is not tracked either — so both cost one manual step per clone, and this one
# covers the worktrees for free.
@category cozy
export def install-change-id-hook [
    path: path = '.' # the repo, or any directory inside it
]: nothing -> record {
    let common = ^git -C $path rev-parse --path-format=absolute --git-common-dir | str trim
    let dest = $common | path join hooks commit-msg
    # Why refuse and not overwrite: in an arbitrary repo a commit-msg hook may already belong to
    # something else (husky, a project's own script), and a silent cp would destroy it.
    let status = if ($dest | path exists) {
        if (open --raw $dest) == (open --raw $hook) {
            'already installed'
        } else {
            error make --unspanned {
                msg: $"a different commit-msg hook already exists: ($dest)"
                help: "compare it with the tracked script and remove it by hand if it should be replaced"
            }
        }
    } else {
        mkdir ($dest | path dirname)
        cp $hook $dest
        ^chmod +x $dest
        'installed'
    }
    {repo: ($common | path dirname), hook: $dest, status: $status}
}

# Harden a git repo against concurrent-access corruption on a shared mount.
# Sets gc.auto=0 and receive.autoGc=false in the repo's own .git/config, so
# both host and sandbox git honor the settings regardless of who triggers an
# operation. Mitigates pack/index corruption from VirtioFS torn writes when
# both sides hit .git concurrently (e.g. host lazygit while a sandbox is live).
#
# Why repo-local and not the sandbox's user config: bootstrap.nu already
# sets gc.auto=0 in ~/.config/git/config inside the sandbox, but host-triggered
# gc (including via lazygit, `git push file://...`, or plain `git gc`) runs
# with the host's git binary and reads the host's ~/.config/git/ — not the
# sandbox's. Repo-local config lives on the shared mount, so both sides
# honor it regardless of which git ran the operation.

def git-config-get [repo: path key: string]: nothing -> any {
    let r = do { git -C $repo config --get $key } | complete
    if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

@category cozy
export def harden [
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
            error make {
                msg: $"not a git repo: ($path)"
                label: {text: "no .git directory here", span: (metadata $path).span}
                help: "pass the repo itself, or --all to harden every git repo in this path's immediate subdirs"
            }
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
