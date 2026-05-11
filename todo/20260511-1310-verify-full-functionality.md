---
task-name: verify-full-functionality
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify full cozy sandbox functionality (main Docker path)

## Task from user (original)

we are inside of a freshly built docker sandbox, where I just restored projects and nushell history.

write a full-functionality todo case with all the previous features, which were existed before our changes (and including our changes).

reuse our testing functionality where possible. In case of doubts - ask what I want.

the main docker path - what is what we testing now.

add a section for a user to check (that isn't possible to check by agent)

## Context

We are running inside a freshly built `cozy:v1` sandbox launched via `docker sandbox create`. The user has restored:

- `~/repos/` projects (the vendored module sources)
- Nushell history (via `cozy sandbox-state history import` or equivalent)

Goal: walk the full surface that cozy ships, both pre-existing features and the changes introduced after `288a2c9` (bootstrap.nu extraction, ensure-nu fallback, vendor.nu fail-fast, auto-detection). Confirm parity with the pre-extraction Dockerfile and that nothing regressed.

## Reuse map (run these alongside this todo)

- `todo/20260511-1258-verify-docker-build.md` — Dockerfile collapse + first-run sandbox artifacts. Most of its checklist applies as-is here.
- `todo/20260511-1258-verify-sandbox-rerun.md` — re-run `cozy install bootstrap` inside this sandbox to confirm idempotent-on-re-run behavior (nushell wipe, apt proxy timing).
- `todo/20260511-1258-verify-vendor-failfast.md` — synthetic edge-case (skip unless you want to corrupt `vendor.yml` here).
- `todo/20260511-1258-verify-ensure-nu-fallback.md` — synthetic edge-case (skip unless you want to corrupt `bootstrap.nu` here).
- `todo/20260511-1258-verify-host-bootstrap.md` — not applicable; host path, not Docker.

## Agent-checkable verification

### A. Brew tools on PATH

- [ ] `which nu hx lazygit zellij broot delta jj git-lfs vd bat topiary fd fzf` all resolve under `/home/linuxbrew/.linuxbrew/bin/`
- [ ] `nu --version` reports a version `nu -c "use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu"` parses cleanly
- [ ] `hx --version`, `lazygit --version`, `zellij --version`, `broot --version`, `delta --version`, `jj --version`, `vd --version`, `bat --version`, `topiary --version`, `fd --version`, `fzf --version` all exit 0

### B. Vendored modules under `~/repos/`

Per `cozy/toolkit/vendor.yml`. Each `use` must succeed; smoke command verifies non-trivial functionality.

- [ ] `~/repos/nu-goodies/` — `use ~/repos/nu-goodies/nu-goodies *; ls | first 3 | arrange [name]` produces a table
- [ ] `~/repos/nu-kv/` — `use ~/repos/nu-kv/kv; kv list` exits 0 (may be empty)
- [ ] `~/repos/dotnu/` — `use ~/repos/dotnu/dotnu` succeeds, exposes `dotnu` command
- [ ] `~/repos/numd/` — `use ~/repos/numd/numd` succeeds; `numd --help` runs
- [ ] `~/repos/claude-nu/` — `use ~/repos/claude-nu/claude-nu` succeeds
- [ ] `~/repos/nu-cmd-stack/` — `use ~/repos/nu-cmd-stack/cmd-stack` succeeds
- [ ] `~/repos/nutest/` — `use ~/repos/nutest/nutest; nutest --help` runs
- [ ] `~/repos/nu-multiproof/` — `use ~/repos/nu-multiproof/nu-multiproof` succeeds
- [ ] `~/repos/topiary-nushell/` — `queries/`, `languages.ncl` present; `topiary format --language nu <some.nu>` works
- [ ] `~/repos/dotfiles/` — `toolkit.nu`, `paths-docker.csv` present, all module subdirs present (broot, claude, helix, jj, lazygit, nushell, zellij, wezterm)
- [ ] `~/repos/my-claude-skills/` — source available (skills are deployed separately into `~/.claude/skills/`)
- [ ] `~/repos/nushell-skills/` — source available
- [ ] `~/repos/cozy/sandbox-toolkit/` and `~/repos/cozy/docker-files/` present (and only these — vendor/, docs.docker.com/, .git/ not mirrored on host install; on Docker the COPY put them at `/home/agent/repos/cozy/`)

### C. `cozy` command surface (sandbox-toolkit/mod.nu exports)

- [ ] `use ~/repos/cozy/sandbox-toolkit/` exposes: `sync-repos mount platform sandbox-state dev-link install configure git-harden`
- [ ] `cozy platform` reports correct arch/OS
- [ ] `cozy install bootstrap --help` (or `nu -c '...; bootstrap --help'`) runs — confirms bootstrap is wired into `install/mod.nu`
- [ ] `cozy sync-repos --help` runs (no execution)
- [ ] `cozy mount --help` runs
- [ ] `cozy sandbox-state history --help` runs (the command the user used to restore history)
- [ ] `cozy git-harden --help` runs

### D. Nushell autoload scripts

Files at `~/.config/nushell/autoload/`:

- [ ] `br.nu` — `br` (broot wrapper) defined and callable in nu
- [ ] `carapace-config.nu` — completions wire-up loads without error
- [ ] `hooks-config.nu` — env_change hooks set
- [ ] `mcp-server.nu` — `nu --mcp` flag handler present (don't actually start it; verify the script loads)
- [ ] `module-imports.nu` — auto-imports from `~/repos/` modules into top-level scope (e.g. `arrange` from nu-goodies is available without explicit `use`)
- [ ] `my-nu-completions.nu` — custom completions registered (e.g. for `git`, `jj`)
- [ ] `standard-aliasses.nu` — common aliases defined (check a couple: `ll`, `..`, or whatever's in there)
- [ ] `zzz_ignore_vars.nu` — final-order script loads last (filename prefix `zzz_` is intentional)

### E. Dotfiles deployed configs

- [ ] `~/.config/helix/config.toml` — present, has nu as `:sh` backend
- [ ] `~/.config/helix/languages.toml` — present
- [ ] `~/.config/lazygit/config.yml` — present
- [ ] `~/.config/zellij/config.kdl` — present; the keybindings file `cozy/CLAUDE.md` calls source of truth
- [ ] `~/.config/zellij/layouts/` — present
- [ ] `~/.config/broot/conf.hjson` — present (written by `broot --write-default-conf` step 7)
- [ ] `~/.config/broot/launcher/installed-*` — present (`--set-install-state installed`)
- [ ] `~/.config/jj/config.toml` — present
- [ ] `~/.config/jj/jj-config-claude-ai.toml` — present (referenced by `JJ_CONFIG` in `/etc/sandbox-persistent.sh`)
- [ ] `~/.config/nushell/config.nu`, `env.nu` — present, vendored versions (not nu defaults)
- [ ] `~/.config/topiary/` — present
- [ ] `~/.visidatarc` — present (copied from `docker-files/.visidatarc`)

### F. Claude Code + skills + MCP

- [ ] `which claude` resolves; `claude --version` runs
- [ ] `~/.claude/CLAUDE.md` ends with the appended `docker-files/global-claude.md` content (grep for "Sandbox Environment" header)
- [ ] `~/.claude/settings.json` has baked `cleanupPeriodDays=36500`, `editorMode=normal`, `verbose=true`
- [ ] `claude mcp list` shows `nushell` stdio MCP server pointing at `/home/linuxbrew/.linuxbrew/bin/nu --mcp`
- [ ] `~/.claude/skills/` populated from both `my-claude-skills` and `nushell-skills` (`elegance-first`, `intent-audit`, `jj-ai-guide`, `keep-a-changelog`, `nushell-completions`, `nushell-style`, `spec-extract` — and the rest)

### G. Runtime sandbox features

- [ ] `/etc/sandbox-persistent.sh` sourced — fresh nu shell has `$env.GIT_AUTHOR_NAME == "Claude"`, `$env.JJ_CONFIG` set, `$env.XDG_*` set, `$env.HELIX_RUNTIME` set, `$env.LANG == "C.UTF-8"`
- [ ] `sudo true` works without password prompt
- [ ] `docker ps` works (docker socket mounted and usable)
- [ ] `~/workspace/mounted` symlink resolves to the host workspace path (`/Users/user/...` or wherever the user passed to `docker sandbox create`)
- [ ] `~/.local/bin/pbcopy` exists, mode 755, OSC 52 shim — `echo test | pbcopy` exits 0 (host clipboard arrival → user section)
- [ ] `/etc/apt/apt.conf.d/90proxy` present; `sudo apt-get update` succeeds (routes through `host.docker.internal:3128`)
- [ ] `~/.config/git/config` — `[user] Agent`, `[safe] directory = *`, `[gc] auto = 0`, `[core] fsync = all`
- [ ] `~/.config/git/ignore` — `.DS_Store Thumbs.db desktop.ini`
- [ ] `~/.gitconfig` may exist (written by `docker sandbox create`) — XDG settings still apply when global has no override

### H. Restored state (user mentioned just restoring these)

- [ ] `~/repos/` contains the expected restored project directories (compare against `toolkit/vendor.yml` repo list — plus any user-added repos)
- [ ] Nushell history present at `~/.local/share/nushell/history.*` (sqlite or txt depending on config), non-empty
- [ ] `history | length` in nu returns > 0
- [ ] Permissions on restored files are agent-owned (no root-owned strays)

### I. Bootstrap re-run smoke (optional but quick)

- [ ] `nu -c 'use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu; bootstrap'` exits 0 from inside this sandbox without breaking the deployed state. Full re-run checklist → `todo/20260511-1258-verify-sandbox-rerun.md`.

## User-checkable verification (agent cannot observe)

The following require UI rendering, host-side observation, or interactive use that the agent can't fully evaluate inside the sandbox.

### Clipboard (OSC 52 → host)

- [ ] Run `echo cozy-clipboard-test | pbcopy` in sandbox → paste on host → text matches
- [ ] Helix yank (`y`) → paste on host → content matches
- [ ] Lazygit copy commit hash → paste on host → matches

### TUIs render correctly

- [ ] `hx` launches in zellij pane, renders with truecolor, line numbers, status line; `:sh` opens a nu shell
- [ ] `lazygit` opens, shows status/log/branches panes, keybindings work
- [ ] `zellij` panes/tabs/floating windows respond to keybindings from `vendor/dotfiles/zellij/config.kdl`
- [ ] `broot` opens, tree renders, `:open` jumps to file in helix
- [ ] `vd some.csv` opens visidata, columns render, navigation works
- [ ] `topiary format --language nu <some.nu>` produces formatted output; same via helix `:format` if wired

### Host-side observation

- [ ] `docker sandbox ls` on host shows this sandbox running
- [ ] Edit a file under `~/workspace/mounted/` in sandbox → change visible on host filesystem (VirtioFS propagation)
- [ ] Reverse: edit file on host → change visible in sandbox
- [ ] `cozy sandbox-state history export` (or whatever export command was used) produces a host-visible artifact

### Persistence across sandbox restart

- [ ] `docker sandbox stop <name>` then `docker sandbox start <name>` — `~/` user data persists (skills, config, history)
- [ ] After restart, `/etc/sandbox-persistent.sh` env still applies in new shells
- [ ] After restart, `~/.gitconfig` is rewritten by docker sandbox create (so user identity reverts to docker-managed; XDG `~/.config/git/config` still applies)

### Terminal / WezTerm

- [ ] `echo $env.COLORTERM` reports `truecolor` (set via Dockerfile ENV)
- [ ] Colors render correctly in helix, lazygit, broot, nu prompt
- [ ] WezTerm host config (vendored under `vendor/dotfiles/wezterm/`) — this is host-side, only verifiable if the user actually runs WezTerm

### Interactive Claude Code session

- [ ] `claude` launches an interactive session in this sandbox
- [ ] MCP nushell tools work in conversation (e.g. ask claude to run `ls | length` via the MCP)
- [ ] Skills load (e.g. `/nushell-style`)
- [ ] `~/.claude/CLAUDE.md` content is included in claude's context (test with a question that requires it)

## Affected files

- Existing files (verification targets):
  - `Dockerfile`, `bootstrap.sh`, `sandbox-toolkit/install/bootstrap.nu`, `sandbox-toolkit/install/ensure-nu.sh`, `sandbox-toolkit/install/.nushell-version`, `sandbox-toolkit/install/mod.nu`
  - `sandbox-toolkit/mod.nu` and its exports
  - `toolkit/vendor.nu`, `toolkit/vendor.yml`
  - `docker-files/global-claude.md`, `docker-files/pbcopy`, `docker-files/.visidatarc`, `docker-files/nushell-autoload/*.nu`
  - All `vendor/` subdirs (dotfiles, nu-goodies, nu-kv, dotnu, numd, claude-nu, nu-cmd-stack, nutest, topiary-nushell, my-claude-skills, nushell-skills, nu-multiproof)
- New files: none for this todo (verification only)
