#!/usr/bin/env nu

# Why: the tab bar keeps the order of last use: the current tab moves to the end,
# and the new tab opens after it. Zellij's NewTab only appends at the end.
let tab_id = zellij action list-panes --json --all
    | from json
    | where id == ($env.ZELLIJ_PANE_ID | into int) and not $it.is_plugin
    | get tab_id
    | first
let tabs = zellij action list-tabs --json | from json
let position = $tabs | where tab_id == $tab_id | get position | first

# Not a move from the last position: there move-tab rotates every tab instead.
0..<(($tabs | length) - $position - 1) | each { zellij action move-tab right --tab-id $tab_id }
zellij action new-tab --cwd (pwd)
