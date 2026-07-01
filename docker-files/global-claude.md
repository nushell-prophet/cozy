# Sandbox Environment

You are running inside an sbx sandbox — Docker's standalone sandbox runtime (Ubuntu, arm64 or amd64). The workspace is mounted at its original macOS path, not `/workspace` or `/home/agent`.

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
- `nu-multiproof` — multi-proof utilities to timestamp and sign git repo contents

Autoload scripts in `~/.config/nushell/autoload/` load these modules — and the `cozy` command — for you, but only when nu starts an **interactive** session. The nushell MCP `evaluate` tool runs such a session, so the modules are ready there too. A one-shot `nu -c '…'` (e.g. run from Bash) is not interactive and skips autoloads, so `cozy`, `nu-goodies`, `kv` and the rest are absent — you'll get `command not found`. Prefer the MCP `evaluate` tool for nushell. If you must use `nu -c`, load the modules with `--config`: `nu --config ~/.config/nushell/autoload/modules-core.nu -c '…'` — `--config` runs even in `-c` mode (unlike autoload), so the full core module set (`cozy`, `nu-goodies`, `kv`, `dotnu`, `numd`) is available.

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`. It provides `evaluate`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

## Constraints

- Docker socket is available for container operations
- Home directory is at `/home/agent`; the mounted workspace is at `$env.WORKSPACE_DIR` (host path, bind-mounted at the same absolute path on macOS/Linux; on Windows the autoload rewrites `C:\Users\…` → `/c/Users/…`)

## Privacy

Mounted folders may contain the user's personal data. Treat the workspace as private by default:

- Don't send file contents or personal details to external services (web search, third-party APIs) unless the task clearly requires it.
- When sending data out is needed, send the minimum — a snippet or a schema, not whole files.
- Keep personal data out of commit messages, issue text, and anything pushed to a remote.
