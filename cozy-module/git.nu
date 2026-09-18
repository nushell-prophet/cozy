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

# Run git in a directory and return its stdout, or fail with git's own stderr as the message.
# Why not a bare `^git …` at each call: that raises too, but its message is Nushell's generic one
# and git's line is streamed to the terminal, not captured; this captures it so callers and tests
# can read it. It serves the commands that must fail on a failed git call; `git-config-get` keeps
# its own `complete` because null is its answer there.
def git-in [dir: path args: list<string>]: nothing -> string {
    let res = ^git -C $dir ...$args | complete
    if $res.exit_code != 0 {
        error make --unspanned {msg: ($res.stderr | str trim)}
    }
    $res.stdout
}

# Why the common git dir and not `core.hooksPath`: the hook lands where every worktree of the
# repository shares it, and the setting that could point at a tracked directory lives in
# `.git/config`, which is not tracked either — so both cost one manual step per clone, and this one
# covers the worktrees for free.
@category cozy
export def install-change-id-hook [
    path: path = '.' # the repo, or any directory inside it
    --force # replace a different commit-msg hook instead of refusing
]: nothing -> record {
    let common = git-in $path [rev-parse --path-format=absolute --git-common-dir] | str trim
    let dest = $common | path join hooks commit-msg
    # Why refuse under core.hooksPath: git then never looks in the common dir, so an install there
    # would report success for a hook that never fires. `--git-path hooks` is where git looks.
    let live = git-in $path [rev-parse --path-format=absolute --git-path hooks] | str trim
    if $live != ($dest | path dirname) {
        error make --unspanned {
            msg: $"core.hooksPath sends git to ($live), so a hook in ($dest | path dirname) would never run"
            help: "copy the tracked hooks/commit-msg into that directory by hand, or unset core.hooksPath"
        }
    }
    # Why refuse and not overwrite: in an arbitrary repo a commit-msg hook may already belong to
    # something else (husky, a project's own script), and a silent cp would destroy it.
    # Why --force and not detecting an older copy of this hook: the script carries no version
    # marker, and the common case for a differing hook is exactly an older copy of ours, so the
    # human who knows that says so with the flag.
    let status = if ($dest | path exists) {
        if (open --raw $dest) == (open --raw $hook) {
            'already installed'
        } else if $force {
            cp $hook $dest
            ^chmod +x $dest
            'replaced'
        } else {
            error make --unspanned {
                msg: $"a different commit-msg hook already exists: ($dest)"
                help: "compare it with the tracked script; pass --force if it should be replaced"
            }
        }
    } else {
        mkdir ($dest | path dirname)
        cp $hook $dest
        ^chmod +x $dest
        'installed'
    }
    {repo: ($common | path dirname) hook: $dest status: $status}
}

# Compose a link to a file as of the commit that last touched it:
# `<repo>@<change-id>:<path in repo>` — git's own `<rev>:<path>`, with the repo in front so a
# reference written in another repo says where to run git and what to show. The full value is
# printed; a hand-written reference may cut the rev to a prefix.
@category cozy
export def link [
    file: path # a committed file inside a git repo
]: nothing -> string {
    let abs = $file | path expand
    let dir = $abs | path dirname
    let loc = git-in $dir [rev-parse --path-format=absolute --git-common-dir --show-prefix] | lines
    # Why the common dir's parent and not the worktree: a worktree is disposable, the repository is
    # not, and `log --all` there sees every worktree's branches.
    let repo = $loc.0 | path dirname
    let path = $loc.1 + ($abs | path basename)

    # Why the last commit that touched the file and not HEAD: `git show <rev>:<path>` then returns
    # exactly the content the writer saw, the link does not rot when unrelated files move, and that
    # commit's body says why the file is the way it is.
    # Why --literal-pathspecs: a pathspec expands glob characters, so `a[1].txt` also matched
    # `a1.txt` and the link named that file's commit.
    let log = git-in $dir [--literal-pathspecs log -1 '--format=%H%n%(trailers:key=Change-Id,valueonly)' -- $abs]
        | lines
        | compact --empty
    if ($log | is-empty) {
        error make {
            msg: $"($path) is not tracked by git"
            label: {text: "no commit touches this file" span: (metadata $file).span}
            help: "add and commit it first: a link names committed content"
        }
    }
    # Why refuse an uncommitted file: the link would name content no reader can reproduce.
    # Why after the log and not before: an untracked file is dirty too (`??` in porcelain), and the
    # first check to run names the cause — so tracked-ness is asked first, dirtiness second.
    if (git-in $dir [--literal-pathspecs status --porcelain -- $abs] | is-not-empty) {
        error make {
            msg: $"($path) has uncommitted changes"
            label: {text: "dirty in the worktree" span: (metadata $file).span}
            help: "commit it first: a link names committed content"
        }
    }
    let ids = $log | skip 1
    let rev = match ($ids | length) {
        # Why the sha in the same slot when the commit carries no Change-Id: most history predates
        # the hook, and a sha is hex while an id is letters k–z, so `resolve` tells them apart
        # without a second field.
        0 => $log.0
        1 => $ids.0
        # Why refuse two ids: a duplicate is legal (cherry-pick, `--amend -C`), but a link must name
        # one thing, and choosing would be the tooling deciding which copy is real.
        _ => {
            error make {
                msg: $"commit ($log.0) carries ($ids | length) Change-Id trailers"
                label: {text: "last touched by an ambiguous commit" span: (metadata $file).span}
                help: "write the link with the sha by hand"
            }
        }
    }
    $"($repo)@($rev):($path)"
}

# Print the file a link names, at the commit it names. A change-id resolves by search, since
# nothing keeps a mapping (see the "Change-Id" section of the mono-repo-tooling-spec); a sha by
# lookup. A prefix of either is accepted.
@category cozy
export def resolve [
    link: string # `<repo>@<rev>:<path in repo>`, as printed by `cozy git link`
]: nothing -> string {
    let parts = $link | parse --regex '^(?<repo>.+?)@(?<rev>[0-9a-f]+|[k-z]+):(?<path>.+)$'
    if ($parts | is-empty) {
        error make {
            msg: $"not a link: ($link)"
            label: {text: "no <repo>@<rev>:<path> shape" span: (metadata $link).span}
            help: "expected <repo>@<change-id or sha>:<path in repo>"
        }
    }
    let p = $parts.0
    let sha = if $p.rev =~ '^[k-z]' {
        let hits = git-in $p.repo [log --all --format=%H --grep $"^Change-Id: ($p.rev)"] | lines
        match ($hits | length) {
            0 => {
                error make {
                    msg: $"no commit in ($p.repo) carries Change-Id ($p.rev)"
                    label: {text: "unknown change-id" span: (metadata $link).span}
                }
            }
            1 => $hits.0
            _ => {
                error make {
                    msg: $"Change-Id ($p.rev) names ($hits | length) commits in ($p.repo)"
                    label: {text: "ambiguous change-id" span: (metadata $link).span}
                    help: $"pick one by sha: ($hits | str join ', ')"
                }
            }
        }
    } else { $p.rev }
    git-in $p.repo [show $"($sha):($p.path)"]
}

# A repo-local git config value, or null when the key is unset.
def git-config-get [repo: path key: string]: nothing -> any {
    let r = ^git -C $repo config --get $key | complete
    if $r.exit_code == 0 { $r.stdout | str trim } else { null }
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
@category cozy
export def harden [
    path: path = '.' # target repo, or parent for --all
    --all (-a) # harden every git repo in immediate subdirs of path
]: nothing -> table {
    let targets = if $all {
        ls $path
        | where type in [dir symlink]
        | get name
        | where ($it | path join .git | path exists)
    } else {
        if not ($path | path join .git | path exists) {
            error make {
                msg: $"not a git repo: ($path)"
                label: {text: "no .git directory here" span: (metadata $path).span}
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
