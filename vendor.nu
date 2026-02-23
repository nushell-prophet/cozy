# Refresh vendored modules and configs from local ~/git/ repos into vendor/
# Run before `docker build` to update vendored copies.

let docker_dir = $env.FILE_PWD
let vendor_dir = $docker_dir | path join vendor
let git_dir = $nu.home-dir | path join git

let modules = [
    [repo module];
    [nu-goodies nu-goodies]
    [nushell-kv kv]
    [dotnu dotnu]
    [numd numd]
    [claude-nu claude-nu]
    [nu-cmd-stack cmd-stack]
    [dotfiles wezterm]
]

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

    mkdir ($vendor_dir | path join $m.repo)
    ^rsync -a --exclude='.git' --exclude='.DS_Store' --exclude='lazytests' --exclude='md_backups' --exclude='zzz_md_backups' $"($src)/" $"($dst)/"
    print $"(ansi green)Copied:(ansi reset) ($m.repo)/($m.module)"
}
