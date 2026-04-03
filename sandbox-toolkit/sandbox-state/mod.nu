export use history.nu
export use projects.nu

# Export nushell history and Claude Code project sessions to sandbox-state.
export def export []: nothing -> nothing {
    history export
    projects export
}

# Import nushell history and Claude Code project sessions from sandbox-state.
export def import []: nothing -> nothing {
    history import
    projects import
}
