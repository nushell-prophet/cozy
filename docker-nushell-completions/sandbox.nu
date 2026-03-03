const agents = [cagent claude codex copilot gemini kiro]

def "nu-complete sandbox names" [] {
    ^docker sandbox ls --json | from json | get vms
    | each {|x| { value: $x.name, description: $"($x.agent) ($x.status)" }}
}

def "nu-complete sandbox run-target" [] {
    let vms = ^docker sandbox ls --json | from json | get vms
        | each {|x| { value: $x.name, description: $x.status }}
    let new = $agents | each {|a| { value: $a, description: "new" }}
    $new | append $vms
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
