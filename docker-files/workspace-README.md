# You're inside a cozy sandbox

This file describes the environment **cozy** built around you — where things live and which config files it touched. It is not about the project mounted in this workspace. For cozy itself (build, install, full feature tour) see `~/repos/cozy/README.md`.

## `~/repos/` — downloaded modules

cozy ships a set of upstream modules *vendored* into `~/repos/` — committed in `cozy/vendor/` and copied in at build time, not fetched from the network. They are flat snapshots (no `.git`), so edit them in place freely. To pull upstream updates later without rebuilding the image, run `cozy sync-repos` — it turns these snapshots into git clones and fast-forwards each to the latest from GitHub. Load a Nushell module with `use ~/repos/<repo>/<module>`.

| Repo | What it gives you |
|---|---|
| `cozy` | The cozy module + installer + docker files (see below) |
| `nu-goodies` | Everyday Nushell helpers (`example`, `copy-out`, …) |
| `nu-kv` | Key-value store, autoloaded under the `kv` prefix |
| `nu-cmd-stack` | Command-history stacking |
| `numd` | Literate Markdown — `numd run <file>` |
| `dotnu` | Literate `.nu` — `dotnu embeds-update`, module tooling |
| `claude-nu` | Toolbox for Claude Code sessions (`claude-nu messages`, …) + tab-completions for the `claude` CLI |
| `nu-multiproof` | Multi-proof utilities |
| `nutest` | Test framework (not autoloaded: `use ~/repos/nutest/nutest`) |
| `topiary-nushell` | Nushell grammar for the topiary formatter |
| `dotfiles` | Source of every config deployed below |
| `my-claude-skills` | Claude Code skills |
| `nushell-skills` | Nushell-specific Claude Code skills |

## The `cozy` module

`~/repos/cozy/` is the project that built this environment. Its module (`cozy-module/`) is autoloaded, so `cozy` is a command:

| Command | Does |
|---|---|
| `cozy logo` | Print the cozy logo |
| `cozy install <tool>` | Build extras from source — `bootstrap` (full reinstall), `rust`, `nushell`, `zellij`, `topiary`, `polars`, `nu-plugin-image`, `claude` |
| `cozy sync-repos` | Convert the `~/repos/` snapshots to git clones and pull the latest from GitHub (updates the VM, no image rebuild) |
| `cozy dev-link` | Swap vendored `~/repos/` copies for symlinks to the mounted workspace (edit-and-test, no rebuild) |
| `cozy mount init` | Register the workspace's git subdirs as submodules |
| `cozy swap-zellij-super` | Rewrite Zellij's Super-key bindings (→ Alt/Ctrl) for Windows hosts |
| `cozy git-harden` | Apply safer git defaults |
| `cozy configure claude-settings` | Write Claude Code settings |
| `cozy sandbox-state export` / `import` | Snapshot/restore history + Claude sessions + global CLAUDE.md |
| `cozy sandbox-state history export` / `import` | Just the Nushell history |
| `cozy sandbox-state history seed` | Seed the Nushell history with useful commands from the bundled seed file |
| `cozy sandbox-state projects export` / `import` | Just Claude Code session files |
| `cozy sandbox-state global-claude export` / `import` | Just the global `~/.claude/CLAUDE.md` |

The rest of `~/repos/cozy/` holds the `Dockerfile`, the shared installer (`cozy-module/install/bootstrap.nu`), and `docker-files/` (autoload scripts, the appended Claude tool catalog).

## Config files cozy modified

Most come from `~/repos/dotfiles/`; a few Nushell autoload scripts come from cozy's own `docker-files/` (noted below). Edit them freely.

**Nushell** — `~/.config/nushell/`

- `config.nu`, `env.nu` — opinionated shell settings (from dotfiles)
- `autoload/*.nu` — loaded on every shell start. From cozy's `docker-files/`: `git-safe-directory.nu`, `mcp-server.nu`, `modules-core.nu`, `modules-repl.nu`, `my-nu-completions.nu`. From dotfiles: `br.nu`, `carapace-config.nu`, `hooks-config.nu`, `zzz_ignore_vars.nu`

**Other tools** — under `~/.config/`

| Path | Tool |
|---|---|
| `~/.config/helix/` | Helix editor |
| `~/.config/zellij/` | Zellij multiplexer |
| `~/.config/lazygit/` | Lazygit |
| `~/.config/broot/` | Broot file manager (+ `br` Nushell wrapper via `autoload/br.nu`) |
| `~/.config/jj/` | Jujutsu VCS |
| `~/.config/topiary/` | Topiary formatter (grammar + language config) |
| `~/.config/git/` | `config` + `ignore`, written in XDG so they survive sandbox restarts |
| `~/.config/visidata/` | VisiData (`config.py`) |

**Home & Claude**

- `~/.claude/CLAUDE.md` — cozy's tool catalog is appended here
- `~/.claude.json` — the vendored Nushell MCP server is registered (gives the agent `evaluate` / `list_commands` / `command_help`)
