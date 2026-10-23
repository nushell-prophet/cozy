# Commands for the cozy sandbox: repos, docs, mounts, sandbox state, installers, git, verify.
# Each subcommand has its own help: `help cozy <subcommand>`.
export def main [] { }

export use sync-repos.nu [ main ]
export use docs.nu
export use mount.nu
export use swap-zellij-super.nu
export use sandbox-state/
export use dev-link.nu
export use install/
export use configure/
# Why: the submodules export every command so tests can `use` any helper; this file names the public ones.
# A named list flattens the namespace, so a file's subcommands go through an inline module of the same name.
module git { export use git.nu [ harden install-change-id-hook link resolve ] }
export use git
export use verify.nu [ main ]
module verify { export use verify.nu [ local-runner report run-checks ] }
export use verify
export use logo.nu
export use nu-demo-instance.nu
export use use-host-ssh-agent.nu [ main ]

# Commit a file into the sandbox-state file history, keyed by its full path (short for `cozy sandbox-state file-history snapshot`).
export alias fhs = sandbox-state file-history snapshot
