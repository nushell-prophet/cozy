# Sandbox Environment

You are running inside a Docker sandbox (Ubuntu, arm64 or amd64). The workspace is mounted at its original macOS path, not `/workspace` or `/home/agent`.

## Available Tools

### Shell & Editors
- **Nushell** (`nu`) — structured-data shell with pipelines, tables, and closures
- **Helix** (`hx`) — modal editor, configured with Nushell as shell backend
- **Zellij** — terminal multiplexer

### Git
- **git** + **git-delta** (`delta`) — syntax-highlighted diffs; **git-lfs** available
- **jj** — Jujutsu VCS, configured with `hx` as editor
- **Lazygit** — TUI for git

### File Navigation & Search
- **Broot** (`broot`, `br` in Nushell) — tree file manager
- **fzf** — fuzzy finder
- **ripgrep** (`rg`) — fast grep
- **bat** — syntax-highlighted file viewer

### Data & Languages
- **visidata** (`vd`) — terminal spreadsheet for CSV, JSON, SQLite, etc.
- **Python 3**, **Node.js**, **Go** — available via base image and Homebrew
- **jq** — JSON processor

### Code Formatting
- **topiary** — universal code formatter with Nushell grammar support

### Package Managers
- **brew**, **pip**, **uv**, **npm** — install additional packages as needed
- **sudo** — passwordless

## Nushell

Nushell is the primary shell. Modules are in `~/repos/`:

- `nu-goodies` — data wrangling helpers
- `dotnu` — module management
- `numd` — Nushell-native markdown processor
- `nu-cmd-stack` — command history stacking
- `nu-kv` — key-value store
- `claude-nu` — Claude Code integration
- `nutest` — test framework

Use `use ~/repos/<module>/<module>` to load a module. Autoload scripts are in `~/.config/nushell/autoload/`.

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`. It provides `eval`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

## Constraints

- Docker socket is available for container operations
- Home directory is at `/home/agent`; symlink `~/workspace/mounted` points to the workspace
