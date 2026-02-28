const history_db = '~/.config/nushell/history.sqlite3'
const history_columns = "command_line, cwd, start_timestamp, duration_ms, exit_status"
const sandbox_state_dir = '~/mounted/sandbox-state'

def sandbox-state-path [filename: string]: nothing -> path {
    let dir = $sandbox_state_dir | path expand
    mkdir $dir
    $dir | path join $filename
}

export def main [] { help history }

# Export nushell history to a nuon file.
#
# Reads the sqlite database directly, so it works from any context:
# interactive shell, `nu -c`, scripts, or the Bash tool.
# No login shell (`nu -l`) required.
# Each export gets a timestamped filename; latest symlink always points to the most recent.
export def export [
    path?: path  # Output file (default: ~/mounted/sandbox-state/history-<timestamp>.nuon)
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
export def import [
    path?: path  # Input file (default: ~/mounted/sandbox-state/history-latest.nuon)
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
    $items | each {|row|
        open $db
        | query db $"INSERT INTO history \(($history_columns)\) VALUES \(?, ?, ?, ?, ?)" --params [
            $row.command_line
            $row.cwd
            $row.start_timestamp
            $row.duration_ms
            $row.exit_status
        ]
    } | ignore
    print $"Imported ($items | length) history items"
}
