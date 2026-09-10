# Commands for the cozy sandbox: repos, docs, mounts, sandbox state, installers, git, verify.
# Each subcommand has its own help: `help cozy <subcommand>`.
export def main [] { }

export use sync-repos.nu
export use docs.nu
export use mount.nu
export use swap-zellij-super.nu
export use sandbox-state/
export use dev-link.nu
export use install/
export use configure/
export use git.nu
export use verify.nu
export use logo.nu
export use nu-demo-instance.nu
export use use-host-ssh-agent.nu

# Commit a file into the sandbox-state file history, keyed by its full path (short for `cozy sandbox-state file-history snapshot`).
export alias fhs = sandbox-state file-history snapshot
