use _clone-or-fail.nu

export def main [] { help topiary }

# Install topiary formatter with nushell support.
#
# Installs the topiary binary via brew, reads the vendored topiary-nushell
# grammar/queries repo (linked at ~/git/topiary-nushell by bootstrap.nu Step 8 —
# errors if absent, never clones it), writes ~/.config/topiary/languages.ncl
# (copied, with a 4-space indent override) and symlinks queries/nu.scm, then
# clones and compiles the tree-sitter-nu grammar with gcc.
# Safe to re-run — skips the brew install and the grammar build when already done.
export def install []: nothing -> nothing {
    # 1. Install topiary binary
    if (which topiary | is-empty) {
        print "  Installing topiary via brew..."
        ^brew install topiary
    } else {
        print $"  (ansi green)topiary(ansi reset): already installed"
    }

    # 2. Locate the topiary-nushell grammar/queries repo.
    # Not a clone fallback because: the repo is vendored and bootstrap.nu Step 8
    # symlinks it here. Cloning from GitHub instead would paper over a broken
    # vendor flow and silently install an unpinned upstream revision.
    let repo_dir = $nu.home-dir | path join git topiary-nushell
    if not ($repo_dir | path exists) {
        error make {msg: $"topiary-nushell not found at ($repo_dir) — it is vendored and linked by bootstrap.nu Step 8. Re-run `cozy install bootstrap`, or on the host refresh vendor/ with `nu toolkit/vendor.nu topiary-nushell`."}
    }
    print $"  (ansi green)topiary-nushell(ansi reset): found at ($repo_dir)"

    # 3. Copy languages.ncl (with the indent override), symlink queries/nu.scm
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
        if (which gcc | is-empty) {
            match $nu.os-info.name {
                "linux" => {
                    print "  Installing gcc (needed to compile tree-sitter grammar)..."
                    ^sudo apt-get update
                    ^sudo apt-get install -y gcc libc6-dev
                }
                "macos" => {
                    error make {msg: "gcc not found — install Xcode Command Line Tools: xcode-select --install"}
                }
                $other => {
                    error make {msg: $"gcc not found and no install path for OS ($other) — install gcc manually"}
                }
            }
        }
        print "  Building tree-sitter-nu grammar..."
        let tmp = mktemp -d
        _clone-or-fail https://github.com/nushell/tree-sitter-nu.git $tmp ...[--depth 1]
        ^gcc -shared -fPIC -o ($tmp | path join parser.so) ($tmp | path join src parser.c) ($tmp | path join src scanner.c) $"-I($tmp | path join src)"
        mkdir $cache_dir
        mv ($tmp | path join parser.so) $so_path
        rm -rf $tmp
        print $"  (ansi cyan)grammar(ansi reset): built and cached"
    }

    print "  topiary nushell formatter ready"
}
