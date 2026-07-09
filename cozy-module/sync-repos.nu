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

# Turn vendored snapshots into full git clones, then keep already-cloned repos
# current — non-destructively. These become the user's repos to develop in and
# PR upstream from, so a re-run never discards local work: no clean, no reset,
# no branch switch. First run converts a throwaway snapshot; later runs only
# fetch and fast-forward when it is safe.
export def main [] {
    open $manifest
    | each {|row|
        let name = $row.name
        let url = $row.url
        let dir = $base | path join $name

        # Why: `cozy dev-link` replaces ~/repos/<name> with a symlink into the
        # mounted workspace. Git ops here would then follow that symlink and run
        # inside the user's live host repo. Refuse to touch dev-linked repos —
        # they're the user's working tree, managed in the workspace, not by
        # sync-repos.
        if ($dir | path type) == 'symlink' {
            print $"  (ansi yellow)($name)(ansi reset): dev-linked, skipping \(managed in workspace, not by sync-repos)"
            return
        }

        mkdir $dir

        if ($dir | path join '.git' | path exists) {
            cd $dir
            # Non-destructive update: this is the user's repo to develop in and
            # PR from. Fetch always (so upstream refs stay current for them to
            # rebase/merge themselves), then fast-forward only when the tree is
            # clean and the branch's upstream hasn't diverged. Anything else is
            # left exactly as they left it — never clean/reset/switch branches.
            # Not `pull --ff-only` because that re-fetches; merge reuses the fetch.
            try { ^git fetch origin } catch {
                print $"  (ansi yellow)($name)(ansi reset): cannot reach remote, skipping"
                return
            }
            if (^git status --porcelain | str trim) != '' {
                print $"  (ansi yellow)($name)(ansi reset): local changes — fetched, not fast-forwarding"
                return
            }
            try {
                ^git merge --ff-only '@{upstream}'
                print $"  (ansi green)($name)(ansi reset): up to date / fast-forwarded"
            } catch {
                # No upstream set, or diverged from it — the user's call to
                # resolve. We already fetched; don't touch the working tree.
                print $"  (ansi yellow)($name)(ansi reset): diverged or no upstream — fetched only, resolve manually"
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
