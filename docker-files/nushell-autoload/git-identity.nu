# Restore the human's own git identity on shell start, from the COZY_GIT_USER_*
# variables `toolkit/container-up.nu` forwards from the host's `git config --global`.
#
# Three layers, each narrower than the last, so every commit is attributed to
# whoever actually made it:
#   ~/.config/git/config  Agent <agent@sandbox>  — placeholder, lets build-time commits work
#   ~/.gitconfig          the human              — written here, overrides the XDG file
#   GIT_AUTHOR_* env      Claude                 — set for the agent's shell only, overrides both
#
# Why here and not bootstrap.nu: these variables arrive at container run time,
# long after the image was built.
# Why `git config` and not writing the file: sbx puts core.excludesFile in the
# same ~/.gitconfig, and a key edit leaves it alone.
# Not --global because: it does not mean ~/.gitconfig. git writes there only if
# that file already exists; otherwise it writes $XDG_CONFIG_HOME/git/config when
# that one does — which is exactly cozy's layout, so --global would overwrite the
# `Agent <agent@sandbox>` placeholder in the bottom layer instead of adding the
# middle one. --file names the target and holds on both paths (sbx creates
# ~/.gitconfig, the Debian image does not).
# Guarded so the normal path writes nothing — same as git-safe-directory.nu.
let gitconfig = $nu.home-dir | path join '.gitconfig'
{
    'user.name': ($env.COZY_GIT_USER_NAME? | default '')
    'user.email': ($env.COZY_GIT_USER_EMAIL? | default '')
}
| items {|key value|
    if ($value | is-not-empty) {
        let current = do { git config --file $gitconfig --get $key } | complete | get stdout | str trim
        if $current != $value {
            git config --file $gitconfig $key $value
        }
    }
}
| ignore
