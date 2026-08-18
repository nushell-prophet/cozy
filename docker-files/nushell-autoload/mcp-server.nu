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
# Why $nu.current-exe and not `which nu`: `which` answers about any command of
# that name, and agent-nu-wrapper.nu — loaded earlier, autoload is alphabetical —
# defines one, so `which nu | get 0.path` returned that .nu file and the entry
# told Claude Code to execute a non-executable script. current-exe is the running
# binary; no definition can shadow it.
let config_path = $nu.home-dir | path join .claude.json
let nu_bin = $nu.current-exe
let entry = {type: stdio command: $nu_bin args: ["--mcp"] env: {}}
if ($config_path | path exists) {
    let config = open $config_path
    # Compare the command, not just presence. A wrong path already written is
    # exactly what needs healing, and a presence test never fires for it.
    if ($config | get --optional mcpServers.nushell.command) != $nu_bin {
        $config | upsert mcpServers.nushell $entry | save --force $config_path
    }
} else {
    {mcpServers: {nushell: $entry}} | save --force $config_path
}
