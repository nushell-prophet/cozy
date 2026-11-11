# The zellij tab follows the directory of the shell, but only while the tab
# still carries a name this hook gave it.
# Why: the user renames a tab by hand in zellij, and the next `cd` must not
# undo that. The hook recognizes its own names from the directories the panes
# of the tab are in (plus the directory this shell just left), so a name
# typed by the user matches none of them and stays until the user changes it.
# Not a per-shell memory of the last name set because: two shells in one tab
# would each take the other's rename for the user's and both stop.

# The basename of a directory, as it goes into a tab name.
# Why strip the leading dashes: a Claude Code project directory is named
# `-Users-user-...`.
def "tab-name base" []: string -> string {
    path basename | str replace --regex '^-+' ''
}

# `foo·3` -> {base: foo, n: 3}; `foo` -> {base: foo, n: 1}.
def "tab-name parse" []: string -> record<base: string, n: int> {
    let name = $in
    let parts = $name | split row '·'
    let tail = $parts | last
    if ($parts | length) > 1 and $tail =~ '^\d+$' {
        {base: ($parts | drop | str join '·'), n: ($tail | into int)}
    } else {
        {base: $name, n: 1}
    }
}

# Rename the tab of this pane after `$before` as the shell cd's from it to `$after`.
def "tab-name follow" [before: any, after: string] {
    if $env.ZELLIJ_PANE_ID? == null { return }
    # Why `not is_plugin`: a plugin pane and a terminal pane can share an id.
    let panes = zellij action list-panes --json --all | from json | where not is_plugin
    let own = $panes | where id == ($env.ZELLIJ_PANE_ID | into int) | first
    let current = $own.tab_name | tab-name parse
    let hook_bases = $panes
    | where tab_id == $own.tab_id
    | get pane_cwd
    | append $before
    | compact
    | each { tab-name base }
    let is_default_name = $own.tab_name =~ '^Tab #\d+$'
    if not ($is_default_name or $current.base in $hook_bases) { return }

    let base = $after | tab-name base
    if $base == $current.base { return }
    let used = $panes
    | where tab_id != $own.tab_id
    | get tab_name
    | uniq
    | each { tab-name parse }
    | where base == $base
    | get n
    let n = 1.. | where $it not-in $used | first
    let name = if $n == 1 { $base } else { $'($base)·($n)' }
    zellij action rename-tab --tab-id $own.tab_id $name
}

$env.config.hooks = {
    pre_prompt: [{ null }] # run before the prompt is shown
    pre_execution: [{ null }] # run before the repl input is run
    env_change: {
        PWD: [{|before, after| tab-name follow $before $after }]
    }

    display_output: {
        metadata access {|meta|
            match $meta.content_type? {
                "application/x-nuscript" | "application/x-nuon" | "text/x-nushell" => { nu-highlight }
                "application/json" => { ^bat --language=json --color=always --style=plain --paging=never }
                _ => { }
            }
        }
        | if (term size).columns >= 100 { table -e } else { table }
    }

    # run to display the output of a pipeline
    command_not_found: { null } # return an error message when a command is not found
}
