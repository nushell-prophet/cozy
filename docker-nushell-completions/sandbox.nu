const agents = [cagent claude codex copilot gemini kiro shell]

def "nu-complete sandbox names" [] {
    ^sbx ls # we don't use --json because it reports wrong status
    | detect columns --guess
    | each {|x| {value: $x.SANDBOX description: $"($x.STATUS) ($x.WORKSPACE)"} }
}

def "nu-complete sandbox run-target" [] {
    ^sbx ls --json | from json | get sandboxes | each {|x| {value: $x.name description: ($x.status | $x.workspaces | str join ' ')} }
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
export def wezterm-cozy [
    sandbox_name: string@"nu-complete sandbox names"
    --config-file: path
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create background job for the proces
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
            $'zellij attach -c ($sandbox_name)'
        ]
    }

    if $no_job { do $closure } else { job spawn $closure }
}

# Docker Sandbox -- local sandbox environments for AI agents
export extern "docker sandbox" [
    --debug (-D) # Enable debug logging
]

# Create a sandbox for an agent
export extern "docker sandbox create" [
    agent: string@$agents
    workspace?: path
    --debug (-D) # Enable debug logging
    --name: string # Name for the sandbox (default: <agent>-<workdir>)
    --pull-template: string@[always missing never] # Template image pull policy: always (always pull from registry), missing (pull only if not cached), never (use only cached images)
    --quiet (-q) # Suppress verbose output
    --template (-t): string # Container image to use for the sandbox (default: agent-specific image)
]

# Run an agent in a sandbox
export extern "docker sandbox run" [
    target: string@"nu-complete sandbox run-target"
    workspace?: path
    --debug (-D) # Enable debug logging
    --name: string # Name for the sandbox (default: <agent>-<workdir>)
    --pull-template: string@[always missing never] # Template image pull policy: always (always pull from registry), missing (pull only if not cached), never (use only cached images)
    --template (-t): string # Container image to use for the sandbox (default: agent-specific image)
]

# Execute a command inside a sandbox
export extern "docker sandbox exec" [
    sandbox: string@"nu-complete sandbox names"
    ...args: string
    --debug (-D) # Enable debug logging
    --detach (-d) # Detached mode: run command in the background
    --detach-keys: string # Override the key sequence for detaching a container
    --env (-e): string # Set environment variables
    --env-file: string # Read in a file of environment variables
    --interactive (-i) # Keep STDIN open even if not attached
    --privileged # Give extended privileges to the command
    --tty (-t) # Allocate a pseudo-TTY
    --user (-u): string # Username or UID (format: <name|uid>[:<group|gid>])
    --workdir (-w): string # Working directory inside the container
]

# List VMs
export extern "docker sandbox ls" [
    --debug (-D) # Enable debug logging
    --json # Output in JSON format
    --quiet (-q) # Only display VM names
]

# Stop one or more sandboxes without removing them
export extern "docker sandbox stop" [
    ...sandbox: string@"nu-complete sandbox names"
    --debug (-D) # Enable debug logging
]

# Remove one or more sandboxes
export extern "docker sandbox rm" [
    ...sandbox: string@"nu-complete sandbox names"
    --debug (-D) # Enable debug logging
]

# Save a snapshot of the sandbox as a template
export extern "docker sandbox save" [
    sandbox: string@"nu-complete sandbox names"
    tag: string
    --debug (-D) # Enable debug logging
    --output (-o): path # Save image to specified tar file instead of loading into host Docker
]

# Reset all VM sandboxes and clean up state
export extern "docker sandbox reset" [
    --debug (-D) # Enable debug logging
    --force (-f) # Skip confirmation prompt
]

# Manage sandbox networking
export extern "docker sandbox network" [
    --debug (-D) # Enable debug logging
]

# Manage proxy configuration for a sandbox
export extern "docker sandbox network proxy" [
    sandbox: string@"nu-complete sandbox names"
    --allow-cidr: string # Remove an IP range in CIDR notation from the block or bypass lists (can be specified multiple times)
    --allow-host: string # Permit access to a domain or IP (can be specified multiple times)
    --block-cidr: string # Block access to an IP range in CIDR notation (can be specified multiple times)
    --block-host: string # Block access to a domain or IP (can be specified multiple times)
    --bypass-cidr: string # Bypass MITM proxy for an IP range in CIDR notation (can be specified multiple times)
    --bypass-host: string # Bypass MITM proxy for a domain or IP (can be specified multiple times)
    --debug (-D) # Enable debug logging
    --policy: string@[allow deny] # Set the default policy
]

# Show network logs
export extern "docker sandbox network log" [
    --debug (-D) # Enable debug logging
    --json # Output in JSON format
    --limit: int # Maximum number of log entries to show
    --quiet (-q) # Only display log entries
]

# Show sandbox version information
export extern "docker sandbox version" [
    --debug (-D) # Enable debug logging
]
