# Give a `nu` launched from inside nushell the agent config — why, see
# agent-config.nu. The bash wrapper covers `nu` typed in a Bash tool call; this
# covers `nu` run from a nushell session, the nushell MCP included, where
# autoload files do load but display_output never fires (nu-mcp does not link
# nu-cli, so no hook can reach it).
#
# Measured on 3,819 session transcripts: of the 212 MCP results containing box
# drawing, 87 were a nested `nu` — the largest single cause, well ahead of a
# pipeline ending in `| table` (16).
#
# The guard sits inside the body because `def` is scoped to its block, so
# `if ... { def nu ... }` would define nothing outside the if.
def --wrapped nu [...args] {
    let passthrough = (
        ($env.CLAUDECODE? | is-empty)
        or ($args | any {|a| $a in ["--config" "--no-config-file" "--mcp" "-n"] })
    )
    if $passthrough {
        ^nu ...$args
    } else {
        ^nu --config ($nu.default-config-dir | path join agent-config.nu) ...$args
    }
}
