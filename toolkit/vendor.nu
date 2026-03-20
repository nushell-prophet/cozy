# Refresh vendored modules and configs from local ~/repos/ repos into vendor/
# Run before `docker build` to update vendored copies.

const modules = [
    [repo module];
    [cozy-docker-sandbox-toolkit .]
    [nu-goodies nu-goodies]
    [nu-kv kv]
    [dotnu dotnu]
    [numd numd]
    [claude-nu claude-nu]
    [nu-cmd-stack cmd-stack]
    [nutest nutest]
    [dotfiles broot]
    [dotfiles claude]
    [dotfiles helix]
    [dotfiles jj]
    [dotfiles lazygit]
    [dotfiles nushell]
    [dotfiles zellij]
    [dotfiles toolkit.nu]
    [dotfiles paths-docker.csv]
    [dotfiles config-gitignore]
    [dotfiles claude-gitignore]
]

export def main [] {
    let vendor_dir = pwd | path join vendor
    let git_dir = pwd | path join '..'

    # Clean and recreate vendor dir
    rm -rf $vendor_dir
    mkdir $vendor_dir

    for $m in $modules {
        let src = $git_dir | path join $m.repo $m.module
        let dst = $vendor_dir | path join $m.repo $m.module

        if not ($src | path exists) {
            print $"(ansi red)Missing:(ansi reset) ($src)"
            continue
        }

        if ($src | path type) == 'file' {
            mkdir ($dst | path dirname)
            cp $src $dst
        } else {
            mkdir $dst
            ^rsync -a --exclude='.git' --exclude='.DS_Store' --exclude='lazytests' --exclude='md_backups' --exclude='zzz_md_backups' $"($src)/" $"($dst)/"
        }
        print $"(ansi green)Copied:(ansi reset) ($m.repo)/($m.module)"
    }
}
