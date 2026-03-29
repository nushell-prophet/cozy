# Refresh vendored modules and configs into vendor/
# Run before `docker build` to update vendored copies.
#
# Default: download tarballs from GitHub (no git clone, no auth needed)
# --local: use local ~/repos/ directories (original rsync behavior)

const vendor_yml = (path self | path dirname | path join vendor.yml)

def load-modules []: nothing -> list<record<repo: string, github: string, modules: list<string>>> {
    open $vendor_yml
}

def fetch-tarball [github: string]: nothing -> path {
    let tmp = mktemp -d
    let url = $"https://api.github.com/repos/($github)/tarball"
    print $"  (ansi cyan)Downloading:(ansi reset) ($github)"
    curl -sL $url | tar xz -C $tmp --strip-components=1
    $tmp
}

def copy-module [src: path, dst: path] {
    if not ($src | path exists) {
        print $"  (ansi red)Missing:(ansi reset) ($src)"
        return
    }
    if ($src | path type) == 'file' {
        mkdir ($dst | path dirname)
        cp $src $dst
    } else {
        mkdir $dst
        ^rsync -a --prune-empty-dirs --exclude='.git' --exclude='.DS_Store' --exclude='lazytests' $"($src)/" $"($dst)/"
    }
}

const ignore_repos = [
    .github
    config-tools
    cozy
    cozy-docker-sandbox-toolkit
    my-dot-claude
    my-dotfiles
    npshow-module
    nushell-history-based-completions
    nushell-prophet-journal
    nushell-prophet-manuals
    nushell-show
]

# Check for nushell-prophet repos not yet in vendor.yml
export def "main check" [--add (-a)] {
    let known = load-modules
        | where github starts-with 'nushell-prophet/'
        | get github
        | each { $in | split row '/' | last }

    let remote = curl -s "https://api.github.com/users/nushell-prophet/repos?per_page=100"
        | from json
        | get name

    let new = $remote
        | where {|r| $r not-in $known and $r not-in $ignore_repos }

    if ($new | is-empty) {
        print "No new nushell-prophet repos found."
        return
    }

    print $"New repos not in vendor.yml:"
    $new | each { print $"  ($in)" }

    if $add {
        let entries = $new | each {|name|
            { repo: $name, github: $"nushell-prophet/($name)", modules: [$name] }
        }
        let current = load-modules
        $current | append $entries | to yaml | save -f $vendor_yml
        print $"\nAdded ($new | length) repo\(s\) to vendor.yml with default modules."
    } else {
        print $"\nUse --add to append them to vendor.yml with default modules."
    }
}

export def main [--local (-l)] {
    let vendor_dir = pwd | path join vendor

    rm -rf $vendor_dir
    mkdir $vendor_dir

    let groups = load-modules

    if $local {
        let git_dir = pwd | path join '..'
        for $group in $groups {
            for module in $group.modules {
                let src = $git_dir | path join $group.repo $module
                let dst = $vendor_dir | path join $group.repo $module
                copy-module $src $dst
                print $"  (ansi green)Copied:(ansi reset) ($group.repo)/($module)"
            }
        }
    } else {
        for $group in $groups {
            let tmp = fetch-tarball $group.github
            for module in $group.modules {
                let src = $tmp | path join $module
                let dst = $vendor_dir | path join $group.repo $module
                copy-module $src $dst
                print $"  (ansi green)Vendored:(ansi reset) ($group.repo)/($module)"
            }
            rm -rf $tmp
        }
    }
}
