# Nushell config for agent-launched `nu`, deployed to ~/.config/nushell/.
#
# `nu --commands` and `nu script.nu` load no config at all, so they render with
# stock defaults: an 80-column box table that wraps identifiers mid-word, drops
# columns into a bare `...` and hides nested values behind `[list 3 items]`. A
# human at a wide terminal never sees that; anything reading the output as text
# loses the data silently. Two wrappers pass this file in with --config:
# /etc/sandbox-persistent.sh (bash) and autoload/agent-nu-wrapper.nu (nushell).
# Not in autoload/ itself — those load into the human's session too.
#
# Hook only: adding the module set here measured 150ms per `nu` against 2ms for
# this, and agents invoke nu constantly.

$env.config.hooks.display_output = {||
    let v = $in
    match ($v | describe --detailed | get type) {
        # The types drawn with box rules; a table describes as a list.
        "list" | "record" | "range" => ($v | to nuon --pretty)
        # Not a no-op: an untouched binary writes raw bytes, 300 of terminal
        # garbage where `table` gives 20 readable lines of hex dump.
        "binary" => ($v | table)
        _ => $v
    }
}
