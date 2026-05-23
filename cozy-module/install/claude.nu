export def main [] { }

# Install claude using official install script.
# Skipped when claude is already on PATH — e.g. inside `sbx run claude`,
# whose base image ships Claude Code pre-installed.
export def install [] {
    let external = which claude | where type == external
    if ($external | is-not-empty) {
        print $"claude already installed at ($external | get path.0) — skipping install"
        return
    }
    curl -fsSL https://claude.ai/install.sh | bash
}
