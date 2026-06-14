---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-spec reconciles this file against
  - cozy-module/mod.nu
  - cozy-module/sync-repos.nu
  - cozy-module/mount.nu
  - cozy-module/dev-link.nu
  - cozy-module/git-harden.nu
  - cozy-module/swap-zellij-super.nu
  - cozy-module/configure/mod.nu
  - cozy-module/logo.nu
  - cozy-module/sandbox-state/
---

# cozy command surface

The `cozy` command, available inside a running sandbox (the module is autoloaded from `~/repos/cozy/cozy-module/`). Exports are wired in `../cozy-module/mod.nu`. The `install` sub-surface lives in its own file: `install.md`.

Each entry: **Purpose** is the first line of the command's own doc comment (verbatim). **Flags** are derived from the signature. **Code** points at the symbol; the full rationale stays there.

## cozy sync-repos
Convert vendor directories to git repos if needed, pull latest from all.
**Flags:** `--force (-f)`
**Code:** `cozy-module/sync-repos.nu` → `export def main`

## cozy mount init
Idempotent git init for multi-repo workspaces. Registers git subdirs as submodules, ignores non-git subdirs.
**Code:** `cozy-module/mount.nu` → `export def init`

## cozy dev-link
Replace vendored `~/repos/` copies with symlinks to the mounted workspace — edit-and-test without rebuild.
**Flags:** `--workspace (-w): path` — defaults to `$env.WORKSPACE_DIR`
**Code:** `cozy-module/dev-link.nu` → `export def main`

## cozy git-harden
Harden a git repo against concurrent-access corruption on a shared mount (sets `gc.auto=0`, `receive.autoGc=false` in the repo's own `.git/config`).
**Flags:** `--all (-a)` — harden every git repo in immediate subdirs; positional `path` (default `.`)
**Code:** `cozy-module/git-harden.nu` → `export def main`

## cozy swap-zellij-super
For Windows hosts: swap the Super modifier out of `~/.config/zellij/config.kdl`.
**Code:** `cozy-module/swap-zellij-super.nu` → `export def main`

## cozy configure claude-settings
Merge default settings into `~/.claude/settings.json` (existing user values win).
**Code:** `cozy-module/configure/mod.nu` → `export def --env claude-settings`

## cozy logo
Prints the cozy ANSI logo.
**Code:** `cozy-module/logo.nu` → `export def main`

## cozy sandbox-state

Export/import nushell history, Claude Code sessions, and global CLAUDE.md across sandbox recreation. The workspace mount survives recreation, so state round-trips through `$env.WORKSPACE_DIR/sandbox-state/`. Wired in `../cozy-module/sandbox-state/mod.nu`.

### cozy sandbox-state export / import
Export (or import) all three state kinds at once — runs the per-kind export/import below.
**Code:** `cozy-module/sandbox-state/mod.nu` → `export def export`, `export def import`

### cozy sandbox-state history export / import / seed
Nushell SQLite history ↔ timestamped `history-*.nuon` in sandbox-state. `seed` loads the bundled `history-seed.nuon`.
**Flags:** `export`/`import` take optional `path?: path`
**Code:** `cozy-module/sandbox-state/history.nu` → `export def export`, `import`, `seed`

### cozy sandbox-state projects export / import
Copies `~/.claude/projects/` ↔ sandbox-state. Import skips sessions whose UUID already exists (no overwrite).
**Flags:** optional `path?: path`
**Code:** `cozy-module/sandbox-state/projects.nu` → `export def export`, `import`

### cozy sandbox-state global-claude export / import
`~/.claude/CLAUDE.md` ↔ timestamped `global-claude-*.md`. Import picks the most recent by name and overwrites the current file.
**Flags:** optional `path?: path`
**Code:** `cozy-module/sandbox-state/global-claude.nu` → `export def export`, `import`
