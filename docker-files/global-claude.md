# Sandbox Environment

You are running inside a Docker sandbox (Ubuntu, arm64 or amd64). The workspace is mounted at its original macOS path, not `/workspace` or `/home/agent`.

## Available Tools

- `nu` (Nushell) — prefer over bash when reasonable
- `hx` (Helix) — Nushell as shell backend
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

- `nu-goodies` — data wrangling helpers
- `dotnu` — module management
- `numd` — Nushell-native markdown processor
- `nu-cmd-stack` — command history stacking
- `nu-kv` — key-value store
- `claude-nu` — Claude Code integration
- `nutest` — test framework
- `nu-multiproof` — multi-proof utilities

Use `use ~/repos/<module>/<module>` to load a module. Autoload scripts are in `~/.config/nushell/autoload/`.

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
