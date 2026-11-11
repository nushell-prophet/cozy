use kv
use str.nu [ "str to-md-fence" escape-regex ]

# use in-vd.nu

@category history
export def get-last-commands-from-sql [n: int = 1]: nothing -> any {
    if ($nu.history-path | str ends-with 'txt') {
        return (history | last $n | get command | if $n == 1 { get 0 } else { })
    }

    open $nu.history-path
    | query db "select command_line from history order by id desc limit ?" --params [$n]
    | get command_line
    | reverse
    | if $n == 1 { get 0 } else { }
}

# Copy this command to clipboard
@category history
export def 'copy-cmd' [
    --md # Wrap the command in a ```nu markdown block
]: nothing -> nothing {
    let commands = get-last-commands-from-sql 2
        | str trim

    $commands
    | last
    | if $in =~ '^copy-cmd(\s|$)' {
        $commands | first
    } else { }
    | str replace --regex '\s*\| copy-cmd.*' ''
    | if $md { str to-md-fence } else { }
    | pbcopy
}

# Filter history with regex and convenient flags, add useful columns
@category history
export def 'hist' [
    like_filter?: string # a string to search in db
    --regex-filters: list<string> = [] # a regex to search for
    --entries: int = 5000 # A number of last entries to work with
    --all (-a) # Return all the history
    --session (-s) # Show only entries from the current session
    --cwd # Show only entries from the current folder
    --last-x: duration # Duration for the period to check commands
    --not-in-vd (-V) # Disable opening command in visidata
    --all-codes # Output all the commands, no only with 0 code
]: nothing -> any {
    if ($nu.history-path | str ends-with 'txt') {
        print "hist requires SQLite history format"
        return
    }

    # Start building the SQL query
    let sql_query = "
        SELECT command_line as command, start_timestamp / 1000 as start_timestamp, session_id, hostname, cwd,
        duration_ms / 1000000.0 as duration_s, exit_status FROM history WHERE 1=1
    "
        | if $like_filter != null {
            append " AND command_line LIKE ?"
        } else { }
        | append " AND command_line NOT LIKE 'hist %'" # Build where clauses based on parameters Exclude 'hist' commands
        | if $all_codes { } else { append " AND exit_status = 0" } # Only successful commands
        | if $session {
            # Session filter
            append $" AND session_id = (history session)"
        } else { }
        | if $cwd {
            # Folder filter
            append " AND cwd = ?"
        } else { }
        | if $last_x != null {
            # Time filter
            append $" AND start_timestamp > ((date now) - $last_x | into int | $in // 1_000_000)" # ns -> ms, raw start_timestamp column stores milliseconds
        } else { }
        | append ' ORDER BY id DESC'
        | if not ($all or $entries == 0 or $like_filter != null) {
            append $" LIMIT ($entries)"
        } else { }
        | str join

    # Why: the user's text and the path go as parameters, so a `'` in them cannot break the query.
    # The order follows the `?` placeholders above.
    let params = []
        | if $like_filter != null { append $"%($like_filter)%" } else { }
        | if $cwd { append (pwd) } else { }

    # Execute the query
    let results = open $nu.history-path | query db $sql_query --params $params

    # Apply regex filters in Nushell (SQLite doesn't support all regex features)
    let filtered_results = if $regex_filters == [] {
        $results
    } else {
        $regex_filters
        | reduce --fold $results {|pattern|
            where command =~ $pattern
        }
    }

    # Format timestamps as human readable
    # Convert nanoseconds to seconds and format
    # TODO: check that filtering by options is adjusted by offset too
    let formatted_results = $filtered_results | into datetime --format '%s' --offset (-3) start_timestamp

    # Add pipe count column
    $formatted_results
    | insert pipes {|i|
        # ast --flatten $i.command
        # | where shape == shape_pipe
        $i.command
        | parse --regex '(\s\|)'
        | length
    }
    # Display in visidata or return
    | if $not_in_vd { } else { in-vd history }
}

# Save significant or all current session history entries into a .nu file. If the .nu file already exists, data will be appended.
@category history
export def 'hist-to-script' [
    filename?: path
    --dont-open (-O) # Don't open the saved history file in editor
    --up (-u): int = 0 # Set number of last events to save
    --all # Save all history into .nu file
    --directory-hist # Get history for a directory instead of session
]: nothing -> nothing {
    if ($nu.history-path | str ends-with 'txt') {
        print "hist-to-script requires SQLite history format"
        return
    }

    let session = history session

    let filepath = $filename
        | if ($in != null) { } else { $"history($session)" }
        | path parse
        | update extension 'nu'
        | path join

    let hist = open $nu.history-path
        | query db (
            if $directory_hist {
                "SELECT command_line FROM history WHERE cwd = ? ORDER BY id"
            } else {
                "SELECT command_line FROM history WHERE session_id = ? ORDER BY id"
            }
        ) --params [(if $directory_hist { $env.PWD } else { $session })]
        | get command_line
        | str replace --all --regex $';(char nl)\$.*? in-vd' ''
        | drop 1

    let buffer = $hist
        | if $up > 1 {
            last ($up + 1)
        } else if $all { } else {
            where {|i|
                $i =~ '(^(let|def|export) )|#|\b(save|source|mkdir|polars to-csv|polars to-avro|polars to-jsonl|polars to-arrow|polars to-parquet)\b'
            }
        }
        | str join "\n\n"
        | $"\n#($filepath)\n($in)\n#---\n"

    $buffer | save --append $filepath

    if not $dont_open {
        commandline edit --replace $'($env.EDITOR) ($filepath)'
    }
}

# Open nushell commands history in visidata
@category history
export def 'in-vd history' []: table -> nothing {
    where command !~ 'in-vd history'
    | if ($in | is-empty) {
        print --stderr 'hist: nothing found'
        return
    } else { }
    | to csv
    | vd --save-filetype csv --filetype csv --output -
    | complete
    | get stdout
    | if ($in == null) { return } else { }
    | from csv
    | kv set vd-history --return-to-stdout
    | get command
    | reverse
    | str join $'(char nl)'
    | str replace --regex ';.+?\| in-vd;' ';'
    | commandline edit --replace $in
}

# Helper function to get all unique directories from command history that exist now
export def 'get-history-dirs' []: nothing -> list<string> {
    open $nu.history-path
    | query db "SELECT DISTINCT(cwd) FROM history ORDER BY id DESC"
    | get cwd
    | compact
    # Not a stored list of dead directories because: a stored list goes stale, and the check of the whole list costs only milliseconds.
    | where { path exists }
}

# Select a directory path using fuzzy search
export def 'select-dir' [
    query: string # The search query
    --interactive (-i) # Force interactive mode
]: nothing -> string {
    let valid_cwds = get-history-dirs | to text

    if ($query | path exists) {
        return $query
    }

    if $interactive {
        return ($valid_cwds | fzf --scheme=path --query $query)
    }

    # Try fuzzy finding first
    let best_match = $valid_cwds | fzf --filter $query | lines | get 0?

    if ($best_match | is-empty) {
        # Fall back to interactive
        $valid_cwds | fzf --scheme=path --query $query
    } else {
        $best_match
    }
}

# Helper function to get open Zellij tab names
export def 'zellij-tab-names' []: nothing -> list<string> {
    if ($env.ZELLIJ? | is-empty) { return [] }
    zellij action query-tab-names | lines
}

# The name the PWD hook of the nushell config (`hooks-config.nu` in dotfiles) gives the tab of a directory
# Why: z looks for the tab the hook named, so it strips the leading dashes the same way
# (a Claude Code project directory is named `-Users-user-...`)
export def 'zellij-tab-name' []: string -> string {
    path basename | str replace --regex '^-+' ''
}

# Generate regex pattern to match Zellij tab by its name
# Matches "name" or "name·2" (indexed duplicates)
export def 'zellij-tab-pattern' [dir_name: string]: nothing -> string {
    ['^' ($dir_name | escape-regex) '(·\d+)?$'] | str join
}

# Handle Zellij tab navigation: create a new tab or switch to an existing one.
# Returns true if caller should cd, false if Zellij handled navigation.
# Why no tab naming here: the PWD hook of the nushell config (`hooks-config.nu` in dotfiles) names the tab
# after the directory; it keeps a name the user typed by hand and numbers a duplicate `name·2`.
export def 'zellij-navigate' [
    path: string # Target directory path
    dir_name: string # Tab name to look for
    --new-tab (-n) # Open in new tab
]: nothing -> bool {
    if ($env.ZELLIJ? | is-empty) { return true }

    if $new_tab {
        # Create new tab with the directory
        zellij action new-tab --layout compact-bar-up --cwd $path
        return false
    }

    # Check if tab with this name already exists
    let matching_tab = zellij-tab-names
        | where $it =~ (zellij-tab-pattern $dir_name)
        | get 0?

    let request: closure = {
        [
            {value: true description: 'switch to existing tab'}
            {value: false description: 'stay here'}
        ]
        | input list 'there is zellij tab already' --display description
        | get value
    }

    if ($matching_tab | is-not-empty) and (do $request) {
        # Switch to existing tab
        zellij action go-to-tab-name $matching_tab
        return false
    }

    true
}

# Jump to directory from history using fuzzy search
@category filesystem
export def --env 'z' [
    query?: string@'completions-cwds' # Fuzzy search query for directory
    --interactive (-i) # Always show interactive picker
    --new-tab (-n) # Open in new Zellij tab
]: nothing -> nothing {
    if ($nu.history-path | str ends-with 'txt') {
        print "z requires SQLite history format"
        return
    }

    # Get target path - default to interactive mode when no query
    let target_path = select-dir ($query | default "") --interactive=($interactive or ($query | is-empty))

    # Exit if no path was selected
    if ($target_path | is-empty) { return }

    # Expand the path to full format
    let expanded_path = $target_path | path expand

    let dir_name = $expanded_path | zellij-tab-name

    # Why: after a switch to another tab or a new tab, the shell left behind stays where it was;
    # a cd there would make the tab hook rename its tab to `name·2`, next to the tab just reached
    if (zellij-navigate $expanded_path $dir_name --new-tab=$new_tab) {
        cd $expanded_path
    }
}

# Generate completions for z command from history
export def 'completions-cwds' []: nothing -> record {
    if ($nu.history-path | str ends-with 'txt') { return {completions: [] options: {}} }

    let termsize = term size | get columns | $in - 5

    # Get open Zellij tabs for marking
    let zellij_tabs = zellij-tab-names

    let now_ms = date now | into int | $in // 1_000_000

    let rows = open $nu.history-path
        | query db "SELECT cwd,
                   MAX(start_timestamp) as last_timestamp,
                   MIN(start_timestamp) as first_timestamp,
                   COUNT(*) as commands
               FROM history
               GROUP BY cwd
               ORDER BY MAX(id) DESC"
        | where cwd != null
        | where { $in.cwd | path exists }
        | each {|row|
            let timestamp = $row.last_timestamp | into int | $in / 1000 | into int | into datetime --format '%s' | date humanize

            let value = do --ignore-errors { $row.cwd | path relative-to $nu.home-dir }
                | match $in {
                    null => $row.cwd
                    '' => '~'
                    $relative_pwd => ([~ $relative_pwd] | path join)
                }

            # Why: the long workspace root is in every history path and cannot move, so the menu shows only the part inside it; nushell still inserts the full value
            let display = if $env.WORKSPACE_DIR? != null {
                    do --ignore-errors { $row.cwd | path relative-to $env.WORKSPACE_DIR }
                }
                | default --empty $value

            # Check if a Zellij tab exists for this directory
            let dir_name = $row.cwd | zellij-tab-name
            let has_tab = $zellij_tabs | any { $in =~ (zellij-tab-pattern $dir_name) }

            {
                value: $value
                display: $display
                last: (if $has_tab { $"⇆ ($timestamp)" } else { $"  ($timestamp)" })
                days: $"($now_ms - $row.first_timestamp | $in // 86_400_000)d"
                commands: $"($row.commands) cmd"
                # Why: wtr, public and mono are the special directories of the mono workflow; a path with no mark is a visible signal too
                mark: ($display | path split | where $it in [wtr public mono] | get 0? | if $in == null { '' } else { $'# ($in)/' })
            }
        }

    # Why: aligned columns put the marks in one column at the end, where they read as a signal
    let width = {|column| $rows | get $column | each { str length --grapheme-clusters } | append 0 | math max }
    let w_last = do $width last
    let w_days = do $width days
    let w_commands = do $width commands

    let described = $rows
        | each {|row|
            let description = [
                ($row.last | fill --width $w_last)
                ($row.days | fill --alignment right --width $w_days)
                ($row.commands | fill --alignment right --width $w_commands)
                $row.mark
            ]
            {value: $row.value display_override: $row.display description: ($description | str join '  ' | str trim --right)}
        }
    let hint_width = $described.description | each { str length --grapheme-clusters } | append 0 | math max

    let variants = $described
        # Why: the menu gives the hint only the width left after the longest shown path, so one long path cuts every hint
        | where ($it.display_override | str length --grapheme-clusters) + $hint_width < $termsize
        # Why: nushell inserts a completion value as is, and a backtick string keeps a path with spaces one word
        | update value { if $in has ' ' { $'`($in)`' } else { } }

    {
        options: {
            case_sensitive: false
            completion_algorithm: fuzzy
            sort: false
        }
        completions: $variants
    }
}
