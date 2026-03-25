# sandbox-toolkit

Runtime toolkit for [cozy](https://github.com/nushell-prophet/cozy) sandboxes. Loaded as the `cozy` overlay inside the container.

Maintains running sandboxes without rebuilding — updates modules, syncs repos, and persists shell history.

## Commands

### `cozy sync-repos`

Pulls the latest changes for all Nushell module repos under `~/repos/` (including the cozy repo itself). Handles branch switching, dirty working tree detection, and converting vendored directories to proper git repos.

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

### `cozy platform` / `cozy platform apply`

Detects the host platform from the workspace mount path. `apply` transforms configs for the detected (or given) platform — currently remaps Zellij Super keybindings to Alt for Windows.

```nushell
cozy platform                    # detect: macos, windows, or linux
cozy platform apply windows      # apply Windows keybinding transforms
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
cozy sandbox-state history export                    # default: ~/workspace/mounted/sandbox-state/history-<timestamp>.nuon
cozy sandbox-state history import                    # from latest export
```

### `cozy sandbox-state history seed`

Seeds history from the bundled `history-seed.nuon` file.

### `cozy sandbox-state projects export` / `import`

Copies Claude Code project sessions (`~/.claude/projects/`) to/from `~/workspace/mounted/sandbox-state/projects/`. The mounted directory survives sandbox recreation.

### `cozy install ...`

Installer subcommands used during image build: `topiary`, `nushell`, `polars`, `rust`, `zellij`, `nu-plugin-image`.

## License

[MIT](LICENSE)
