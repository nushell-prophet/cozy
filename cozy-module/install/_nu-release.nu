use _install-binary.nu

# Puts one binary from a nushell release tarball at $dest.
#
# Every release tarball carries `nu` and the bundled plugins (polars among
# them), so one download path serves `cozy install nushell --github` and
# `cozy install polars --github`.
export def main [
    version: string # Release tag, like 0.116.0
    member: string # Binary inside the tarball, like nu or nu_plugin_polars
    dest: path
]: nothing -> nothing {
    let os = match $nu.os-info.name {
        linux => 'unknown-linux-gnu'
        macos => 'apple-darwin'
        $other => { error make {msg: $"no nushell release build for OS ($other)"} }
    }
    let target = $"($nu.os-info.arch)-($os)"
    let archive = $"nu-($version)-($target)"
    let url = $"https://github.com/nushell/nushell/releases/download/($version)/($archive).tar.gz"

    print $"  Downloading ($member) ($version) from ($url)..."
    let response = http get --raw --full --allow-errors $url

    if $response.status != 200 {
        error make {
            msg: $"no nushell release asset for ($version) on ($target): HTTP ($response.status)"
            help: "a dev build has no release, and a fresh release may still be uploading its assets; build from source instead (drop --github)"
        }
    }

    let tmp = mktemp --directory

    $response.body | save ($tmp | path join archive.tar.gz)
    ^tar --extract --gzip --file ($tmp | path join archive.tar.gz) --directory $tmp $"($archive)/($member)"
    mkdir ($dest | path dirname)
    _install-binary ($tmp | path join $archive $member) $dest
    rm --recursive $tmp
}
