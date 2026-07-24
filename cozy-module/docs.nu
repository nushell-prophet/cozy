# Fetch reference docs into local folders for offline / in-sandbox agent use.
#
# Fetches with curl, not `http get`: `http get` doesn't work through the Docker
# sandbox proxy, curl does (same constraint as `toolkit docs`, which mirrors the
# Docker sandbox docs). Each command returns a structured summary so the nushell
# MCP captures the result — a bare `print` only reaches stdout, which the MCP
# drops. Output dirs are gitignored generated content, refetch anytime.

const CLAUDE_DOCS_DIR = 'claude-code-docs'
const NUSHELL_DOCS_DIR = 'nushell-docs'
const NUSHELL_DOCS_REPO = 'https://github.com/nushell/nushell.github.io.git'
const NUSHELL_DOCS_FOLDERS = ['blog' 'book' 'cookbook']

export def main [] { }

# Download Claude Code documentation pages listed in the sitemap, in parallel.
@example "Fetch Claude Code docs" { cozy docs claude }
export def claude [
    --output-dir: path = $CLAUDE_DOCS_DIR # Where to write the .md pages
]: nothing -> record {
    let sitemap = do { ^curl -sfL https://code.claude.com/docs/sitemap.xml } | complete
    if $sitemap.exit_code != 0 {
        error make {msg: $"failed to fetch sitemap.xml \(curl exit ($sitemap.exit_code)\)"}
    }

    let urls = $sitemap.stdout
        | from xml
        | get content.content
        | each { get content.0.content.0 }
        | where $it =~ 'docs/en/'
        | each { $in + '.md' }

    mkdir $output_dir

    let results = $urls | par-each --threads 4 {|url|
        let filename = $url | path split | skip 4 | str join '_'
        let dest = [$output_dir $filename] | path join
        let r = do { ^curl -sfL $url } | complete
        if $r.exit_code == 0 {
            $r.stdout | save -f $dest
            {url: $url status: ok}
        } else {
            {url: $url status: failed}
        }
    } | sort-by url

    let failed = $results | where status == failed | get url
    {
        dir: $output_dir
        ok: ($results | where status == ok | length)
        failed: $failed
    }
}

# Fetch Nushell docs (book, cookbook, blog) via a shallow sparse checkout.
# Re-run to update: pulls the existing checkout, or clones it fresh.
@example "Fetch/update Nushell docs" { cozy docs nushell }
export def nushell [
    --output-dir: path = $NUSHELL_DOCS_DIR # Where to place the sparse checkout
]: nothing -> record {
    if ($output_dir | path exists) {
        ^git -C $output_dir pull
    } else {
        ^git clone --depth 1 --filter=blob:none --sparse $NUSHELL_DOCS_REPO $output_dir
        ^git -C $output_dir sparse-checkout set --no-cone ...($NUSHELL_DOCS_FOLDERS | each { $'/($in)/*' })
    }

    let folders = $NUSHELL_DOCS_FOLDERS | each {|f|
        {folder: $f size: (du ($output_dir | path join $f) | get apparent | first)}
    }
    {dir: $output_dir folders: $folders}
}
