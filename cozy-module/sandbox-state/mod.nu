export use history.nu
export use projects.nu
export use global-claude.nu

# Export nushell history, Claude Code project sessions, and global CLAUDE.md to sandbox-state.
export def export []: nothing -> nothing {
    history export
    projects export
    global-claude export
}

# Import nushell history, Claude Code project sessions, and global CLAUDE.md from sandbox-state.
export def import []: nothing -> nothing {
    history import
    projects import
    global-claude import
}
