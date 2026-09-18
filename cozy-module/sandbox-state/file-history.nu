# Version history for arbitrary files, as a git repo under sandbox-state.
#
# A sandbox is thrown away; sandbox-state is not. Any file worth keeping across
# sandbox recreation can be committed here, and git then answers what changed
# between two moments — which a flat copy cannot.
#
# The path inside the repo is the file's own absolute path with the leading `/`
# dropped, so `/Users/user/.config/helix/config.toml` lands at
# `Users/user/.config/helix/config.toml`.
# Not folding $HOME into a marker because: the literal path is the honest record
# of the machine it came from, and the same-looking `~/.claude/CLAUDE.md` is a
# different file in the sandbox than on the host.
#
# Sibling of `global-claude.nu`, which keeps the global CLAUDE.md its own way and
# is left alone — its repo, `../global-claude-history/`, is a finished artifact
# with hand-written history from the old machine.

const repo_name = 'file-history'

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

# Creates the repo on first use.
def file-history-repo []: nothing -> path {
    let repo = sandbox-state-path $repo_name
    if not ($repo | path join .git | path exists) {
        git init --quiet $repo
    }
    $repo
}

# Returns whether a commit was made.
def commit-file [repo: path src: path]: nothing -> bool {
    let rel = $src | str replace --regex '^/+' ''
    let dst = $repo | path join $rel
    # Why --raw: a plain `open` on a .md path runs `from md` and would save the
    # parsed AST instead of the file — silently, with no error.
    let text = open --raw $src
    if ($dst | path exists) and (open --raw $dst) == $text {
        return false
    }
    mkdir ($dst | path dirname)
    $text | save --force $dst
    git -C $repo add $rel
    let when = date now | format date '%Y-%m-%d %H:%M:%S'
    git -C $repo commit --quiet --message $src --message $"snapshotted from (sys host | get hostname) at ($when)"
    true
}

# Commit files into the sandbox-state file history, keyed by their full paths.
#
# With paths, adds or updates each one. Without any, refreshes every file the
# repo already tracks — the repo is its own registry, so a file added once keeps
# getting new versions with no separate list to maintain. A tracked file absent
# on this machine is skipped and named in the summary.
# A file whose bytes have not changed produces no commit, so re-running is free.
#
# A bare `*.md` arrives as that literal string, since nushell expands globs only
# for external commands — spread the matches instead: `snapshot ...(glob *.md)`.
@category cozy-sandbox-state
export def snapshot [
    ...paths: path # Files to snapshot (default: every file already tracked)
]: nothing -> nothing {
    let repo = file-history-repo

    let sources = if ($paths | is-empty) {
        # core.quotePath=false keeps non-ASCII paths readable instead of \nnn-escaped.
        ^git -C $repo -c core.quotePath=false ls-files
        | lines
        | each { $"/($in)" }
    } else {
        # Why every path is checked before anything is committed: a typo in the
        # last of five arguments should not leave the first four committed.
        # Not raising inside the `each` because: an error thrown in a closure
        # comes back wrapped in `eval_block_with_input`, which buries the
        # message. Collecting first also names every bad path, not just one.
        let expanded = $paths | path expand
        let missing = $expanded | where not ($it | path exists)
        if ($missing | is-not-empty) {
            let names = $missing | each { $"  ($in)" } | str join (char newline)
            error make {
                msg: $"file not found:(char newline)($names)"
                label: {text: "checked these paths" span: (metadata $paths).span}
                help: 'a bare `*.md` arrives as that literal string — spread the matches instead: `snapshot ...(glob *.md)`'
            }
        }
        $expanded
    }

    if ($sources | is-empty) {
        print $"No files tracked in ($repo) yet — pass a path to add one"
        return
    }

    # Why skip rather than refuse on a refresh: the repo holds host and sandbox
    # paths side by side, so a refresh on either machine always meets files that
    # exist only on the other. Explicit paths were already checked above.
    let absent = $sources | where not ($it | path exists)
    mut committed = 0
    mut unchanged = 0
    for src in ($sources | where $it not-in $absent) {
        if (commit-file $repo $src) {
            $committed += 1
        } else {
            $unchanged += 1
        }
    }

    print $"($committed) committed, ($unchanged) unchanged in ($repo)"
    if ($absent | is-not-empty) {
        print $"($absent | length) skipped, not on this machine:"
        print ($absent | each { $"  ($in)" } | str join (char nl))
    }
}
