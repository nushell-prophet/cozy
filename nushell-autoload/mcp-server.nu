# Ensure nushell MCP server is registered in Claude Code settings.
# Self-healing: sandbox create overwrites settings.json, this restores the config.
let settings_path = $nu.home-dir | path join .claude settings.json
if ($settings_path | path exists) {
    let settings = open $settings_path
    if ($settings | get --optional mcpServers.nushell) == null {
        $settings
        | upsert mcpServers {nushell: {type: stdio, command: nu, args: ["--mcp"], env: {}}}
        | save -f $settings_path
    }
}
