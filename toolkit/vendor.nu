# Refresh vendored modules and configs into vendor/
# Run before `docker build` to update vendored copies.
#
# Default: download tarballs from GitHub (no git clone, no auth needed)
# --local: use local ~/repos/ directories (original rsync behavior)

const modules = [
    [repo github module];
    [nu-goodies nushell-prophet/nu-goodies nu-goodies]
    [nu-kv nushell-prophet/nu-kv kv]
    [dotnu nushell-prophet/dotnu dotnu]
    [numd nushell-prophet/numd numd]
    [claude-nu nushell-prophet/claude-nu claude-nu]
    [nu-cmd-stack nushell-prophet/nu-cmd-stack cmd-stack]
    [nutest vyadh/nutest nutest]
    [topiary-nushell blindFS/topiary-nushell languages.ncl]
    [topiary-nushell blindFS/topiary-nushell queries]
    [topiary-nushell blindFS/topiary-nushell LICENSE]
    [dotfiles nushell-prophet/my-dotfiles broot]
    [dotfiles nushell-prophet/my-dotfiles claude]
    [dotfiles nushell-prophet/my-dotfiles helix]
    [dotfiles nushell-prophet/my-dotfiles jj]
    [dotfiles nushell-prophet/my-dotfiles lazygit]
    [dotfiles nushell-prophet/my-dotfiles nushell]
    [dotfiles nushell-prophet/my-dotfiles zellij]
    [dotfiles nushell-prophet/my-dotfiles wezterm]
    [dotfiles nushell-prophet/my-dotfiles toolkit.nu]
    [dotfiles nushell-prophet/my-dotfiles paths-docker.csv]
    [my-claude-skills maxim-uvarov/my-claude-skills plugins/my-skills/skills]
    [nushell-skills nushell-prophet/nushell-skills plugins]
]

# Group modules by repo to avoid downloading the same tarball multiple times
def group-by-repo []: list<record<repo: string, github: string, module: string>> -> list<record<repo: string, github: string, modules: list<string>>> {
    $in
    | group-by repo
    | items {|repo rows|
        {
            repo: $repo
            github: ($rows.0.github)
            modules: ($rows | get module)
        }
    }
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
        ^rsync -a --prune-empty-dirs
            --exclude='.git' --exclude='.DS_Store' --exclude='lazytests'
            $"($src)/" $"($dst)/"
    }
}

export def main [--local (-l)] {
    let vendor_dir = pwd | path join vendor

    rm -rf $vendor_dir
    mkdir $vendor_dir

    if $local {
        let git_dir = pwd | path join '..'
        for $m in $modules {
            let src = $git_dir | path join $m.repo $m.module
            let dst = $vendor_dir | path join $m.repo $m.module
            copy-module $src $dst
            print $"  (ansi green)Copied:(ansi reset) ($m.repo)/($m.module)"
        }
    } else {
        for $group in ($modules | group-by-repo) {
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
