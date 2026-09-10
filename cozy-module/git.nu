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
