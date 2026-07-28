export def main [] { }

# Install claude using official install script.
# Skipped when claude is already on PATH — e.g. inside `sbx run claude`,
# whose base image ships Claude Code pre-installed.
export def install [] {
    # Why `-a`: bootstrap.nu does `use claude.nu`, and this module's `main`
    # makes `claude` a custom command in that scope. Plain `which claude`
    # returns only the first match — that custom command — so the external
    # filter was always empty and this skip could never fire.
    let external = which -a claude | where type == external
    if ($external | is-not-empty) {
        print $"claude already installed at ($external | get path.0) — skipping install"
        return
    }
    # Not `curl … | bash` because: bash exits 0 on empty input, so a blocked
    # host or a proxy 403 made this step report success with no claude
    # installed, and the real failure surfaced one line later in bootstrap.nu
    # as a command-not-found for `claude mcp add`. Downloading to a file first
    # makes curl's own exit status the one that counts.
    let script = mktemp --tmpdir --suffix .sh
    curl -fsSL https://claude.ai/install.sh -o $script
    bash $script
    rm --force $script

    # `-a` for the same reason as above — without it this assert fired on every
    # build, whatever the installer did.
    if (which -a claude | where type == external | is-empty) {
        error make {msg: "the claude installer finished but `claude` is not on PATH — bootstrap Step 9 needs it for `claude mcp add`"}
    }
}
