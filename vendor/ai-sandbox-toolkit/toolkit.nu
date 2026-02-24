export def main [] { }

const repos = {
    ai-sandbox-toolkit: "https://github.com/nushell-prophet/ai-sandbox-toolkit.git"
    nu-goodies: "https://github.com/nushell-prophet/nu-goodies.git"
    nushell-kv: "https://github.com/nushell-prophet/nu-kv.git"
    dotnu: "https://github.com/nushell-prophet/dotnu.git"
    numd: "https://github.com/nushell-prophet/numd.git"
    claude-nu: "https://github.com/nushell-prophet/claude-nu.git"
    nu-cmd-stack: "https://github.com/nushell-prophet/nu-cmd-stack.git"
}

def remote-head-branch []: nothing -> string {
    ^git remote show origin
    | lines
    | where { $in =~ 'HEAD branch:' }
    | first
    | str replace -r '.*HEAD branch:\s*' ''
}

# Convert vendor directories to git repos if needed, pull latest from all
export def "main sync-repos" [--force (-f)] {
    let base = $nu.home-dir | path join git

    $repos | items {|name url|
        let dir = $base | path join $name
        if not ($dir | path exists) {
            print $"  (ansi yellow)($name)(ansi reset): not found, skipping"
            return
        }

        if ($dir | path join '.git' | path exists) {
            cd $dir
            let branch = try { remote-head-branch } catch {
                print $"  (ansi yellow)($name)(ansi reset): cannot reach remote, skipping"
                return
            }
            let current = ^git branch --show-current | str trim
            if $current != $branch {
                let dirty = (^git status --porcelain | str trim) != ''
                if $dirty and not $force {
                    print $"  (ansi red)($name)(ansi reset): has local changes, skipping branch switch ($current) → ($branch) \(use --force to override)"
                    return
                }
                print $"  (ansi cyan)($name)(ansi reset): switching ($current) → ($branch)"
                ^git fetch origin
                ^git clean -fd
                ^git checkout -f -B $branch $"origin/($branch)"
                ^git branch -u $"origin/($branch)"
            } else {
                let dirty = (^git status --porcelain | str trim) != ''
                if $dirty {
                    print $"  (ansi yellow)($name)(ansi reset): has local changes, skipping pull"
                    return
                }
                print $"  (ansi green)($name)(ansi reset): pulling"
                ^git pull --ff-only
            }
        } else {
            print $"  (ansi cyan)($name)(ansi reset): init + fetch"
            cd $dir
            ^git init -b main
            ^git remote add origin $url
            ^git fetch origin
            let branch = try { remote-head-branch } catch {
                print $"  (ansi yellow)($name)(ansi reset): cannot detect remote HEAD branch, skipping"
                return
            }
            ^git reset --hard $"origin/($branch)"
            ^git branch -M $branch
            ^git branch -u $"origin/($branch)"
        }
    }
    | ignore
}

def git-subdirs []: nothing -> list<string> {
    ls | where type == dir
    | where { $in.name | path join .git | path exists }
    | get name
}

def non-git-subdirs []: nothing -> list<string> {
    ls | where type == dir
    | where { $in.name | path join .git | path exists | not $in }
    | get name
}

export def "main mount" [] { help "main mount" }

# Idempotent git init for multi-repo workspaces.
# Registers git subdirs as submodules, ignores non-git subdirs.
# Safe to re-run after adding new dirs.
export def "main mount init" []: nothing -> nothing {
    # sandbox mounts have different ownership — trust all dirs
    ^git config --global safe.directory '*'

    let repos = git-subdirs
    if ($repos | is-empty) {
        error make { msg: 'no git repos found in subdirectories' }
    }

    let fresh = not ('.git' | path exists)

    if $fresh {
        ^git init
    }

    # find repos not yet registered as submodules
    let existing = if $fresh { [] } else {
        ^git submodule status
        | lines
        | each { $in | str trim | split row ' ' | get 1 }
    }

    let new_repos = $repos | where { $in not-in $existing }

    if ($new_repos | is-empty) and (not $fresh) {
        print 'Workspace up to date'
        return
    }

    # .gitmodules — rebuild from all repos
    $repos
    | each {|name|
        $'[submodule "($name)"]
	path = ($name)
	url = ./($name)'
    }
    | str join (char nl)
    | save -f .gitmodules

    # register new submodules
    $new_repos | each {|name|
        ^git config -f .git/config $'submodule.($name).url' $'./($name)'
        ^git config -f .git/config $'submodule.($name).active' true
        let commit = ^git -C $name rev-parse HEAD | str trim
        ^git update-index --add --cacheinfo $'160000,($commit),($name)'
    }

    # .gitignore
    [.DS_Store ...(non-git-subdirs)]
    | str join (char nl)
    | save -f .gitignore

    ^git add .gitmodules .gitignore
    glob *.md | each { ^git add $in }

    let msg = if $fresh {
        'Init workspace'
    } else {
        $'Register submodules: ($new_repos | str join ", ")'
    }
    ^git commit -m $msg

    print $'Registered ($new_repos | length) submodules: ($new_repos | str join ", ")'
}

export def "main history" [] { help "main history" }

const history_db = '~/.config/nushell/history.sqlite3'
const history_columns = "command_line, cwd, start_timestamp, duration_ms, exit_status"
const sandbox_state_dir = '~/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

# Export nushell history to a nuon file.
#
# Reads the sqlite database directly, so it works from any context:
# interactive shell, `nu -c`, scripts, or the Bash tool.
# No login shell (`nu -l`) required.
# Each export gets a timestamped filename; latest symlink always points to the most recent.
export def "main history export" [
    path?: path  # Output file (default: ~/mounted/sandbox-state/history-<timestamp>.nuon)
]: nothing -> nothing {
    let out = $path | default (sandbox-state-path $"history-(date now | format date '%Y%m%d-%H%M%S').nuon")
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make { msg: $"history database not found: ($db)" }
    }
    let items = open $db | query db $"SELECT ($history_columns) FROM history ORDER BY id"
    if ($items | is-empty) {
        print 'No history items to export'
        return
    }
    $items | save --force $out
    # update "latest" symlink
    let link = $out | path dirname | path join 'history-latest.nuon'
    rm -f $link
    ^ln -s ($out | path basename) $link
    print $"Exported ($items | length) history items to ($out)"
}

# Import nushell history from a nuon file.
#
# Inserts directly into the sqlite database, so it works from any context.
# The file should contain a table with columns:
# command_line, cwd, start_timestamp, duration_ms, exit_status.
# Without a path, imports from the latest export via the history-latest.nuon symlink.
export def "main history import" [
    path?: path  # Input file (default: ~/mounted/sandbox-state/history-latest.nuon)
]: nothing -> nothing {
    let src = $path | default (sandbox-state-path 'history-latest.nuon')
    if not ($src | path exists) {
        error make { msg: $"file not found: ($src)" }
    }
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make { msg: $"history database not found: ($db)" }
    }
    let items = open $src
    if ($items | is-empty) {
        print 'No history items to import'
        return
    }
    $items | each {|row|
        open $db
        | query db $"INSERT INTO history \(($history_columns)\) VALUES \(?, ?, ?, ?, ?)" --params [
            $row.command_line
            $row.cwd
            $row.start_timestamp
            $row.duration_ms
            $row.exit_status
        ]
    } | ignore
    print $"Imported ($items | length) history items"
}
