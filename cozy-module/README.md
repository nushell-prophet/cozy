# cozy-module

Runtime toolkit for [cozy](https://github.com/nushell-prophet/cozy) sandboxes. Loaded as the `cozy` overlay inside the container.

Maintains running sandboxes without rebuilding — updates modules, syncs repos, and persists shell history.

## Commands

### `cozy sync-repos`

Pulls the latest changes for all repos under `~/repos/`. Handles branch switching, dirty working tree detection, and converting vendored directories to proper git repos.

```nushell
cozy sync-repos       # skip repos with local changes
cozy sync-repos -f    # force: discard local changes and switch branches
```

### `cozy mount init`

Idempotent initialization of multi-repo workspaces. Discovers git subdirectories, registers them as git submodules, generates `.gitmodules` and `.gitignore`. Safe to re-run after adding new directories.

```nushell
cozy mount init
```

### `cozy dev-link`

Replaces vendored `~/repos/` copies with symlinks to the mounted workspace. Enables edit-and-test without rebuild.

```nushell
cozy dev-link
```

### `cozy swap-zellij-super`

Rewrites `~/.config/zellij/config.kdl` in place to remove the Super modifier (Super+Shift→Alt+Shift, Super+Alt→Ctrl+Alt, Super→Alt). Intended for Windows hosts, where Win+key is reserved by the OS and the default Super-based bindings collide. Idempotent.

```nushell
cozy swap-zellij-super
```

### `cozy configure claude-settings`

Merges default Claude settings (effortLevel, cleanupPeriodDays) into sandbox `~/.claude/settings.json`. Existing user values take precedence.

### `cozy sandbox-state export` / `cozy sandbox-state import`

Combined export/import of both Nushell history and Claude Code project sessions.

```nushell
cozy sandbox-state export        # exports history + projects
cozy sandbox-state import        # imports history + projects
```

### `cozy sandbox-state history export` / `import`

Exports Nushell's SQLite history database to a timestamped `.nuon` file, or imports records back. Deduplicates and skips entries already present.

```nushell
cozy sandbox-state history export                    # default: $env.WORKSPACE_DIR/sandbox-state/history-<timestamp>.nuon
cozy sandbox-state history import                    # from latest export
```

### `cozy sandbox-state history seed`

Seeds history from the bundled `history-seed.nuon` file.

### `cozy sandbox-state projects export` / `import`

Copies Claude Code project sessions (`~/.claude/projects/`) to/from `$env.WORKSPACE_DIR/sandbox-state/projects/`. The workspace directory survives sandbox recreation.

### `cozy install ...`

Installer subcommands used during image build or inside a running sandbox: `bootstrap`, `claude`, `topiary`, `nushell`, `polars`, `rust`, `zellij`, `nu-plugin-image`.

`bootstrap` is the single entry point that sets up the sandbox (or host) end-to-end — brew tools, XDG git config, vendored modules, dotfiles, Claude skills, broot, topiary, and Claude Code with the nushell MCP. Same code path is used by the Dockerfile and by `bootstrap.sh` on the host.

## License

[MIT](LICENSE)
