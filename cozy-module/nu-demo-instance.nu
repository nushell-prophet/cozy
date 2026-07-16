# Launch a throwaway nushell for demos. By default the config home is an
# empty temp dir, so nu starts bare; `with-env` scopes the XDG change to the
# child, so nothing leaks into the calling session.
#
# With --here the config home is the current directory: nu reads
# ./nushell/{env.nu,config.nu} (XDG layout), and both files are created empty
# if missing, so they are present upon start and can be edited live in a demo.
#
# Extra args pass through to nu (e.g. `cozy nu-demo-instance -c '...'`).
export def --wrapped main [
    --here # use ./nushell/ in the current directory as the config dir
    ...args: string
]: nothing -> nothing {
    let config_home = if $here {
        let dir = $env.PWD | path join nushell
        mkdir $dir
        [config.nu env.nu]
        | each {|f| $dir | path join $f }
        | where not ($it | path exists)
        | each {|f| touch $f }
        $env.PWD
    } else {
        mktemp -d
    }

    with-env {
        XDG_CONFIG_HOME: $config_home
        # Not '' because: empty XDG vars are treated as unset (dirs crate
        # falls back to ~/.local/share), which would load the real vendor
        # autoloads and write history into the real data dir.
        XDG_DATA_HOME: (mktemp -d)
    } { nu ...$args }
}
