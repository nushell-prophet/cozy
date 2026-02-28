const repos = {
    ai-sandbox-toolkit: "https://github.com/nushell-prophet/ai-sandbox-toolkit.git"
    nu-goodies: "https://github.com/nushell-prophet/nu-goodies.git"
    nushell-kv: "https://github.com/nushell-prophet/nu-kv.git"
    dotnu: "https://github.com/nushell-prophet/dotnu.git"
    numd: "https://github.com/nushell-prophet/numd.git"
    claude-nu: "https://github.com/nushell-prophet/claude-nu.git"
    nu-cmd-stack: "https://github.com/nushell-prophet/nu-cmd-stack.git"
    topiary-nushell: "https://github.com/blindFS/topiary-nushell.git"
}

def remote-head-branch []: nothing -> string {
    ^git remote show origin
    | lines
    | where { $in =~ 'HEAD branch:' }
    | first
    | str replace -r '.*HEAD branch:\s*' ''
}

# Convert vendor directories to git repos if needed, pull latest from all
export def main [--force (-f)] {
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
