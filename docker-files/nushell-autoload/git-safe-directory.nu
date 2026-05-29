# Re-assert git safe.directory = '*' on shell start.
# Self-healing: `docker sandbox` create overwrites the global safe.directory
# (set to '*' by bootstrap.nu / `cozy mount init`) with just the workspace-root
# path. git does NOT extend that to the submodule repos beneath it (dotnu,
# numd, …), so each repo trips "dubious ownership" whenever the VirtioFS mount
# intermittently reports its dir as uid 0 instead of the agent's uid.
# Same self-healing pattern as mcp-server.nu restoring the MCP entry.
# Guarded so the normal path writes nothing.
let current = do { git config --global --get-all safe.directory } | complete
if $current.exit_code != 0 or ($current.stdout | lines | str trim) != ['*'] {
    git config --global --replace-all safe.directory '*'
}
