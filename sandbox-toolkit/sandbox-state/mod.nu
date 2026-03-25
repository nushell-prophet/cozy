export use history.nu
export use projects.nu

# Export both nushell history and Claude Code project sessions to sandbox-state.
export def export []: nothing -> nothing {
    history export
    projects export
}

# Import both nushell history and Claude Code project sessions from sandbox-state.
export def import []: nothing -> nothing {
    history import
    projects import
}
