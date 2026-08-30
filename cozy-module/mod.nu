export def main [] { }

export use sync-repos.nu
export use docs.nu
export use mount.nu
export use swap-zellij-super.nu
export use sandbox-state/
export use dev-link.nu
export use install/
export use configure/
export use git-harden.nu
export use verify.nu
export use logo.nu
export use nu-demo-instance.nu

# Commit a file into the sandbox-state file history, keyed by its full path (short for `cozy sandbox-state file-history snapshot`).
export alias fhs = sandbox-state file-history snapshot
