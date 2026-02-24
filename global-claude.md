# Sandbox Environment

You are running inside a Docker sandbox (Ubuntu, aarch64). The workspace is mounted at its original macOS path, not `/workspace` or `/home/agent`.

## Available Tools

### Shell & Editors
- **Nushell** (`nu`) — structured-data shell with pipelines, tables, and closures
- **Helix** (`hx`) — modal editor, configured with Nushell as shell backend
- **Zellij** — terminal multiplexer

### Git
- **git** + **git-delta** (`delta`) — syntax-highlighted diffs
- **jj** — Jujutsu VCS, configured with `hx` as editor
- **Lazygit** — TUI for git
- **gh** — GitHub CLI

### File Navigation & Search
- **Broot** (`broot`, `br` in Nushell) — tree file manager
- **fzf** — fuzzy finder
- **ripgrep** (`rg`) — fast grep

### Data & Languages
- **visidata** (`vd`) — terminal spreadsheet for CSV, JSON, SQLite, etc.
- **Python 3**, **Node.js**, **Go** — available via base image and Homebrew
- **jq** — JSON processor
- **Carapace** — multi-shell completion engine

### Package Managers
- **brew**, **pip**, **uv**, **npm** — install additional packages as needed
- **sudo** — passwordless

## Nushell

Nushell is the primary shell. Modules are in `~/git/`:

- `nu-goodies` — data wrangling helpers
- `dotnu` — module management
- `numd` — Nushell-native markdown processor
- `nu-cmd-stack` — command history stacking
- `nushell-kv` — key-value store
- `claude-nu` — Claude Code integration

Use `use ~/git/<module>/<module>` to load a module. Autoload scripts are in `~/.config/nushell/autoload/`.

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`. It provides `eval`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

## Constraints

- Outbound network is firewalled — request domain access if needed
- Docker socket is available for container operations
- Home directory is at `/home/agent`; symlink `~/mounted` points to the workspace
