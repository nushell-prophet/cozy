# Keep the global ~/.claude/CLAUDE.md as git history.
#
# `snapshot` commits the live file into ~/.claude's own git repo and pushes it to the history repo
# under sandbox-state. `restore` brings that history into a fresh sandbox, overwriting nothing —
# the one file it writes is a `.gitignore` that is not there yet.
#
# Not a copy per snapshot because: a copy records a version, and what you want to see is what moved
# between two of them.
#
# Divergence between machines is left to the user: a push that is not a fast-forward goes to a
# timestamped branch, and merging those branches is manual. No engineering here — skipping several
# rounds costs nothing while the commits are in the history.

const global_claude_dir = '~/.claude'
const remote_name = 'sb-snapshot'
const tracked_file = 'CLAUDE.md'
const own_branch = 'global-claude'

# The history repo inside the mounted workspace; errors when no workspace is mounted.
def history-repo []: nothing -> path {
    if $env.WORKSPACE_DIR? == null {
        error make --unspanned {msg: "WORKSPACE_DIR not set — sandbox-state requires a mounted workspace"}
    }
    $env.WORKSPACE_DIR | path join sandbox-state global-claude-history
}

# Whether a git command in `dir` succeeds, with its output discarded.
# The arguments come as a list, not as rest args, because: nushell reads any `-x`/`--x` among rest
# args as a flag of this command and refuses to parse it as data for git.
def git-ok [dir: path, args: list<string>]: nothing -> bool {
    (do { ^git -C $dir ...$args } | complete | get exit_code) == 0
}

# Remote-tracking branches of the history repo that already contain the checked-out commit.
# Empty for an unborn HEAD, which is the fresh-machine case.
def remote-branches-with-head [dir: path]: nothing -> string {
    if not (git-ok $dir ['rev-parse' '--verify' '--quiet' 'HEAD']) { return '' }
    ^git -C $dir branch --remotes --list $"($remote_name)/*" --contains HEAD | str trim
}

# Commit the live ~/.claude/CLAUDE.md and push it to the history repo.
#
# Does nothing when the file is unchanged since the last commit, so it is safe to run on every
# machine recreation. Pushes to the history repo's `master` when that is a fast-forward; otherwise
# to a branch named after the timestamp, for you to merge by hand later.
@category cozy-sandbox-state
export def snapshot []: nothing -> nothing {
    let dir = $global_claude_dir | path expand
    # A missing file is not an empty version: `git add` stages the deletion of a tracked file, so
    # without this check a snapshot taken before bootstrap wrote CLAUDE.md pushes a commit that
    # drops it from the history tip, for every machine that restores next.
    let file = $dir | path join $tracked_file
    if not ($file | path exists) {
        error make --unspanned {msg: $"global CLAUDE.md not found: ($file) — run `cozy install bootstrap` first"}
    }
    # Not `git init` here because: on a wrong or missing mount that would silently start an empty
    # history and report success, which is the one failure nobody would notice.
    if not (git-ok $dir ['rev-parse' '--git-dir']) {
        error make --unspanned {msg: $"($dir) is not a git repository — run `cozy sandbox-state global-claude restore` first"}
    }
    if not (git-ok $dir ['remote' 'get-url' $remote_name]) {
        error make --unspanned {msg: $"($dir) has no `($remote_name)` remote — run `cozy sandbox-state global-claude restore` first"}
    }

    ^git -C $dir add $tracked_file
    if not (git-ok $dir ['diff' '--cached' '--quiet' '--' $tracked_file]) {
        let stamp = date now | format date '%Y%m%d-%H%M%S'
        # The pathspec, so a change someone left staged in ~/.claude cannot ride along in a commit
        # whose message says it holds one file.
        ^git -C $dir commit --quiet --message $stamp --message $"snapshot of ($file)" -- $tracked_file
        print $"Committed ($tracked_file) as ($stamp)"
    }

    ^git -C $dir fetch --quiet $remote_name
    # Whether this version reached the history is answered by the remote, not by the index. A push
    # that failed earlier — a read-only mount, or a non-bare history repo refusing an update to the
    # branch it has checked out — leaves a commit that `diff --cached` calls clean, so an
    # index-based check would return "nothing to do" forever while the local repo drifts ahead.
    if (remote-branches-with-head $dir | is-not-empty) {
        print $"($tracked_file) is already in the history — nothing to push"
        return
    }

    # A fast-forward keeps the single line of history. Anything else — diverged or unrelated — goes
    # to its own branch: the push must never fail and must never rewrite what another machine pushed.
    let upstream = $"($remote_name)/master"
    let ff = (not (git-ok $dir ['rev-parse' '--verify' '--quiet' $upstream])) or (git-ok $dir ['merge-base' '--is-ancestor' $upstream 'HEAD'])
    if $ff {
        ^git -C $dir push --quiet $remote_name HEAD:master
        print $"Pushed to ($remote_name)/master"
    } else {
        let branch = date now | format date '%Y%m%d-%H%M%S'
        ^git -C $dir push --quiet $remote_name $"HEAD:refs/heads/($branch)"
        print $"($upstream) has diverged, so it went to branch ($branch) — merge it by hand"
    }
}

# Bring the CLAUDE.md history into ~/.claude, without overwriting anything.
#
# Uses `git reset --mixed`, which moves HEAD and the index and writes no file of its own, so every
# other file in ~/.claude — sessions, credentials, settings — is untouched by construction. Afterwards the
# live CLAUDE.md shows as modified against the history: take the history's version with
# `git restore CLAUDE.md`, or keep yours and let the next snapshot commit it.
#
# Run it after `cozy install bootstrap`, never before: bootstrap step 6 rewrites CLAUDE.md to
# refresh its cozy catalog block.
@category cozy-sandbox-state
export def restore []: nothing -> nothing {
    let repo = history-repo
    # `rev-parse` and not a `.git` directory test because: the history repo may be bare, and a bare
    # repo has no `.git` entry at all.
    if not (git-ok $repo ['rev-parse' '--git-dir']) {
        error make --unspanned {msg: $"no CLAUDE.md history repo at ($repo) — start one with `git init --bare ($repo)`"}
    }

    let dir = $global_claude_dir | path expand
    mkdir $dir
    if not (git-ok $dir ['rev-parse' '--git-dir']) {
        ^git -C $dir init --quiet
    }
    # Fetch from the path instead of through a configured remote, because: setting the remote
    # before the two guards below leaves ~/.claude pointing at the repo that just refused it, and
    # the refusal says to run `snapshot` — which would then push this machine's history there.
    ^git -C $dir fetch --quiet $repo $"+refs/heads/*:refs/remotes/($remote_name)/*"

    # Say which branch is missing, rather than letting `reset` fail with git's "ambiguous argument".
    let upstream = $"($remote_name)/master"
    if not (git-ok $dir ['rev-parse' '--verify' '--quiet' $upstream]) {
        error make --unspanned {msg: $"($repo) has no `master` branch — nothing to restore from"}
    }

    let head = git-ok $dir ['rev-parse' '--verify' '--quiet' 'HEAD']
    let related = $head and (git-ok $dir ['merge-base' 'HEAD' $upstream])
    # Refuse to rewind a branch holding versions the history has never seen. `reset` moves the
    # current branch, so without this, restore on a machine that never managed to push would undo
    # exactly the CLAUDE.md edits it is supposed to protect.
    if $related and (remote-branches-with-head $dir | is-empty) {
        error make --unspanned {msg: $"($dir) has commits the history repo does not — run `cozy sandbox-state global-claude snapshot` first"}
    }
    # A history with no common ancestor is someone else's repo — dotfiles' `push-to-machine`
    # git-inits ~/.claude and commits there during bootstrap. Leave its branch alone and put the
    # CLAUDE.md history on a branch of its own.
    # Why: the dotfiles can be used without cozy, so the two should not interfere. A temporary
    # decision.
    if $head and not $related {
        let branch = $"refs/heads/($own_branch)"
        if (git-ok $dir ['rev-parse' '--verify' '--quiet' $branch]) {
            error make --unspanned {msg: $"($dir) is not on its `($own_branch)` branch — check it out first: `git -C ($dir) symbolic-ref HEAD ($branch)`"}
        }
        ^git -C $dir symbolic-ref HEAD $branch
        print $"($dir) holds an unrelated history — the ($tracked_file) history goes to branch ($own_branch)"
    }

    if (git-ok $dir ['remote' 'get-url' $remote_name]) {
        ^git -C $dir remote set-url $remote_name $repo
    } else {
        ^git -C $dir remote add $remote_name $repo
    }
    ^git -C $dir reset --quiet --mixed $upstream
    # The ignore file lives in the history because ~/.claude holds credentials and session data that
    # must never be committable. It is the one file restore writes: without it on disk the very first
    # `git status` here lists every session file, and staging all of them is one keystroke in lazygit.
    let ignore = $dir | path join '.gitignore'
    if not (git-ok $dir ['ls-files' '--error-unmatch' '.gitignore']) {
        print $"warning: the history has no .gitignore — everything in ($dir) is committable, including .credentials.json"
    } else if not ($ignore | path exists) {
        ^git -C $dir restore '.gitignore'
    }

    print $"Restored the ($tracked_file) history into ($dir) — no files were overwritten"
    let state = ^git -C $dir status --short -- $tracked_file | str trim
    if ($state | is-empty) {
        print $"($tracked_file) already matches the newest version in the history"
    } else if ($state | str starts-with 'D') {
        # Not the "differs" wording for an absent file: it reads as "yours is newer", and the advice
        # that goes with it — keep yours and snapshot it — is what would push the deletion.
        print $"($tracked_file) is not on this machine yet — write the history's version with `git -C ($dir) restore ($tracked_file)`"
    } else {
        print $"($tracked_file) differs from the newest version in the history: `git -C ($dir) diff -- ($tracked_file)`"
        print $"  keep the history's version with `git -C ($dir) restore ($tracked_file)`, or keep yours and snapshot it"
    }
}
