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
export def "main sync-repos" [] {
    let base = $nu.home-dir | path join git

    $repos | items {|name url|
        let dir = $base | path join $name
        if not ($dir | path exists) {
            print $"  (ansi yellow)($name)(ansi reset): not found, skipping"
            return
        }

        if ($dir | path join '.git' | path exists) {
            print $"  (ansi green)($name)(ansi reset): pulling"
            cd $dir; ^git pull --ff-only
        } else {
            print $"  (ansi cyan)($name)(ansi reset): init + fetch"
            cd $dir
            ^git init -b main
            ^git remote add origin $url
            ^git fetch origin
            ^git reset --hard origin/main
            ^git branch -u origin/main
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
    let ignored = non-git-subdirs
    let had_git = ('.git' | path exists)

    if not $had_git { ^git init }

    # .gitignore — regenerated from current state
    [.DS_Store ...$ignored]
    | str join (char nl)
    | save -f .gitignore

    if ($repos | is-not-empty) {
        # .gitmodules — regenerated
        $repos
        | each {|name|
            $'[submodule "($name)"]
	path = ($name)
	url = ./($name)'
        }
        | str join (char nl)
        | save -f .gitmodules

        # register each submodule
        for name in $repos {
            ^git config -f .git/config $'submodule.($name).url' $'./($name)'
            ^git config -f .git/config $'submodule.($name).active' true
            let commit = ^git -C $name rev-parse HEAD | str trim
            ^git update-index --add --cacheinfo $'160000,($commit),($name)'
        }

        ^git add .gitmodules
    }

    ^git add .gitignore
    glob *.md | each { ^git add $in }

    let staged = ^git diff --cached --name-only | str trim
    if ($staged | is-not-empty) {
        let msg = if $had_git { 'Update workspace' } else { 'Init workspace' }
        ^git commit -m $msg
        print $"($msg): ($repos | length) submodules, ($ignored | length) ignored dirs"
    } else {
        print "Workspace up to date"
    }
}
