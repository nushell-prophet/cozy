# Ensure nushell MCP server is registered in Claude Code user config.
# Self-healing: sandbox create may overwrite ~/.claude.json, this restores the MCP entry.
# Note: MCP servers are read from ~/.claude.json (user scope), NOT ~/.claude/settings.json.
let config_path = $nu.home-dir | path join .claude.json
let nu_bin = which nu | get 0.path
if ($config_path | path exists) {
    let config = open $config_path
    if ($config | get --optional mcpServers.nushell) == null {
        $config
        | upsert mcpServers.nushell {type: stdio command: $nu_bin args: ["--mcp"] env: {}}
        | save -f $config_path
    }
} else {
    {mcpServers: {nushell: {type: stdio command: $nu_bin args: ["--mcp"] env: {}}}}
    | save -f $config_path
}
