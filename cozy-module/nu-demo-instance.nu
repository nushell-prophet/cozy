# Prepare a throwaway nushell launch for demos. Instead of spawning nu
# itself, this puts the launch line into the REPL prompt via `commandline`,
# so the user executes it — the audience sees the actual code, it lands in
# history, and it can be edited before running.
#
# The line points XDG_CONFIG_HOME and XDG_DATA_HOME at empty temp dirs, so
# nu starts bare; `with-env` scopes the change to the child, so nothing
# leaks into the calling session.
#
# With --here the config home is the current directory: nu reads
# ./nushell/{env.nu,config.nu} (XDG layout), and both files are created
# empty if missing, so they are present upon start and can be edited live.
export def main [
    --here # use ./nushell/ in the current directory as the config dir
]: nothing -> nothing {
    let config_home = if $here {
        let dir = $env.PWD | path join nushell
        mkdir $dir
        [config.nu env.nu]
        | each {|f| $dir | path join $f }
        | where not ($it | path exists)
        | each {|f| touch $f }
        '$env.PWD'
    } else {
        '(mktemp -d)'
    }

    # XDG_DATA_HOME is a temp dir, not '' because: empty XDG vars are treated
    # as unset (dirs crate falls back to ~/.local/share), which would load the
    # real vendor autoloads and write history into the real data dir.
    $"with-env { XDG_CONFIG_HOME: ($config_home), XDG_DATA_HOME: \(mktemp -d) } { nu }"
    | commandline edit --replace $in
}
