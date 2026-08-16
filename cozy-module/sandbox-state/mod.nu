export use history.nu
export use projects.nu
export use global-claude.nu

# Snapshot nushell history, Claude Code project sessions, and global CLAUDE.md to sandbox-state.
export def snapshot []: nothing -> nothing {
    history snapshot
    projects snapshot
    global-claude snapshot
}

# Restore nushell history, Claude Code project sessions, and global CLAUDE.md from sandbox-state.
export def restore []: nothing -> nothing {
    history restore
    projects restore
    global-claude restore
}
