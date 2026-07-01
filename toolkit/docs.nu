# Download Docker sandbox documentation as local markdown files.
# Stored in docs.docker.com/ (its own git repo, ignored by cozy).

const base_url = "https://docs.docker.com"

# Page-path prefixes we mirror. Every page under these is synced.
const prefixes = [ai/sandboxes reference/cli/sbx]

# Discover the pages to sync from Docker's generated page index.
# Why: llms-full.txt is the full page index (llms.txt is only a curated
# top-level guide and lists sandboxes once). Parsing it means new sandbox / sbx
# pages appear automatically -- no hardcoded list to keep in sync.
def discover-pages []: nothing -> list<string> {
    # Why: http get doesn't work through Docker sandbox proxy, curl does
    let index = do { ^curl -sfL $"($base_url)/llms-full.txt" } | complete
    if $index.exit_code != 0 {
        error make {msg: $"failed to fetch llms-full.txt \(curl exit ($index.exit_code)\)"}
    }
    $index.stdout
    | lines
    | parse --regex '^Markdown:\s+(?<url>\S+\.md)\s*$'
    | get url
    | where {|u| $u | str starts-with $"($base_url)/" }
    | each {|u| $u | str replace $"($base_url)/" '' | str replace --regex '\.md$' '' }
    | where {|p| $prefixes | any {|pre| $p | str starts-with $pre } }
    | uniq
    | sort
}

# Sync Docker sandbox docs to local markdown.
# Run from the cozy/ directory.
export def main [] {
    let dir = pwd | path join docs.docker.com
    init $dir

    let pages = discover-pages
    print $"Discovered ($pages | length) pages from llms-full.txt"

    let results = $pages | par-each {|page|
            let url = $"($base_url)/($page).md"
            let file = $dir | path join $"($page).md"
            mkdir ($file | path dirname)

            # Why: http get doesn't work through Docker sandbox proxy, curl does
            let result = do { ^curl -sfL $url } | complete
            if $result.exit_code == 0 {
                $result.stdout | save -f $file
                {page: $page status: ok}
            } else {
                {page: $page status: failed}
            }
        } | sort-by page

    commit $dir

    # Why: return the summary as structured data -- a bare `print` only reaches
    # stdout, which the nushell MCP doesn't capture, so callers got an empty
    # result. The record renders in the REPL and survives through the MCP.
    {
        discovered: ($pages | length)
        ok: ($results | where status == "ok" | length)
        failed: ($results | where status == "failed" | get page)
    }
}

def init [dir: path] {
    if not ($dir | path exists) {
        mkdir $dir
        ^git init $dir o+e>| ignore
        # Why: parent workspace .gitignore starts with * (ignore all).
        # Git traverses parent .gitignore even for nested repos.
        # Override with !* so docs repo tracks everything.
        "!*\n" | save ($dir | path join .gitignore)
        print $"Initialized git repo at ($dir)"
    }

    # Ensure parent .gitignore has the entry
    let gitignore = $dir | path dirname | path join .gitignore
    let entry = "/docs.docker.com"
    let content = open $gitignore
    if $entry not-in $content {
        $"\n($entry)\n" | save -a $gitignore
        print $"Added ($entry) to .gitignore"
    }
}

def commit [dir: path] {
    ^git -C $dir add -A
    let status = ^git -C $dir status --porcelain
    if ($status | str trim | is-empty) {
        print "No changes to commit"
    } else {
        let date = date now | format date "%Y-%m-%d"
        ^git -C $dir commit -m $"docs: sync sandbox documentation ($date)"
        print "Committed"
    }
}
