# Why: the submodules export every command so tests can `use` any helper; this file names the public ones.
# A named list flattens the namespace, so a file's subcommands go through an inline module of the same name.
module history { export use history.nu [ restore seed snapshot ] }
export use history
module projects { export use projects.nu [ restore snapshot ] }
export use projects
module global-claude { export use global-claude.nu [ restore snapshot ] }
export use global-claude
module file-history { export use file-history.nu [ snapshot ] }
export use file-history

# Snapshot nushell history, Claude Code project sessions, and global CLAUDE.md to sandbox-state.
@category cozy-sandbox-state
export def snapshot []: nothing -> nothing {
    history snapshot
    projects snapshot
    global-claude snapshot
}

# Restore nushell history, Claude Code project sessions, and global CLAUDE.md from sandbox-state.
@category cozy-sandbox-state
export def restore []: nothing -> nothing {
    history restore
    projects restore
    global-claude restore
}
