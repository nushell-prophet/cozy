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

- [ ] `which nu hx lazygit zellij broot delta jj git-lfs vd bat topiary fd fzf` all resolve
- [ ] `which nu` resolves to `/home/linuxbrew/.linuxbrew/bin/nu` — if it resolves to `~/.local/bin/nu`, ensure-nu.sh fell back to the pinned version (still working, but worth knowing)
- [ ] `nu --version` exits 0
- [ ] `nu -c "use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu"` exits 0 (parse + top-level eval succeeds)
- [ ] `hx --version`, `lazygit --version`, `zellij --version`, `broot --version`, `delta --version`, `jj --version`, `vd --version`, `bat --version`, `topiary --version`, `fd --version`, `fzf --version` all exit 0

### B. Vendored modules under `~/repos/`

Per `cozy/toolkit/vendor.yml`. Each `use` must succeed; smoke command verifies non-trivial functionality.

- [ ] `~/repos/nu-goodies/` — `use ~/repos/nu-goodies/nu-goodies` exits 0; pick one exported command (e.g. `arrange`) and confirm it's defined via `scope commands | where name == 'arrange'`
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
- [ ] `~/repos/cozy/sandbox-toolkit/` and `~/repos/cozy/docker-files/` present and complete (`ls ~/repos/cozy/sandbox-toolkit/install/` shows `bootstrap.nu`, `mod.nu`, `claude.nu`, `topiary.nu`, `rust.nu`, `polars.nu`, `zellij.nu`, `nushell.nu`, `nu-plugin-image.nu`, `ensure-nu.sh`, `.nushell-version`; `ls ~/repos/cozy/docker-files/` shows `pbcopy`, `.visidatarc`, `global-claude.md`, `nushell-autoload/`)

### C. `cozy` command surface (sandbox-toolkit/mod.nu exports)

- [ ] `use ~/repos/cozy/sandbox-toolkit/` exposes: `sync-repos mount platform sandbox-state dev-link install configure git-harden` (plus a no-op `main`)
- [ ] `cozy platform` reports correct arch/OS
- [ ] `cozy install` subcommand surface — `scope commands | where name starts-with 'install '` shows: `bootstrap claude rust polars topiary zellij nushell nu-plugin-image`. Each `--help` runs:
  - [ ] `cozy install bootstrap --help`
  - [ ] `cozy install claude --help`
  - [ ] `cozy install rust --help`
  - [ ] `cozy install polars --help`
  - [ ] `cozy install topiary --help`
  - [ ] `cozy install zellij --help`
  - [ ] `cozy install nushell --help`
  - [ ] `cozy install nu-plugin-image --help`
- [ ] `cozy sync-repos --help` runs (no execution)
- [ ] `cozy mount --help` runs
- [ ] `cozy sandbox-state history --help` runs (the command the user used to restore history)
- [ ] `cozy git-harden --help` runs
- [ ] `cozy configure --help` runs

### D. Nushell autoload scripts

Two deploy paths populate `~/.config/nushell/autoload/`. They overlap on `hooks-config.nu`; dotfiles' `push-to-machine` runs after bootstrap's copy (step 4 after step 3), so the dotfiles version wins.

**From `vendor/dotfiles/nushell/autoload/` (deployed via `paths-docker.csv`):**

- [ ] `br.nu` — defines `br` (broot wrapper); `scope commands | where name == 'br'` shows it
- [ ] `carapace-config.nu` — completions wire-up loads without error on nu startup
- [ ] `hooks-config.nu` — env_change hooks set (`$env.config.hooks.env_change | columns | length` > 0)
- [ ] `zzz_ignore_vars.nu` — file present; filename prefix `zzz_` makes it load last alphabetically

**From `docker-files/nushell-autoload/` (copied by bootstrap step 3):**

- [ ] `mcp-server.nu` — script loads on nu startup but `nu --mcp` server only starts when the flag is passed (don't trigger it; just confirm the file exists and `nu -c "exit 0"` doesn't hang)
- [ ] `module-imports.nu` — auto-imports `~/repos/` modules into top-level scope; pick one symbol and confirm it's defined without explicit `use` (read the file to find what's actually imported)
- [ ] `my-nu-completions.nu` — file present; read it to enumerate which commands get completions, then spot-check one
- [ ] `standard-aliasses.nu` — file present; read it to enumerate defined aliases, then spot-check one resolves
- [ ] `hooks-config.nu` — present in this dir too, but the dotfiles version overrides it (verify which content is live: `diff ~/.config/nushell/autoload/hooks-config.nu ~/repos/cozy/docker-files/nushell-autoload/hooks-config.nu` should show diffs, while diff against `~/repos/dotfiles/nushell/autoload/hooks-config.nu` should be identical)

### E. Dotfiles deployed configs (source of truth: `vendor/dotfiles/paths-docker.csv`)

Helix:

- [ ] `~/.config/helix/config.toml` — present, has nu as `:sh` backend
- [ ] `~/.config/helix/languages.toml` — present
- [ ] `~/.config/helix/config-no-wrap.toml` — present (alternate config variant)

Lazygit:

- [ ] `~/.config/lazygit/config.yml` — present

Zellij (keybindings source of truth per `cozy/CLAUDE.md` is `vendor/dotfiles/zellij/config.kdl`):

- [ ] `~/.config/zellij/config.kdl` — present
- [ ] `~/.config/zellij/layouts/compact-bar-up.kdl` — present
- [ ] `~/.config/zellij/layouts/compact-bar-up.swap.kdl` — present
- [ ] `~/.config/zellij/broot-paste.nu` — present (zellij ↔ broot clipboard helper)
- [ ] `~/.config/zellij/hx-scrollback.nu` — present (scrollback-into-helix integration)
- [ ] `~/.config/zellij/lazygit-helix.nu` — present
- [ ] `~/.config/zellij/todo-nu/` — present (todo helpers)

Broot:

- [ ] `~/.config/broot/conf.hjson` — present (overlap: written by `broot --write-default-conf` step 7 AND deployed via paths-docker.csv; dotfiles deploy runs after, so dotfiles wins)
- [ ] `~/.config/broot/select.hjson` — present
- [ ] `~/.config/broot/verbs.hjson` — present
- [ ] `~/.config/broot/launcher/installed-*` — present (from `--set-install-state installed`)

Jj:

- [ ] `~/.config/jj/jj-config-claude-ai.toml` — present (referenced by `JJ_CONFIG` in `/etc/sandbox-persistent.sh`). Note: no separate `~/.config/jj/config.toml` is deployed.

Nushell:

- [ ] `~/.config/nushell/config.nu` — present, vendored version (not nu default)
- [ ] `~/.config/nushell/env.nu` — present, vendored
- [ ] `~/.config/nushell/toolkit.nu` — present (referenced via `use toolkit.nu` in the nushell config flow)

Visidata:

- [ ] `~/.visidatarc` — present (copied by bootstrap from `docker-files/.visidatarc`)

Claude (also in section F, listed here for paths-docker.csv completeness):

- [ ] `~/.claude/CLAUDE.md` — present (dotfiles writes it, bootstrap appends `global-claude.md`)
- [ ] `~/.claude/settings.json` — present
- [ ] `~/.claude/agents/` — populated from `*.md` glob
- [ ] `~/.claude/commands/` — populated from `*.md` glob
- [ ] `~/.claude/output-styles/` — populated from `**/*` glob

### F. Claude Code + skills + MCP

- [ ] `which claude` resolves; `claude --version` runs
- [ ] `~/.claude/CLAUDE.md` ends with the appended `docker-files/global-claude.md` content (grep for "Sandbox Environment" header)
- [ ] `~/.claude/settings.json` has baked `cleanupPeriodDays=36500`, `editorMode=normal`, `verbose=true`
- [ ] `claude mcp list` shows `nushell` stdio MCP server pointing at `/home/linuxbrew/.linuxbrew/bin/nu --mcp`
- [ ] `~/.claude/skills/` contains exactly these 7 directories (combined output of `install-skills --all` from both source repos as of 2026-05-11): `elegance-first`, `intent-audit`, `jj-ai-guide`, `keep-a-changelog`, `nushell-completions`, `nushell-style`, `spec-extract`. If the set differs, the source repos drifted — re-check `~/repos/my-claude-skills/plugins/my-skills/skills/` and `~/repos/nushell-skills/plugins/`

### G. Runtime sandbox features

Env from `/etc/sandbox-persistent.sh`:

- [ ] Fresh nu shell has `$env.GIT_AUTHOR_NAME == "Claude"`, `$env.GIT_AUTHOR_EMAIL == "claude@anthropic.com"`, same for COMMITTER vars
- [ ] `$env.JJ_CONFIG` points to `~/.config/jj/jj-config-claude-ai.toml`
- [ ] `$env.XDG_CONFIG_HOME`, `$env.XDG_DATA_HOME`, `$env.XDG_CACHE_HOME` set
- [ ] `$env.HELIX_RUNTIME == "/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime"`
- [ ] `$env.LANG == "C.UTF-8"` (also set via Dockerfile ENV — won't distinguish source, both fine)

System & host integration:

- [ ] `sudo true` works without password prompt
- [ ] `docker ps` works (docker socket mounted and usable)
- [ ] `~/workspace/mounted` symlink — `readlink ~/workspace/mounted` resolves to the host workspace path passed to `docker sandbox create` (e.g. `/Users/user/...`)
- [ ] `/etc/apt/apt.conf.d/90proxy` present; `sudo apt-get update` succeeds (routes through `host.docker.internal:3128`). NOTE: failure may indicate host-side proxy is down, not a sandbox bug.

`~/.local/bin/` (PATH-first per Dockerfile ENV):

- [ ] `~/.local/bin/pbcopy` — exists, mode 755 (OSC 52 shim, host arrival → user section)
- [ ] `~/.local/bin/claude` — exists (installed by `claude install` step 9)
- [ ] `~/.local/bin/hx-scrollback` — exists (deployed; binary for the zellij hx-scrollback.nu integration)
- [ ] `~/.local/bin/todo-hx` — exists (deployed; todo-in-helix helper)

Git config (XDG):

- [ ] `~/.config/git/config` written by bootstrap step 2 contains: `[user] name=Agent email=agent@sandbox`, `[safe] directory=*`, `[gc] auto=0`, `[core] fsync=all fsyncMethod=fsync`
- [ ] **Reality check**: live `safe.directory` may be the workspace path (e.g. `/Users/user/git/ai-sandbox-dev-container`) rather than `*` — `docker sandbox create` rewrites the XDG config on every start, replacing `*` with the mounted workspace path. Both work; flag if `safe.directory` is missing entirely
- [ ] Live config may include a `[credential "https://github.com"] helper = gh-token` block added by `docker sandbox create` — expected, not bootstrap-written
- [ ] `~/.config/git/ignore` contains `.DS_Store`, `Thumbs.db`, `desktop.ini`
- [ ] `~/.gitconfig` exists (written by `docker sandbox create`) — XDG settings still apply via git's config layering (`git config --show-origin user.name` reveals which file wins)

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
