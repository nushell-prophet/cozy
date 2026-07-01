# Download Docker sandbox documentation as local markdown files.
# Stored in docs.docker.com/ (its own git repo, ignored by cozy).

const base_url = "https://docs.docker.com"

const pages = [
    # Sandbox docs
    ai/sandboxes/get-started
    ai/sandboxes/usage
    ai/sandboxes/agents
    ai/sandboxes/customize
    ai/sandboxes/customize/templates
    ai/sandboxes/customize/kits
    ai/sandboxes/customize/build-an-agent
    ai/sandboxes/architecture
    ai/sandboxes/security
    ai/sandboxes/governance
    ai/sandboxes/governance/org
    ai/sandboxes/workflows
    ai/sandboxes/troubleshooting
    ai/sandboxes/faq
    # CLI reference (sbx)
    reference/cli/sbx
    reference/cli/sbx/create
    reference/cli/sbx/run
    reference/cli/sbx/exec
    reference/cli/sbx/cp
    reference/cli/sbx/ls
    reference/cli/sbx/stop
    reference/cli/sbx/rm
    reference/cli/sbx/reset
    reference/cli/sbx/login
    reference/cli/sbx/logout
    reference/cli/sbx/secret
    reference/cli/sbx/secret/set
    reference/cli/sbx/secret/ls
    reference/cli/sbx/secret/rm
    reference/cli/sbx/policy
    reference/cli/sbx/policy/allow
    reference/cli/sbx/policy/ls
    reference/cli/sbx/version
]

# Sync Docker sandbox docs to local markdown.
# Run from the cozy/ directory.
export def main [] {
    let dir = pwd | path join docs.docker.com
    init $dir

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

    let ok = $results | where status == "ok" | length
    let failed = $results | where status == "failed"
    print $"Downloaded ($ok)/($results | length) pages"
    if ($failed | is-not-empty) {
        print "Failed:"
        print ($failed | get page | to text)
    }

    commit $dir
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
