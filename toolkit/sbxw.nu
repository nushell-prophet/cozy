def "nu-complete sandbox names" [] {
    ^sbx ls --json | from json | get sandboxes
    | each {|x| {value: $x.name description: $"($x.status) ($x.workspaces | str join ' ')"} }
}

const script_path = path self

def "nu-complete wezterm background" [] {
    [
        {value: "000000" description: "black (sandbox default)"}
        {value: "0d0d0d" description: "near-black"}
        {value: "0a0e27" description: "deep navy (host default)"}
    ]
}

# Open a sandbox in a new WezTerm window and attach to its zellij session
export def main [
    sandbox_name: string@"nu-complete sandbox names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
    --zellij-session: string = '' # zellij session name to use instead of sandbox name
] {
    let conf = $config_file
        | default ($script_path | path dirname | path join ../vendor/dotfiles/wezterm/wezterm.lua)

    let closure = {
        # Why: set the background via --config at window creation rather than the
        # SANDBOX_MODE OSC user-var trick, which applied it only after the shell
        # started and briefly flashed the config-file default first.
        ^wezterm --config-file $conf --config $'colors={background="#($background)"}' start --always-new-process -- ...[
            sbx
            exec
            -it
            $sandbox_name
            nu
            --login
            --execute
            $'zellij attach --create ($zellij_session | default --empty $sandbox_name)'
        ]
    }

    if $no_job { do $closure } else { job spawn $closure }
}
