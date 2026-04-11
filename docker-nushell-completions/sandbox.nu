const agents = [cagent claude codex copilot gemini kiro shell]

def "nu-complete sandbox names" [] {
    ^docker sandbox ls
    | detect columns --guess # --json gives status that all machines are running
    | each {|x| { value: $x.SANDBOX, description: $"($x.STATUS) ($x.WORKSPACE)" }}
}

def "nu-complete sandbox run-target" [] {
    let vms = ^docker sandbox ls --json | from json | get vms
        | each {|x| { value: $x.name, description: $x.status }}
    let new = $agents | each {|a| { value: $a, description: "new" }}
    $new | append $vms
}

const script_path = path self

export def wezterm-cozy [
    sandbox_name: string@"nu-complete sandbox names"
    --config-file: path
] {
    let conf = $config_file
    | default ($script_path | path dirname | path join ../vendor/dotfiles/wezterm/wezterm.lua)

    ^wezterm --config-file $conf start --always-new-process -- ...[
        docker sandbox exec -it $sandbox_name
        nu --login --commands $'
            print -n $"\e]1337;SetUserVar=SANDBOX_MODE=b24=\e\\";
            zellij attach -c ($sandbox_name)
        '
    ]
}

export extern "docker sandbox" [
    --debug(-D)
]

export extern "docker sandbox create" [
    agent: string@$agents
    workspace?: path
    --debug(-D)
    --load-local-template
    --name: string
    --quiet(-q)
    --template(-t): string
]

export extern "docker sandbox run" [
    target: string@"nu-complete sandbox run-target"
    workspace?: path
    --debug(-D)
    --load-local-template
    --name: string
    --template(-t): string
]

export extern "docker sandbox exec" [
    sandbox: string@"nu-complete sandbox names"
    ...args: string
    --debug(-D)
    --detach(-d)
    --detach-keys: string
    --env(-e): string
    --env-file: string
    --interactive(-i)
    --privileged
    --tty(-t)
    --user(-u): string
    --workdir(-w): string
]

export extern "docker sandbox ls" [
    --debug(-D)
    --json
    --no-trunc
    --quiet(-q)
]

export extern "docker sandbox stop" [
    ...sandbox: string@"nu-complete sandbox names"
    --debug(-D)
]

export extern "docker sandbox rm" [
    ...sandbox: string@"nu-complete sandbox names"
    --debug(-D)
]

export extern "docker sandbox save" [
    sandbox: string@"nu-complete sandbox names"
    tag: string
    --debug(-D)
    --output(-o): path
]

export extern "docker sandbox reset" [
    --debug(-D)
    --force(-f)
]

export extern "docker sandbox network" [
    --debug(-D)
]

export extern "docker sandbox network proxy" [
    sandbox: string@"nu-complete sandbox names"
    --allow-cidr: string
    --allow-host: string
    --block-cidr: string
    --block-host: string
    --bypass-cidr: string
    --bypass-host: string
    --debug(-D)
    --policy: string@[allow deny]
]

export extern "docker sandbox network log" [
    --debug(-D)
    --json
    --limit: int
    --quiet(-q)
]

export extern "docker sandbox version" [
    --debug(-D)
]
