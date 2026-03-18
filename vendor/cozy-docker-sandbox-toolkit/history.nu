const history_db = '~/.config/nushell/history.sqlite3'
const history_columns = "command_line, cwd, start_timestamp, duration_ms, exit_status"
const sandbox_state_dir = '~/workspace/mounted/sandbox-state'
const seed_file = path self | path dirname | path join 'history-seed.nuon'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

export def main [] { help history }

# Seed nushell history with useful commands from the bundled seed file.
#
# Initializes the history database if needed, then imports history-seed.nuon
# from the toolkit directory.
export def seed []: nothing -> nothing {
    if not ($seed_file | path exists) {
        error make { msg: $"seed file not found: ($seed_file)" }
    }
    import $seed_file
}

# Export nushell history to a nuon file.
#
# Reads the sqlite database directly, so it works from any context:
# interactive shell, `nu -c`, scripts, or the Bash tool.
# No login shell (`nu -l`) required.
# Each export gets a timestamped filename; latest symlink always points to the most recent.
export def export [
    path?: path  # Output file (default: ~/workspace/mounted/sandbox-state/history-<timestamp>.nuon)
]: nothing -> nothing {
    let out = $path | default (sandbox-state-path $"history-(date now | format date '%Y%m%d-%H%M%S').nuon")
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make { msg: $"history database not found: ($db)" }
    }
    let items = open $db | query db $"SELECT ($history_columns) FROM history ORDER BY id"
    if ($items | is-empty) {
        print 'No history items to export'
        return
    }
    $items | save --force $out
    # update "latest" symlink
    let link = $out | path dirname | path join 'history-latest.nuon'
    rm -f $link
    ^ln -s ($out | path basename) $link
    print $"Exported ($items | length) history items to ($out)"
}

# Import nushell history from a nuon file.
#
# Inserts directly into the sqlite database, so it works from any context.
# The file should contain a table with columns:
# command_line, cwd, start_timestamp, duration_ms, exit_status.
# Without a path, imports from the latest export via the history-latest.nuon symlink.
# Deduplicates incoming rows and skips entries already in the DB.
# Re-sorts the DB by start_timestamp after import.
export def import [
    path?: path  # Input file (default: ~/workspace/mounted/sandbox-state/history-latest.nuon)
]: nothing -> nothing {
    let src = $path | default (sandbox-state-path 'history-latest.nuon')
    if not ($src | path exists) {
        error make { msg: $"file not found: ($src)" }
    }
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make { msg: $"history database not found: ($db)" }
    }
    let items = open $src
    if ($items | is-empty) {
        print 'No history items to import'
        return
    }

    # Deduplicate incoming rows
    let items = $items | uniq-by start_timestamp command_line

    # Skip rows already present in the DB
    let existing_ts = open $db
        | query db "SELECT start_timestamp FROM history"
        | get start_timestamp
    let new_items = $items | where { $in.start_timestamp not-in $existing_ts }

    if ($new_items | is-empty) {
        print $"All ($items | length) entries already in history, nothing to import"
        return
    }

    $new_items | each {|row|
        open $db
        | query db $"INSERT INTO history \(($history_columns)\) VALUES \(?, ?, ?, ?, ?)" --params [
            $row.command_line
            $row.cwd
            $row.start_timestamp
            ($row.duration_ms | default 0)
            ($row.exit_status | default 0)
        ]
    } | ignore

    # Re-sort: extract all rows sorted, delete, reinsert with sequential IDs
    let sorted = open $db
        | query db $"SELECT ($history_columns) FROM history ORDER BY start_timestamp ASC"
    open $db | query db "DELETE FROM history"
    $sorted | each {|row|
        open $db
        | query db $"INSERT INTO history \(($history_columns)\) VALUES \(?, ?, ?, ?, ?)" --params [
            $row.command_line $row.cwd $row.start_timestamp $row.duration_ms $row.exit_status
        ]
    } | ignore

    let skipped = ($items | length) - ($new_items | length)
    print $"Imported ($new_items | length) new entries, ($skipped) duplicates skipped. History: ($sorted | length) total, sorted by timestamp"
}
