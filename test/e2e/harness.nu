# Playwright-for-terminals: drive real zellij panes to e2e-test cozy's
# interactive (Layer 2) command flows. See ../../todo/20260528-172203-zellij-interactive.md
# for the full design rationale (#4508 PTY-client constraint, Layer 1/2 split).
#
# Every verb takes a `ctx` record { session, job } returned by `start`, so the
# whole harness drives ONE dedicated, uniquely-named test session and never
# touches the user's live session.

# Create a background session and attach a sized throwaway PTY client to it.
#
# Why a PTY client: zellij 0.44.3 renders nothing and applies no input to a
# --create-background session until a real client is attached (#4508). We attach
# one for the test's lifetime via `script`, then poll list-clients until it lands
# before returning — never sleep-and-hope.
export def start [
    name: string  # unique session name; the test owns it exclusively
    --rows: int = 40  # pin terminal size so renders are deterministic (headless default 50x49 is not)
    --cols: int = 120
    --timeout: duration = 10sec
]: nothing -> record<session: string, job: int> {
    zellij attach --create-background $name | ignore

    # Why script -qec ... /dev/null: a real PTY client is the only thing that
    # makes the session render; util-linux `script` gives us one headlessly.
    let job = job spawn { ^script -qec $"stty rows ($rows) cols ($cols); zellij attach ($name)" /dev/null }

    let deadline = (date now) + $timeout
    mut attached = false
    while (date now) < $deadline {
        # >1 line means a client row exists past the header
        if (zellij --session $name action list-clients | lines | length) > 1 {
            $attached = true
            break
        }
        sleep 200ms
    }
    if not $attached {
        job kill $job
        zellij delete-session --force $name | ignore
        error make { msg: $"PTY client never attached to session ($name) within ($timeout)" }
    }

    { session: $name, job: $job }
}

# Kill the PTY client job and delete the session. Safe to call in teardown even
# if start partially failed — both operations swallow their own errors.
export def stop [ctx: record<session: string, job: int>]: nothing -> nothing {
    try { job kill $ctx.job }
    zellij delete-session --force $ctx.session | ignore
}

# Spawn a new pane running a command; returns its pane id (e.g. "terminal_2").
export def run-cmd [
    ctx: record
    ...cmd: string
    --floating
    --cwd: string
]: nothing -> string {
    mut args = [--session $ctx.session run]
    if $floating { $args = ($args | append "--floating") }
    if $cwd != null { $args = ($args | append [--cwd $cwd]) }
    zellij ...$args -- ...$cmd | str trim
}

# Spawn a `nu` pane and wait until its prompt has rendered (so input lands in
# the REPL, not a half-initialised shell). Returns the pane id.
export def run-nu [ctx: record, --cwd: string]: nothing -> string {
    let pane = if $cwd != null { run-cmd $ctx nu --cwd $cwd } else { run-cmd $ctx nu }
    # nu's default prompt ends with a '>' on the prompt line; wait for it.
    wait-text $ctx '>' --pane $pane | ignore
    $pane
}

# Type literal characters into a pane (no submit). Targets focused pane unless --pane.
export def type [ctx: record, text: string, --pane: string]: nothing -> nothing {
    mut args = [--session $ctx.session action write-chars $text]
    if $pane != null { $args = ($args | append [--pane-id $pane]) }
    zellij ...$args | ignore
}

# Send a named key chord (e.g. "Enter", "Esc", "Ctrl c", "Up") to a pane.
export def key [ctx: record, key: string, --pane: string]: nothing -> nothing {
    mut args = [--session $ctx.session action send-keys $key]
    if $pane != null { $args = ($args | append [--pane-id $pane]) }
    zellij ...$args | ignore
}

# Focus a pane so its grid becomes dumpable.
export def focus [ctx: record, pane: string]: nothing -> nothing {
    zellij --session $ctx.session action focus-pane-id $pane | ignore
}

# Dump a pane's rendered viewport text. Focuses it first (dump only sees a
# visible pane). Pass --full to include scrollback.
export def screen [ctx: record, --pane: string, --full]: nothing -> string {
    if $pane != null { focus $ctx $pane }
    mut args = [--session $ctx.session action dump-screen]
    if $full { $args = ($args | append "--full") }
    zellij ...$args
}

# Poll a pane's rendered text until it matches `pattern` (regex) or timeout.
# Returns the matching screen dump; errors with the last dump on timeout.
export def wait-text [
    ctx: record
    pattern: string
    --pane: string
    --timeout: duration = 8sec
    --poll: duration = 250ms
]: nothing -> any {
    let deadline = (date now) + $timeout
    mut last = ""
    while (date now) < $deadline {
        $last = (screen $ctx --pane $pane)
        if $last =~ $pattern { return $last }
        sleep $poll
    }
    error make { msg: $"wait-text timed out after ($timeout) waiting for /($pattern)/\n--- last screen ---\n($last)" }
}

# Clientless pane-state assertions: list-panes --json parsed into a table.
# Columns include: id, title, exited, exit_status, pane_command, is_floating,
# is_focused, tab_name, pane_cwd.
export def panes [ctx: record]: nothing -> table {
    zellij --session $ctx.session action list-panes --json | from json
}

# Poll tab-names until `name` appears (rename hooks fire async). Errors on timeout.
export def wait-tab [
    ctx: record
    name: string
    --timeout: duration = 6sec
    --poll: duration = 200ms
]: nothing -> any {
    let deadline = (date now) + $timeout
    mut last = []
    while (date now) < $deadline {
        $last = (tab-names $ctx)
        if $name in $last { return $last }
        sleep $poll
    }
    error make { msg: $"wait-tab timed out after ($timeout) waiting for tab '($name)'; have ($last)" }
}

# Open a new tab in the test session (panes spawned afterward land here).
export def new-tab [ctx: record]: nothing -> nothing {
    zellij --session $ctx.session action new-tab | ignore
}

# Poll a pane's running command (clientless) until it matches `pattern` (regex).
# `pane_command` reflects the foreground child (e.g. "hx +7 ..." while helix runs,
# back to "nu" once it exits) — a reliable, render-free readiness signal.
export def wait-pane-command [
    ctx: record
    pane: string
    pattern: string
    --timeout: duration = 8sec
    --poll: duration = 200ms
]: nothing -> any {
    let id = $pane | str replace 'terminal_' '' | into int
    let deadline = (date now) + $timeout
    mut last = ""
    while (date now) < $deadline {
        $last = (panes $ctx | where id == $id | get 0?.pane_command | default "")
        if $last =~ $pattern { return $last }
        sleep $poll
    }
    error make { msg: $"wait-pane-command timed out after ($timeout): pane ($pane) command '($last)' never matched /($pattern)/" }
}

# Current tab names for the test session (clientless).
export def tab-names [ctx: record]: nothing -> list<string> {
    zellij --session $ctx.session action query-tab-names | lines
}
