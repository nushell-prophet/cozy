# Repo → clone URL list, read from the generated manifest derived from
# toolkit/vendor.yml (the single source of truth for what cozy vendors).
# vendored-repos.nuon ships next to this file under ~/repos/cozy/cozy-module/
# (cozy-module is COPYed into the image), so this in-sandbox command resolves
# it via `path self` — the host-only toolkit/vendor.yml is not reachable here.
const manifest = path self | path dirname | path join vendored-repos.nuon

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
    open $manifest
    | each {|row|
        let name = $row.name
        let url = $row.url
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
