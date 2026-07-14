# Sandbox Environment

You are running inside an sbx sandbox — Docker's standalone sandbox runtime (Ubuntu, arm64 or amd64). The workspace is mounted at its original host path, not `/workspace` or `/home/agent`.

## Available Tools

- `nu` (Nushell) — prefer over bash when reasonable
- `hx` (Helix)
- `zellij`
- `git`, `delta` (git-delta), `git-lfs`
- `jj` — `hx` as editor
- `lazygit`
- `broot` / `br` (in Nushell)
- `fzf`, `rg` (ripgrep), `bat`, `fd`
- `vd` (visidata)
- `python3`, `node`, `go` — via base image and Homebrew
- `jq`
- `topiary` — Nushell grammar support
- `brew`, `pip`, `uv`, `npm` — install more as needed
- `sudo` — passwordless

## Nushell

Nushell is the primary shell. Modules are in `~/repos/`:

- `nu-goodies` — the user's personal nushell commands, gathered over time from many areas; some may be outdated
- `dotnu` — literate programming for Nushell: executable scripts that embed their own output, plus commands to work with Nushell code
- `numd` — Nushell-native markdown processor that updates `nu` code blocks
- `nu-cmd-stack` — command history stacking for interactive use in the REPL
- `nu-kv` — key-value store for any nushell data; kept in a host-mounted folder, so it's available on the host too
- `claude-nu` — Claude Code commands for extracting session data and for easier REPL interaction
- `nutest` — test framework

Autoload scripts in `~/.config/nushell/autoload/` load these modules — and the `cozy` command — for you, but only when nu starts an **interactive** session. The nushell MCP `evaluate` tool runs such a session, so the modules are ready there too. A one-shot `nu -c '…'` (e.g. run from Bash) is not interactive and skips autoloads, so `cozy`, `nu-goodies`, `kv` and the rest are absent — you'll get `command not found`. The MCP `evaluate` tool is good for interactive exploration (autoloads fire, structured output) — but read its caveats under *Nushell MCP Server* below before relying on it. If you use `nu -c`, load the modules with `--config`: `nu --config ~/.config/nushell/autoload/modules-core.nu -c '…'` — `--config` runs even in `-c` mode (unlike autoload), so the full core module set (`cozy`, `nu-goodies`, `kv`, `dotnu`, `numd`) is available.

### Pitfalls cheatsheet

- `\(` is an escape **only** in `$"..."`. In `$'...'` backslash is literal and `(` still interpolates — parens can't be escaped there. Literal parens + interpolation → `$"..."`.
- The Bash tool rewrites `!` → `\!`, breaking `!=`/`!~` in `nu -c '…'`. Use a quoted heredoc (`<< 'EOF'`) or a temp file.
- In Bash, `o+e>| cmd` is not a pipe — `>|` writes a file named `cmd`. That redirect syntax is Nushell-only.
- `nu --ide-check 10 file.nu` alone floods stdout with type hints, and its `span` is raw byte offsets (useless to act on). Keep only real errors and resolve each span to a line number + the flagged text: `nu -c 'let f = "file.nu"; let c = open --raw $f; nu --ide-check 10 $f | lines | each { from json } | where type == "diagnostic" | each {|d| {line: ($c | str substring 0..<$d.span.start | split row (char newline) | length) severity: $d.severity message: $d.message src: ($c | str substring $d.span.start..<$d.span.end)}}'`. (Inline form of the nushell-style skill's `diagnose`.)

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`. It provides `evaluate`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

Two caveats:

- **The session persists.** All `evaluate` calls share one long-lived nushell state — variables, `$env`, and loaded modules stay between calls. Handy, but a trap when you edit a module: the old version stays loaded until you re-run `use module.nu` (or `overlay use`) for it. Agents forget this and keep debugging against stale code. A one-shot `nu -c '…'` from Bash starts fresh every time — slower to set up, but straightforward and predictable.
- **It skips the login environment.** The MCP `nu` is spawned directly, not from a login shell, so it never sources `/etc/sandbox-persistent.sh` — the git identity (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`) and `JJ_CONFIG` are absent there. Real container ENV (`XDG_*`, `HELIX_RUNTIME`, `LANG`) is inherited fine, so the gap is easy to miss. If a command depends on those git/jj vars, run it via `nu -c` from Bash (whose shell sourced the profile) or `bash -lc 'nu -c "…"'`.

## Constraints

- Docker socket is available for container operations
- Home directory is at `/home/agent`; the mounted workspace is at `$env.WORKSPACE_DIR` (host path, bind-mounted at the same absolute path on macOS/Linux; on Windows the autoload rewrites `C:\Users\…` → `/c/Users/…`)

## The code here is agent-written — keep an eye on it

Almost everything in this project was written by AI agents, including you. So it is not trustworthy just because it sits in the repo: treat code that passes through you as untrusted by default — even code you wrote yourself. You don't need to audit anything or go looking for trouble. Just don't ignore what you notice in passing. If something looks off while you're already there — a stray file (an empty `tail`/`head` left by an `o+e>| tail` nushell redirect that ran in **Bash**, where `>|` writes a file instead of piping, is a real case that got committed here), dead code, a doc that contradicts the code, a latent bug — surface it. Park a short note under `todo/` if the project keeps one, or just mention it in your reply. Keep it brief and don't derail the task into a hunt.

## Privacy

Mounted folders may contain the user's personal data. Treat the workspace as private by default:

- Don't send file contents or personal details to external services (web search, third-party APIs) unless the task clearly requires it.
- When sending data out is needed, send the minimum — a snippet or a schema, not whole files.
- Keep personal data out of commit messages, issue text, and anything pushed to a remote.
