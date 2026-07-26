# Open a new WezTerm window and attach it to a zellij session inside a sandbox.
#
# The only thing that differs between the two run paths is how you get a shell
# inside — `sbx exec -it NAME` vs `container exec -it [--cwd W] NAME` — so the
# caller passes that prefix and everything else lives here once. Used by
# toolkit/sbxw.nu (sbx) and toolkit/container.nu (Apple `container`).
#
# Named for the window, not the job: nushell refuses to export a command named
# like its own module, and `attach-window` is the name worth keeping at the
# call sites.

const script_path = path self

export def "nu-complete wezterm background" [] {
    [
        {value: "000000" description: "black (sandbox default)"}
        {value: "0d0d0d" description: "near-black"}
        {value: "0a0e27" description: "deep navy (host default)"}
    ]
}

export def attach-window [
    exec_argv: list<string> # how to get a shell inside, e.g. [sbx exec -it my-box]
    session: string # zellij session to attach to, created if missing
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create a background job for the process
] {
    let conf = $config_file
        | default ($script_path | path dirname | path join ../vendor/dotfiles/wezterm/wezterm.lua)

    let launch = $exec_argv ++ [nu --login --execute $'zellij attach --create ($session)']

    let closure = {
        # Why: set the background via --config at window creation rather than the
        # SANDBOX_MODE OSC user-var trick, which applied it only after the shell
        # started and briefly flashed the config-file default first.
        ^wezterm --config-file $conf --config $'colors={background="#($background)"}' start --always-new-process -- ...$launch
    }

    if $no_job { do $closure } else { job spawn $closure }
}
