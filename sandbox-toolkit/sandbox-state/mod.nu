export use history.nu
export use projects.nu
export use credentials.nu

# Export nushell history, Claude Code project sessions, and credentials to sandbox-state.
export def export []: nothing -> nothing {
    history export
    projects export
    credentials export
}

# Import nushell history, Claude Code project sessions, and credentials from sandbox-state.
export def import []: nothing -> nothing {
    credentials import
    history import
    projects import
}
