# Keep cozy's global gitignore patterns (.DS_Store, …) active on shell start.
# Self-healing: `sbx` sets core.excludesFile = ~/.gitignore_global in ~/.gitconfig
# on every sandbox create. Once excludesFile is set, git stops reading its XDG
# default (~/.config/git/ignore) where cozy wrote those patterns, so they go
# inert. git allows only one excludesFile, and ~/.gitconfig (sbx's) wins over the
# XDG config, so cozy can't reclaim it — it must augment whatever file is active.
# Mirror cozy's canonical ignore (~/.config/git/ignore, written by bootstrap.nu)
# into the resolved excludesFile, keeping sbx's own entries (`.sbx`).
# Same self-healing pattern as git-safe-directory.nu / mcp-server.nu.
# Guarded so the normal path writes nothing.
let canonical = $nu.home-dir | path join .config git ignore
let active = do { git config --get core.excludesFile } | complete
# excludesFile unset -> git already reads ~/.config/git/ignore as its default.
# Nothing to mirror. This is the plain-host path; the sbx path takes the branch.
if $active.exit_code == 0 and ($active.stdout | str trim | is-not-empty) and ($canonical | path exists) {
    let target = $active.stdout | str trim | path expand
    let have = if ($target | path exists) { open $target | lines } else { [] }
    let missing = open $canonical | lines | where {|p| $p not-in $have }
    if ($missing | is-not-empty) {
        ($missing | str join (char newline)) + (char newline) | save --append $target
    }
}
