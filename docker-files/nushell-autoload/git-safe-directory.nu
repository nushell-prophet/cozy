# Re-assert git safe.directory = '*' on shell start.
# Self-healing: sandbox creation narrows safe.directory to just the
# workspace-root path. bootstrap.nu sets '*' in the XDG file
# (~/.config/git/config) and `cozy mount init` sets it globally. git does NOT extend that to the submodule repos beneath it (dotnu,
# numd, …), so each repo trips "dubious ownership" whenever the VirtioFS mount
# intermittently reports its dir as uid 0 instead of the agent's uid.
# Same self-healing pattern as mcp-server.nu restoring the MCP entry.
# Guarded so the normal path writes nothing.
let current = do { git config --global --get-all safe.directory } | complete
if $current.exit_code != 0 or ($current.stdout | lines | str trim) != ['*'] {
    git config --global --replace-all safe.directory '*'
}
