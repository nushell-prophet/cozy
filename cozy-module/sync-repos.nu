const repos = {
    claude-nu: "https://github.com/nushell-prophet/claude-nu.git"
    cozy: "https://github.com/nushell-prophet/cozy.git"
    dotnu: "https://github.com/nushell-prophet/dotnu.git"
    nu-cmd-stack: "https://github.com/nushell-prophet/nu-cmd-stack.git"
    nu-goodies: "https://github.com/nushell-prophet/nu-goodies.git"
    numd: "https://github.com/nushell-prophet/numd.git"
    nu-kv: "https://github.com/nushell-prophet/nu-kv.git"
    nu-multiproof: "https://github.com/nushell-prophet/nu-multiproof.git"
    topiary-nushell: "https://github.com/blindFS/topiary-nushell.git"
    dotfiles: "https://github.com/nushell-prophet/my-dotfiles.git"
    nutest: "https://github.com/vyadh/nutest.git"
    nushell-skills: "https://github.com/nushell-prophet/nushell-skills.git"
    my-claude-skills: "https://github.com/maxim-uvarov/my-claude-skills.git"
}

const base = $nu.home-dir | path join repos

def remote-head-branch []: nothing -> string {
    ^git remote show origin
    | lines
    | where { $in =~ 'HEAD branch:' }
    | first
    | str replace -r '.*HEAD branch:\s*' ''
}

# Convert vendor directories to git repos if needed, pull latest from all
export def main [--force (-f)] {
    $repos
    | items {|name url|
        let dir = $base | path join $name

        # Why: `cozy dev-link` replaces ~/repos/<name> with a symlink into the
        # mounted workspace. The destructive git ops below (clean -fd, reset
        # --hard, checkout -f) would then follow that symlink and run inside the
        # user's live host repo. Refuse to touch dev-linked repos — they're the
        # user's working tree, not a vendored copy for sync-repos to reset.
        if ($dir | path type) == 'symlink' {
            print $"  (ansi yellow)($name)(ansi reset): dev-linked, skipping \(managed in workspace, not by sync-repos)"
            return
        }

        mkdir $dir

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
