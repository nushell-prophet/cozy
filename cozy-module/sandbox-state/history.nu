const history_db = '~/.config/nushell/history.sqlite3'
# The columns nushell itself surfaces (`history --long`), minus the ids.
# Why: session_id groups the commands of one shell sitting, and hostname says
# which machine or sandbox they ran on — provenance that is gone for good once
# a snapshot drops it. Left out: `id`, assigned by the receiving DB; `idx`, a
# row number computed at display time; and `more_info`, a reedline slot for
# embedders that nushell never writes and never shows.
const history_columns = "command_line, cwd, start_timestamp, duration_ms, exit_status, session_id, hostname"
const seed_file = path self | path dirname | path join .. history-seed.nuon

# The sandbox-state directory inside the mounted workspace; errors when no workspace is mounted.
def sandbox-state-dir []: nothing -> path {
    if $env.WORKSPACE_DIR? == null {
        error make --unspanned {msg: "WORKSPACE_DIR not set — sandbox-state requires a mounted workspace"}
    }
    $env.WORKSPACE_DIR | path join sandbox-state
}

# Path of a file under sandbox-state, creating the directory when missing.
def sandbox-state-path [filename: string]: nothing -> path {
    let dir = sandbox-state-dir
    mkdir $dir
    $dir | path join $filename
}

# Seed nushell history with useful commands from the bundled seed file.
#
# Initializes the history database if needed, then restores history-seed.nuon
# from the cozy-module directory.
@category cozy-sandbox-state
export def seed []: nothing -> nothing {
    if not ($seed_file | path exists) {
        error make --unspanned {msg: $"seed file not found: ($seed_file)"}
    }
    restore $seed_file
}

# Snapshot nushell history to a nuon file.
#
# Reads the sqlite database directly, so it works from any context:
# interactive shell, `nu -c`, scripts, or the Bash tool.
# No login shell (`nu -l`) required.
# Each snapshot gets a timestamped filename; restore picks the most recent by name.
@category cozy-sandbox-state
export def snapshot [
    path?: path # Output file (default: $env.WORKSPACE_DIR/sandbox-state/history-<timestamp>.nuon)
]: nothing -> nothing {
    let out = $path | default (sandbox-state-path $"history-(date now | format date '%Y%m%d-%H%M%S').nuon")
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make --unspanned {msg: $"history database not found: ($db)"}
    }
    let items = open $db | query db $"SELECT ($history_columns) FROM history ORDER BY id"
    if ($items | is-empty) {
        print 'No history items to snapshot'
        return
    }
    $items | save --force $out
    print $"Snapshotted ($items | length) history items to ($out)"
}

# Restore nushell history from a nuon file.
#
# Inserts directly into the sqlite database, so it works from any context.
# The file must have the columns command_line, cwd, start_timestamp,
# duration_ms and exit_status; session_id and hostname are optional, so older
# snapshots and history-seed.nuon still restore.
# Without a path, restores from the most recent history-*.nuon in sandbox-state.
# Deduplicates incoming rows and skips entries already in the DB.
# New rows are inserted oldest-first so recall stays chronological.
@category cozy-sandbox-state
export def restore [
    path?: path # Input file (default: latest history-*.nuon in $env.WORKSPACE_DIR/sandbox-state/)
]: nothing -> nothing {
    let src = if $path != null { $path } else {
        let dir = sandbox-state-dir
        let files = glob ($dir | path join 'history-*.nuon') | sort
        if ($files | is-empty) {
            error make --unspanned {msg: $"no history snapshots found in ($dir)"}
        }
        $files | last
    }
    if not ($src | path exists) {
        error make --unspanned {msg: $"file not found: ($src)"}
    }
    let db = $history_db | path expand
    if not ($db | path exists) {
        error make --unspanned {msg: $"history database not found: ($db)"}
    }
    let items = open $src
    if ($items | is-empty) {
        print 'No history items to restore'
        return
    }

    # Deduplicate incoming rows
    let items = $items | uniq-by start_timestamp command_line

    # Skip rows already present in the DB
    let existing_ts = open $db
        | query db "SELECT start_timestamp FROM history"
        | get start_timestamp
    let new_items = $items | where start_timestamp not-in $existing_ts

    if ($new_items | is-empty) {
        print $"All ($items | length) entries already in history, nothing to restore"
        return
    }

    # Insert oldest-first. reedline's recall query orders by `id`, so seeding
    # an empty history (the common case: restoring into a fresh sandbox) in
    # timestamp order is enough to make recall chronological — no global
    # re-sequencing needed.
    #
    # Not re-sorting the whole table afterwards: the old code did
    # `DELETE FROM history` then reinserted every row to renumber ids. That
    # had two faults. (1) It could not be atomic — nushell's `query db`
    # runs one statement per call and rejects multi-statement strings, so
    # there is no way to wrap the delete + reinserts in a transaction; a
    # crash mid-reinsert truncated the user's entire history. (2) It reinserted
    # only 5 of the table's 9 columns, silently nulling session_id, hostname,
    # and more_info on every import. Appending is safe by contrast: it never
    # removes existing rows, and a partial run is fully recoverable on re-run
    # via the dedup above. The tradeoff is that when merging into an already
    # populated history, older imported entries recall after existing ones
    # rather than being globally interleaved — acceptable to remove a
    # data-loss path.
    # Batched: one multi-row INSERT per chunk opens the DB once per chunk
    # instead of once per row. Chunk size 100 keeps the bound-parameter count
    # (7 per row, so 700) under SQLite's limit on every build (999 before 3.32,
    # 32766 after).
    $new_items
    | sort-by start_timestamp
    | chunks 100
    | each {|batch|
        let placeholders = $batch | each { "(?, ?, ?, ?, ?, ?, ?)" } | str join ', '
        let params = $batch
            | each {|row|
                [
                    $row.command_line
                    $row.cwd
                    $row.start_timestamp
                    ($row.duration_ms | default 0)
                    ($row.exit_status | default 0)
                    # Optional access: snapshots made before these columns were carried,
                    # and history-seed.nuon, have no such cell — null is the honest
                    # value for "this row never had a session".
                    $row.session_id?
                    $row.hostname?
                ]
            }
            | flatten
        open $db | query db $"INSERT INTO history \(($history_columns)\) VALUES ($placeholders)" --params $params
    }
    | ignore

    let total = open $db | query db "SELECT count(*) AS n FROM history" | get 0.n
    let skipped = ($items | length) - ($new_items | length)
    print $"Restored ($new_items | length) new entries, ($skipped) duplicates skipped. History: ($total) total"
}
