const topiary_nushell_url = "https://github.com/blindFS/topiary-nushell.git"

export def main [] { help topiary }

# Install topiary formatter with nushell support.
#
# Installs the topiary binary via brew, clones the topiary-nushell
# grammar/queries repo, and symlinks config into ~/.config/topiary/.
# Safe to re-run — skips steps already done.
export def install []: nothing -> nothing {
    # 1. Install topiary binary
    if (which topiary | is-empty) {
        print "  Installing topiary via brew..."
        ^brew install topiary
    } else {
        print $"  (ansi green)topiary(ansi reset): already installed"
    }

    # 2. Clone topiary-nushell repo
    let repo_dir = $nu.home-dir | path join git topiary-nushell
    if not ($repo_dir | path exists) {
        print "  Cloning topiary-nushell..."
        ^git clone $topiary_nushell_url $repo_dir
    } else {
        print $"  (ansi green)topiary-nushell(ansi reset): already cloned"
    }

    # 3. Symlink config files
    let config_dir = $nu.home-dir | path join .config topiary
    mkdir $config_dir
    mkdir ($config_dir | path join queries)

    # Copy languages.ncl and override indent to 4 spaces
    let lang_ncl = $config_dir | path join languages.ncl
    let lang_src = [$repo_dir languages.ncl] | path join
    if ($lang_ncl | path exists) {
        print $"  (ansi green)languages.ncl(ansi reset): exists"
    } else {
        open --raw $lang_src
            | str replace --regex '(grammar\.source\.git\s*=\s*\{[^}]*\},)' '$1
      indent = "    "'
            | save -f $lang_ncl
        print $"  (ansi cyan)languages.ncl(ansi reset): copied with indent override"
    }

    # Symlink query file
    let scm_link = $config_dir | path join queries nu.scm
    let scm_target = [$repo_dir queries nu.scm] | path join
    if ($scm_link | path type) == "symlink" {
        print $"  (ansi green)queries/nu.scm(ansi reset): symlink exists"
    } else {
        rm -f $scm_link
        ^ln -s $scm_target $scm_link
        print $"  (ansi cyan)queries/nu.scm(ansi reset): symlinked"
    }

    # 4. Build tree-sitter grammar for topiary cache.
    #    topiary prefetch uses its own HTTP client which may fail behind proxies,
    #    so we clone via git and compile the .so ourselves.
    let rev = open ($repo_dir | path join languages.ncl)
        | parse --regex 'rev\s*=\s*"(?P<rev>[0-9a-f]+)"'
        | get rev.0
    let cache_dir = $nu.home-dir | path join .cache topiary nu
    let so_path = $cache_dir | path join $"($rev).so"
    if ($so_path | path exists) {
        print $"  (ansi green)grammar(ansi reset): cached"
    } else {
        print "  Building tree-sitter-nu grammar..."
        let tmp = mktemp -d
        ^git clone --depth 1 https://github.com/nushell/tree-sitter-nu.git $tmp
        ^gcc -shared -fPIC -o ($tmp | path join parser.so) ($tmp | path join src parser.c) ($tmp | path join src scanner.c) $"-I($tmp | path join src)"
        mkdir $cache_dir
        mv ($tmp | path join parser.so) $so_path
        rm -rf $tmp
        print $"  (ansi cyan)grammar(ansi reset): built and cached"
    }

    print "  topiary nushell formatter ready"
}
