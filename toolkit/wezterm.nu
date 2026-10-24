# Open a new WezTerm window and attach it to a zellij session inside a sandbox.
#
# The only thing that differs between the two run paths is how you get a shell
# inside — `sbx exec --interactive --tty NAME` vs
# `container exec --interactive --tty [--cwd W] NAME` — so the
# caller passes that prefix and everything else lives here once. Used by
# toolkit/sbxw.nu (sbx) and toolkit/container.nu (Apple `container`).
#
# Named for the window, not the job: nushell refuses to export a command named
# like its own module, and `attach-window` is the name worth keeping at the
# call sites.

const default_conf = path self ../vendor/dotfiles/wezterm/wezterm.lua

export def "nu-complete wezterm background" []: nothing -> table<value: string, description: string> {
    [
        {value: "000000" description: "black (sandbox default)"}
        {value: "0d0d0d" description: "near-black"}
        {value: "0a0e27" description: "deep navy (host default)"}
    ]
}

export def "nu-complete wezterm size" []: nothing -> table<value: string, description: string> {
    [
        {value: "100x30" description: "small"}
        {value: "120x30" description: "laptop"}
        {value: "140x40" description: "medium"}
        {value: "180x44" description: "large"}
        {value: "80x24" description: "classic terminal, good for a recording"}
    ]
}

# The WezTerm flags for a window size given as COLSxROWS; none without a size,
# so the config file's initial_cols/initial_rows apply.
# Why apart from attach-window: `container attach` may restart the cage before
# it opens the window, and a typo in --size has to fail before that restart.
export def size-flags [size?: string]: nothing -> list<string> {
    if $size == null { return [] }

    let dims = $size | parse --regex '^(?<cols>[1-9]\d*)x(?<rows>[1-9]\d*)$'

    if ($dims | is-empty) {
        error make --unspanned {
            msg: $"--size ($size) is not COLSxROWS"
            help: "give columns and rows joined by an x, e.g. --size 140x40"
        }
    }
    [--config $'initial_cols=($dims.0.cols)' --config $'initial_rows=($dims.0.rows)']
}

export def attach-window [
    exec_argv: list<string> # how to get a shell inside, e.g. [sbx exec --interactive --tty my-box]
    session: string # zellij session to attach to, created if missing
    --config-file: path # WezTerm config (default: the vendored dotfiles wezterm.lua)
    --background: string@"nu-complete wezterm background" = "000000" # hex without '#'
    --no-job # don't create a background job for the process
    --record: path # save the session as an asciicast into this directory, one new file per call; don't resize the window, the recorder keeps its start size
    --size-flags: list<string> = [] # the window size, as `size-flags` returns it
]: nothing -> any {
    # the spawned job's id, so `job kill` can reach it; nothing with --no-job
    let conf = $config_file
        | default $default_conf

    # Why: set the background via --config at window creation rather than the
    # OSC user-var trick, which applies it only after the shell starts and
    # briefly flashes the config-file default first.
    # Why `wezterm record` gets the same flags: it is a process of its own that
    # reads the host config otherwise, and writes that config's colors into the
    # cast header, so a player shows the cast on the wrong background.
    let wezterm_config = [
        --config-file $conf
        --config $'colors={background="#($background)"}'
        ...$size_flags
    ]

    # Why `wezterm record` around the exec: it wraps the very command the window
    # already runs, so the cast is written on the host and needs no recorder
    # installed anywhere. It reads the tty size once and never handles SIGWINCH
    # (upstream wezterm/src/asciicast.rs), so a resize leaves zellij at the old size.
    # `-o` has no long form; `--` keeps `--interactive --tty` of the exec from parsing as its flags.
    # Why a directory, not a file: `-o` truncates an existing file, so a name
    # made per call keeps every recording.
    let cast = if $record != null {
        mkdir $record
        $record
        | path expand
        | path join $'($session)-(date now | format date "%Y%m%d-%H%M%S").cast'
    }

    if $cast != null { print $'recording to ($cast)' }

    let launch = [
        ...(if $cast != null { [wezterm ...$wezterm_config record -o $cast --] })
        ...$exec_argv
        nu --login --execute $'zellij attach --create ($session)'
    ]

    # Why: a `job spawn`ed process dies with the nu that spawned it, so a
    # one-shot `nu toolkit/container.nu attach NAME` exits before the window is
    # up and nothing ever appears — silently. Say so here, where the contract
    # breaks, instead of leaving the caller wondering.
    if not ($nu.is-interactive or $no_job) {
        error make --unspanned {
            msg: "the WezTerm window is spawned as a background job, and a job dies when the nu that spawned it exits — run as a one-shot script, it would leave no window"
            help: "run it from an interactive nu: `use toolkit; toolkit container attach <name>` (or `toolkit sbxw <name>`). Pass --no-job to run wezterm in the foreground of this shell instead — it blocks until the window closes."
        }
    }

    let closure = {
        ^wezterm ...$wezterm_config start --always-new-process -- ...$launch
    }

    if $no_job { do $closure } else { job spawn $closure }
}
