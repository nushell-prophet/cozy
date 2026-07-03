---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - docker-files/nushell-autoload/modules-core.nu
  - docker-files/nushell-autoload/modules-repl.nu
  - docker-files/nushell-autoload/mcp-server.nu
  - docker-files/nushell-autoload/git-global-ignore.nu
  - docker-files/nushell-autoload/git-safe-directory.nu
  - docker-files/nushell-autoload/my-nu-completions.nu
  - docker-files/nushell-autoload/standard-aliases.nu
  - docker-files/global-claude.md
  - docker-files/pbcopy
  - docker-files/logo.ans
  - docker-files/workspace-README.md
reconciled-at: 6d0a0f617731076e7b387a47782c70cdfad0593b
---

# cozy autoload & shipped docker-files

The `docker-files/` bits that land in the running sandbox. `bootstrap.nu` Step 3.5 copies `docker-files/nushell-autoload/*.nu` → `~/.config/nushell/autoload/` (loaded on every shell start), Step 6 appends `global-claude.md` to `~/.claude/CLAUDE.md`, and the `pbcopy` shim is installed to `~/.local/bin` (on every Linux, just before Step 1). The `Dockerfile`'s final `COPY` places `workspace-README.md` at `~/workspace/README.md`. `logo.ans` stays in place and is read by `cozy logo` and the build MOTD.

Each entry records why the file ships — the self-healing or workaround it exists for. **Code** points at the file.

## Autoload scripts (`~/.config/nushell/autoload/`)

Nushell loads autoload scripts alphabetically; they're listed below in that order (`git-global-ignore` → `git-safe-directory` → `mcp-server` → `modules-core` → `modules-repl` → `my-nu-completions` → `standard-aliases`). The only ordering dependency is `modules-core` before `modules-repl` — alphabetical naming guarantees it, so the REPL-only modules can build on the core overlays.

### git-global-ignore.nu
Keep cozy's global gitignore patterns (`.DS_Store`, `Thumbs.db`, `desktop.ini`) active on shell start. Self-healing: `sbx` sets `core.excludesFile = ~/.gitignore_global` in `~/.gitconfig` on every create, which shadows git's XDG default (`~/.config/git/ignore`) where cozy wrote those patterns. git allows one excludesFile and `~/.gitconfig` wins over XDG, so cozy can't reclaim it — the autoload mirrors its canonical `~/.config/git/ignore` into whatever excludesFile resolves to, keeping sbx's `.sbx`. No-ops when excludesFile is unset (plain host reads the XDG default) or nothing is missing.
**Code:** `docker-files/nushell-autoload/git-global-ignore.nu`

### git-safe-directory.nu
Re-assert git `safe.directory = '*'` on shell start. Self-healing: sandbox creation overwrites the global setting with just the workspace-root path, so submodule repos beneath it trip "dubious ownership" under VirtioFS. Guarded so the normal path writes nothing.
**Code:** `docker-files/nushell-autoload/git-safe-directory.nu`

### mcp-server.nu
Ensure the nushell MCP server is registered in Claude Code user config. Self-healing: sandbox create may overwrite `~/.claude.json`, this restores the `mcpServers.nushell` stdio entry (`nu --mcp`).
> NOTE: registered in `~/.claude.json` (user scope), NOT `~/.claude/settings.json`.
**Code:** `docker-files/nushell-autoload/mcp-server.nu`

### modules-core.nu
Resolve `$env.WORKSPACE_DIR` to the in-VM mount path, then overlay the vendored `~/repos/` modules that must work in any context: nu-goodies, cozy, nu-kv, dotnu, numd. Sets `$env.kv.path` under the workspace sandbox-state dir when mounted. Windows hosts get `C:\Users\…` → `/c/Users/…` rewritten here. **Also loaded outside autoload:** non-interactive `nu --config ~/.config/nushell/autoload/modules-core.nu -c …` runs it (Helix's `shell`, agent `nu -c` from the Bash tool), because a one-shot `-c` skips autoload but honours `--config`. Everything here must stay safe in a one-shot `-c` — no prompt hooks, no REPL state.
**Code:** `docker-files/nushell-autoload/modules-core.nu` → `def resolve-workspace-mount`

### modules-repl.nu
Interactive-only module additions, `use`d on every interactive shell start: claude-nu, zellij's todo.nu, nu-cmd-stack. Split out from the core set so non-interactive `-c` consumers don't load session tools that have no meaning there.
**Code:** `docker-files/nushell-autoload/modules-repl.nu`

### my-nu-completions.nu
Custom completions for external tools — defines the `tte` extern with style-name completion.
**Code:** `docker-files/nushell-autoload/my-nu-completions.nu` → `export extern tte`

### standard-aliases.nu
Defines the `lg` → `lazygit` alias (the only alias in the file today).
**Code:** `docker-files/nushell-autoload/standard-aliases.nu` → `alias lg = lazygit`

## global-claude.md
The tool catalog appended to `~/.claude/CLAUDE.md` by `bootstrap.nu` Step 6. A markdown brief that tells the agent what cozy built around it: available tools (shell, editors, git, search, data/languages, formatting, package managers), where Nushell modules live, the registered Nushell MCP server and its two usage caveats (the `evaluate` session persists across calls, so edited modules stay stale until re-`use`d; the MCP `nu` skips the login shell, so the `/etc/sandbox-persistent.sh` git/jj exports are absent), sandbox constraints, and a privacy section.
**Code:** `docker-files/global-claude.md`

## pbcopy
Clipboard shim installed to `~/.local/bin/pbcopy` on every Linux, container or host, just before Step 1 — the dotfiles deployed in Step 4 call `pbcopy` and Linux has no native one; a user's own non-cozy `pbcopy` on PATH is never shadowed. Reads stdin and emits it as an OSC 52 terminal escape (`base64`-encoded) to `/dev/tty`, so copy-to-clipboard works over the terminal without a real pasteboard.
**Code:** `docker-files/pbcopy`

## logo.ans
The cozy ANSI logo asset. Read by `cozy logo` (anchored via `path self`) and by the build/MOTD line in `bootstrap.nu`. Not copied elsewhere — consumed in place from `~/repos/cozy/docker-files/logo.ans`.
**Code:** `docker-files/logo.ans`

## workspace-README.md
The "You're inside a cozy sandbox" orientation page, placed at `~/workspace/README.md` by the `Dockerfile`'s final `COPY` (not by `bootstrap.nu`). Describes the environment — the vendored `~/repos/` modules, the `cozy` command surface, and every config file cozy touched — for whoever opens the workspace. Points at `~/repos/cozy/README.md` for the full tour.
**Code:** `docker-files/workspace-README.md`
