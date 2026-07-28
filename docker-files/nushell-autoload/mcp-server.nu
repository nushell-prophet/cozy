# Raise the MCP output cap from its 10kb default (nu-mcp evaluation.rs:19).
# Why: over the cap the tool returns *no* output at all — only a note pointing
# at $history.N — so every long result cost a second round trip, and in the
# session logs more than half of those were never fetched at all. The Bash tool
# at least shows the head. Set here, not via `claude mcp add --env`: nu-mcp
# reads it with `as_filesize`, which takes a real filesize value and refuses a
# string, so a process env var is silently ignored.
# Not `0` (unlimited) because: one stray `open big.json` would then push the
# whole file into the context window. Keep a backstop, just a roomier one.
$env.NU_MCP_OUTPUT_LIMIT = 64kb

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
