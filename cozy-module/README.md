# cozy-module

Runtime toolkit for [cozy](https://github.com/nushell-prophet/cozy) sandboxes.
Loaded as the `cozy` overlay inside the container.

Maintains running sandboxes without rebuilding — updates modules, syncs repos, and persists shell history.

## Commands

### `cozy sync-repos`

Turns the vendored `~/repos/` snapshots into full git clones of upstream on the first run, then keeps already-cloned repos current — non-destructively.
These are yours to develop in and PR upstream from, so a re-run never touches local work: it fetches always, and fast-forwards a repo only when its tree is clean and the branch hasn't diverged.
Dev-linked repos (see `cozy dev-link`) are skipped.

```nushell
cozy sync-repos
```

### `cozy mount init`

Idempotent initialization of multi-repo workspaces.
Discovers git subdirectories, registers them as git submodules, generates `.gitmodules` and `.gitignore`.
Safe to re-run after adding new directories.

```nushell
cozy mount init
```

### `cozy dev-link`

Replaces vendored `~/repos/` copies with symlinks to the mounted workspace.
Enables edit-and-test without rebuild.

```nushell
cozy dev-link
```

### `cozy swap-zellij-super`

Rewrites `~/.config/zellij/config.kdl` in place to remove the Super modifier (Super+Shift→Alt+Shift, Super+Alt→Ctrl+Alt, Super→Alt).
Intended for Windows hosts, where Win+key is reserved by the OS and the default Super-based bindings collide.
Idempotent.

```nushell
cozy swap-zellij-super
```

### `cozy use-host-ssh-agent`

Shows whether this shell can reach the host ssh-agent that `container.nu up --ssh-agent` forwards, and switches it.
Off in every new shell by default: parallel clients of the forwarded socket lose their answers and hang, and the container's terminal can freeze with them.
Enable it in the pane that signs, for as long as it signs.

```nushell
cozy use-host-ssh-agent            # status
cozy use-host-ssh-agent --enable   # this shell and its children may sign with the host's keys
cozy use-host-ssh-agent --disable  # back to the default
```

### `cozy git-harden`

Sets `gc.auto=0` and `receive.autoGc=false` in a repo's own `.git/config` so both the host and the sandbox git honor them, regardless of which side runs an operation.
Mitigates pack/index corruption from VirtioFS torn writes when both sides hit `.git` on the shared mount at once.

```nushell
cozy git-harden                  # harden the repo in the current dir
cozy git-harden ~/workspace -a   # harden every git repo one level under the path
```

### `cozy configure claude-settings`

Merges default Claude settings (effortLevel, cleanupPeriodDays) into sandbox `~/.claude/settings.json`.
Existing user values take precedence.

### `cozy sandbox-state snapshot` / `cozy sandbox-state restore`

Combined snapshot/restore of Nushell history, Claude Code project sessions, and the global `~/.claude/CLAUDE.md`.

```nushell
cozy sandbox-state snapshot      # snapshots history + projects + global-claude
cozy sandbox-state restore       # restores history + projects + global-claude
```

### `cozy sandbox-state history snapshot` / `restore`

Snapshots Nushell's SQLite history database to a timestamped `.nuon` file, or restores records back.
Deduplicates and skips entries already present.

```nushell
cozy sandbox-state history snapshot                  # default: $env.WORKSPACE_DIR/sandbox-state/history-<timestamp>.nuon
cozy sandbox-state history restore                   # from latest snapshot
```

### `cozy sandbox-state history seed`

Seeds history from the bundled `history-seed.nuon` file.

### `cozy sandbox-state projects snapshot` / `restore`

Copies Claude Code project sessions (`~/.claude/projects/`) to/from `$env.WORKSPACE_DIR/sandbox-state/projects/`.
The workspace directory survives sandbox recreation.

### `cozy sandbox-state global-claude snapshot` / `restore`

Copies the global `~/.claude/CLAUDE.md` to/from `$env.WORKSPACE_DIR/sandbox-state/`, so the agent's persistent instructions survive sandbox recreation.
The combined `cozy sandbox-state snapshot` / `restore` runs this alongside history and projects.

### `cozy sandbox-state file-history snapshot`

Commits any file into `$env.WORKSPACE_DIR/sandbox-state/file-history/`, a git repo, so its versions survive sandbox recreation and can be diffed against each other.
The path inside the repo is the file's own absolute path with the leading `/` dropped — `/Users/user/.config/helix/config.toml` lands at `Users/user/.config/helix/config.toml`.

```nushell
cozy sandbox-state file-history snapshot ~/.config/helix/config.toml   # add or update one file
cozy sandbox-state file-history snapshot                              # refresh every file already tracked
cozy fhs ~/.config/helix/config.toml ~/.config/nushell/env.nu         # same thing, short, several at once
cozy fhs ...(glob ~/.claude/*.md)                                     # a glob has to be spread
```

Several paths at once are checked before anything is committed, so a typo in the last argument leaves the earlier ones uncommitted, and the error names every path that was not found.
A bare `*.md` arrives as that literal string — nushell expands globs only for external commands — hence the `...(glob ...)` spread.

`cozy fhs` is an alias for the same command, and completion shows it with the full name spelled out.

The repo is its own registry: a file added once is picked up by every later bare `snapshot`.
Unchanged bytes produce no commit, so re-running costs nothing.
Read the history with `git -C ($env.WORKSPACE_DIR | path join sandbox-state file-history) log --patch`.

### `cozy verify`

Runs the post-build checks against the sandbox you are inside: tools launch, expected files/dirs/env vars exist, the nushell MCP, pbcopy, topiary, and git-XDG wiring is in place, and — the only checks that touch the network — that `api.anthropic.com` is not intercepted and that an egress allowlist is in force.
Every expected value is derived from repo sources (`vendored-repos.nuon`, the autoload glob, `bootstrap.nu`), so the checklist can't drift from the build.

```nushell
cozy verify
```

The `cozy` module is autoloaded only in an interactive nushell session, so run this from an interactive shell or the nushell MCP `evaluate` tool — a one-shot `nu -c` skips autoloads and won't have `cozy` unless you load it explicitly (`nu --config ~/.config/nushell/autoload/modules-core.nu -c 'cozy verify'`).

### `cozy docs claude` / `cozy docs nushell`

Fetches reference docs into a local folder for offline / in-sandbox use.
`claude` downloads the Claude Code doc pages listed in the sitemap (in parallel); `nushell` makes a shallow sparse checkout of the Nushell docs (book, cookbook, blog) and re-runs as a `git pull`.
Both fetch with curl — `http get` doesn't work through the sandbox proxy — and return a structured summary.
Output dirs (`claude-code-docs/`, `nushell-docs/`, overridable with `--output-dir`) are generated content; refetch anytime.

```nushell
cozy docs claude      # -> ./claude-code-docs/
cozy docs nushell     # -> ./nushell-docs/
```

### `cozy logo`

Prints the cozy ANSI logo banner (the same one bash login shows).

### `cozy nu-demo-instance`

Puts a launch line for a bare, throwaway Nushell into the REPL prompt instead of spawning it — so during a demo the audience sees the actual code, it lands in history, and it can be edited before running.
The line points `XDG_CONFIG_HOME` and `XDG_DATA_HOME` at empty temp dirs, scoped with `with-env` so nothing leaks into the calling session.
`--here` uses `./nushell/` in the current directory as the config dir instead, creating empty `config.nu`/`env.nu` so they can be edited live.

```nushell
cozy nu-demo-instance
cozy nu-demo-instance --here
```

### `cozy install ...`

Installer subcommands used during image build or inside a running sandbox: `bootstrap`, `claude`, `topiary`, `nushell`, `polars`, `rust`, `zellij`, `nu-plugin-image`.

`bootstrap` is the single entry point that sets up the sandbox (or host) end-to-end — brew tools, XDG git config, vendored modules, dotfiles, Claude skills, broot, topiary, and Claude Code with the nushell MCP.
Every install path reaches it through the shared `install/run-install.sh`.

## License

[MIT](LICENSE)
