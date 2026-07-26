def "nu-complete runtimes" [] {
    [
        {value: "sbx" description: "Docker standalone sandbox runtime (default)"}
        {value: "container" description: "Apple container"}
    ]
}

# Why: the completer takes `context` (the command line typed so far) because the
# name list depends on --runtime, which nushell can't otherwise pass to it.
def "nu-complete sandbox names" [context: string] {
    if ($context =~ '--runtime[=\s]+container') {
        # Why: --all so stopped containers are offered too and the state in the
        # description carries information — without it every row reads `running`.
        ^container ls --all --format json | from json
        | each {|x| {value: $x.configuration.id description: $x.status.state} }
    } else {
        ^sbx ls --json | from json | get sandboxes
        | each {|x| {value: $x.name description: $"($x.status) ($x.workspaces | str join ' ')"} }
    }
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
    --runtime: string@"nu-complete runtimes" = "sbx" # which runtime holds the sandbox
    --workdir: path # start directory inside the container (`container` only; sbx uses the workspace)
] {
    let conf = $config_file
        | default ($script_path | path dirname | path join ../vendor/dotfiles/wezterm/wezterm.lua)

    let attach = [
        nu
        --login
        --execute
        $'zellij attach --create ($zellij_session | default --empty $sandbox_name)'
    ]

    let launch = match $runtime {
        "sbx" => [sbx exec -it $sandbox_name ...$attach]
        # Why: `container` has no notion of a workspace, so it starts wherever the
        # image left WORKDIR — pass --cwd when the start directory matters.
        "container" => [
            container exec -it
            ...(if ($workdir | is-not-empty) { [--cwd $workdir] } else { [] })
            $sandbox_name ...$attach
        ]
        _ => (error make {msg: $"unknown runtime '($runtime)' — expected 'sbx' or 'container'"})
    }

    let closure = {
        # Why: set the background via --config at window creation rather than the
        # SANDBOX_MODE OSC user-var trick, which applied it only after the shell
        # started and briefly flashed the config-file default first.
        ^wezterm --config-file $conf --config $'colors={background="#($background)"}' start --always-new-process -- ...$launch
    }

    if $no_job { do $closure } else { job spawn $closure }
}
