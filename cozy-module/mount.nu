# Immediate subdirectories that are git repos.
def git-subdirs []: nothing -> list<string> {
    ls | where type == dir
    | where ($it.name | path join .git | path exists)
    | get name
}

# Immediate subdirectories that are not git repos.
def non-git-subdirs []: nothing -> list<string> {
    ls | where type == dir
    | where not ($it.name | path join .git | path exists)
    | get name
}

# Idempotent git init for multi-repo workspaces.
# Registers git subdirs as submodules, ignores non-git subdirs.
# Safe to re-run after adding new dirs.
@category cozy
export def init []: nothing -> nothing {
    # sandbox mounts have different ownership — trust all dirs
    # safe.directory='*' is asserted in three places: here, bootstrap.nu's XDG
    # config (Step 2), and the git-safe-directory.nu autoload (self-heals after
    # sandbox create narrows it). Edit one, check the other two.
    ^git config --global safe.directory '*'

    let repos = git-subdirs
    if ($repos | is-empty) {
        error make --unspanned {msg: 'no git repos found in subdirectories'}
    }

    let fresh = not ('.git' | path exists)

    if $fresh {
        ^git init
    }

    # find repos not yet registered as submodules
    let existing = if $fresh { [] } else {
        ^git submodule status
        | lines
        | each { str trim | split row ' ' | get 1 }
    }

    let new_repos = $repos | where $it not-in $existing

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
    | save --force .gitmodules

    # register new submodules
    $new_repos | each {|name|
        ^git config -f .git/config $'submodule.($name).url' $'./($name)'
        ^git config -f .git/config $'submodule.($name).active' true
        let commit = ^git -C $name rev-parse HEAD | str trim
        ^git update-index --add --cacheinfo 160000 $commit $name
    }

    # .gitignore
    [.DS_Store ...(non-git-subdirs)]
    | str join (char nl)
    | save --force .gitignore

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
