export def main [] { }

const repos = {
    nu-goodies: "https://github.com/nushell-prophet/nu-goodies.git"
    nushell-kv: "https://github.com/nushell-prophet/nu-kv.git"
    dotnu: "https://github.com/nushell-prophet/dotnu.git"
    numd: "https://github.com/nushell-prophet/numd.git"
    claude-nu: "https://github.com/nushell-prophet/claude-nu.git"
    nu-cmd-stack: "https://github.com/nushell-prophet/nu-cmd-stack.git"
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
            let branch = ^git remote show origin | lines | where { $in =~ 'HEAD branch:' } | first | str replace -r '.*HEAD branch:\s*' ''
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
                print $"  (ansi green)($name)(ansi reset): pulling"
                ^git pull --ff-only
            }
        } else {
            print $"  (ansi cyan)($name)(ansi reset): init + fetch"
            cd $dir
            ^git init -b main
            ^git remote add origin $url
            ^git fetch origin
            let branch = ^git remote show origin | lines | where { $in =~ 'HEAD branch:' } | first | str replace -r '.*HEAD branch:\s*' ''
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

export def "main ws" [] { help "main ws" }

# Idempotent git init for multi-repo workspaces.
# Registers git subdirs as submodules, ignores non-git subdirs.
# Safe to re-run after adding new dirs.
export def "main ws init" []: nothing -> nothing {
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
