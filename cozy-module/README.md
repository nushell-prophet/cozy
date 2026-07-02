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

### `cozy git-harden`

Sets `gc.auto=0` and `receive.autoGc=false` in a repo's own `.git/config` so both the host and the sandbox git honor them, regardless of which side runs an operation. Mitigates pack/index corruption from VirtioFS torn writes when both sides hit `.git` on the shared mount at once.

```nushell
cozy git-harden                  # harden the repo in the current dir
cozy git-harden ~/workspace -a   # harden every git repo one level under the path
```

### `cozy configure claude-settings`

Merges default Claude settings (effortLevel, cleanupPeriodDays) into sandbox `~/.claude/settings.json`. Existing user values take precedence.

### `cozy sandbox-state export` / `cozy sandbox-state import`

Combined export/import of Nushell history, Claude Code project sessions, and the global `~/.claude/CLAUDE.md`.

```nushell
cozy sandbox-state export        # exports history + projects + global-claude
cozy sandbox-state import        # imports history + projects + global-claude
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

### `cozy sandbox-state global-claude export` / `import`

Copies the global `~/.claude/CLAUDE.md` to/from `$env.WORKSPACE_DIR/sandbox-state/`, so the agent's persistent instructions survive sandbox recreation. The combined `cozy sandbox-state export` / `import` runs this alongside history and projects.

### `cozy verify`

Runs the post-build checks against the sandbox you are inside: tools launch, expected files/dirs/env vars exist, and the nushell MCP, pbcopy, topiary, and git-XDG wiring is in place. Every expected value is derived from repo sources (`vendored-repos.nuon`, the autoload glob, `bootstrap.nu`), so the checklist can't drift from the build.

```nushell
cozy verify
```

The `cozy` module is autoloaded only in an interactive nushell session, so run this from an interactive shell or the nushell MCP `evaluate` tool — a one-shot `nu -c` skips autoloads and won't have `cozy`.

### `cozy install ...`

Installer subcommands used during image build or inside a running sandbox: `bootstrap`, `claude`, `topiary`, `nushell`, `polars`, `rust`, `zellij`, `nu-plugin-image`.

`bootstrap` is the single entry point that sets up the sandbox (or host) end-to-end — brew tools, XDG git config, vendored modules, dotfiles, Claude skills, broot, topiary, and Claude Code with the nushell MCP. Every install path reaches it through the shared `install/run-install.sh`.

## License

[MIT](LICENSE)
