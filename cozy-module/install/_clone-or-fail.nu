# Wraps `git clone` with GIT_TERMINAL_PROMPT=0 so a 404 over HTTPS
# (deleted/renamed account, private repo) fails immediately instead of
# hanging on git's "Username for ..." credential prompt.
export def main [
    url: string
    dest: string
    ...args: string # extra flags forwarded to git clone
]: nothing -> nothing {
    with-env {GIT_TERMINAL_PROMPT: "0"} {
        try { ^git clone $url $dest ...$args } catch {
            error make {msg: $"git clone failed: ($url)\n  Repo may be missing, renamed, or private. Verify the URL and update this install script if upstream moved."}
        }
    }
}
