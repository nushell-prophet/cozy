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
