# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `bootstrap.sh` auto-installs Homebrew on Linux when passwordless `sudo -n` works (e.g. inside a `docker sandbox` `shell` agent). On macOS — or any host where sudo would prompt — it keeps the fail-fast behavior and now prints the `NONINTERACTIVE=1` install one-liner alongside the brew.sh link so it can be copy-pasted directly. (c9fe9cf, 75a78a2)

### Changed

- Replaced `cozy platform` / `cozy platform apply` with a single narrow command `cozy swap-zellij-super`. The previous module auto-detected the host OS from `WORKSPACE_DIR` path heuristics, but detection was unreliable on Windows (broke in 1a36b53 and even the prior fix didn't hold) and macOS/Linux branches were no-ops. The new command does the one thing that was actually used — rewriting Super→Alt in `~/.config/zellij/config.kdl` for Windows hosts — with no detection, no dispatcher, no platform parameter.

## [0.2.3] - 2026-05-23

### Changed

- Renamed `sandbox-toolkit/` → `cozy-module/` — aligns the folder name with how it's loaded inside the sandbox (`overlay use ~/repos/cozy/cozy-module/ as cozy --prefix`). Custom scripts importing from the old path need updating. (674684d, b7636c8)
- Vendored `nu-goodies` — adds `fzf-preview` (pipe paths through fzf with bat preview, jumps to `file:line[:col]`) and `in-pane` (open a zellij pane running `nu --execute <command>`). (6395628)
- Vendored `nu-multiproof` — upstream refactor refresh: `--path` → `--repo` across commands, path-typed params retyped from `string` to `path`. Plus `tree-hashes` fixes: uuid-suffix the root-cid stage dir, stale-sig check now also catches bare `<manifest>.sig`. (86398d3)
- Vendored `dotfiles/wezterm` — QuickSelect `file:line` regex excludes `╭─[` so nushell error headers like `╭─[/path/file.nu:1946:63]` no longer match with the box-drawing prefix. (81e25dc)

### Fixed

- Bootstrap `claude install` no longer skips the real install during docker build. The `which claude` guard from e67ed1d matched the `claude install` module command itself (added by `use claude.nu`), making the subsequent `^claude mcp add` fail with `Command 'claude' not found`. Now filters to `type == external`. (a51a5c7)

## [0.2.2] - 2026-05-14

### Added

- `dotfiles/toolkit push-to-machine --delete-orphans` flag — removes machine files whose repo source has been deleted upstream. Without it, removed dotfiles persisted indefinitely in user homes (mirrors the same problem `populate-repos` solved in 0.2.0 for vendored modules). Bootstrap still calls `push-to-machine --docker` without this flag — opt-in. (24e1ce7)

### Changed

- WezTerm `cmd+shift+n` / `alt+cmd+n` now launch a fresh WezTerm instance via `open -n -a WezTerm --args start --always-new-process` instead of `SpawnCommandInNewWindow`. The old action reused the same OS process, so new windows ended up under the existing Dock icon. `--always-new-process` is required: without it the new wezterm-gui detects the running mux over its unix socket and delegates the spawn back, collapsing into the original Dock icon. Works around wezterm issue #6202 where `wezterm start --always-new-process` opens in the background on macOS. (7269696)
- Vendored `nu-cmd-stack` — `cmd-stack init` now accepts `--quiet` / `--force-keybindings` directly (previously only on `apply-keybindings`), and `apply-keybindings` made private. Interactive `history` selector passes `--quiet` through. (a8af768)

### Removed

- Vendored dotfiles slash commands `/commit-git`, `/git-improve-history`, and the `commit-git` agent — superseded by upstream Claude Code's built-in `/commit-git` skill (now listed in the global skills catalog). (a03aaf2)

### Fixed

- `env.nu` also defaults `XDG_CONFIG_HOME` from `$HOME` when unset, not just `XDG_DATA_HOME` — the `TOPIARY_*` exports and `vd` alias further down read `XDG_CONFIG_HOME` and crashed nu on a fresh macOS shell or sandbox shell predating bootstrap with "Cannot find column XDG_CONFIG_HOME". Extends the 0.2.0 XDG_DATA_HOME fallback. (a2e6bfe)
- `cozy install bootstrap` skips the `claude.ai/install.sh` curl|bash when `claude` is already on PATH — e.g. inside `sbx run claude`, whose base image ships Claude Code pre-installed, the reinstall was wasted work. (e67ed1d)

## [0.2.1] - 2026-05-14

### Added

- `bootstrap.sh` / `bootstrap.nu` gain `--force` flag, and host installs now refuse to clobber existing user configs on first run — fail-fast guard checks `XDG_CONFIG_HOME/{nushell,helix,zellij,lazygit,broot,jj,git}`, `~/.claude/`, `~/.visidatarc`, and `~/repos/`; lists conflicts and exits with instructions. Re-runs skip the guard via a `~/.cozy-installed` stamp written on successful completion; `--force` is the escape hatch for partial-failure recovery. (b459662)

### Fixed

- macOS host install now exports `XDG_CONFIG_HOME="$HOME/.config"` to the user's shell rc (`~/.zshrc` or `~/.bash_profile`, picked by `$SHELL`), wrapped in `# >>> cozy env >>>` markers. Without this, `nu` on macOS read defaults from `~/Library/Application Support/nushell/` and all the dotfiles cozy had just deployed to `~/.config/nushell/` were silently invisible. (40d94b7)

## [0.2.0] - 2026-05-12

### Added

- `cozy install bootstrap` — single end-to-end installer (brew tools, vendored modules under `~/repos/`, dotfiles via `toolkit push-to-machine`, Claude skills, broot init, topiary, Claude Code + nushell MCP). `--local` re-vendors from sibling repos for development workflows. (0c69ad8)
- `cozy/bootstrap.sh` — host entry that ensures brew + nu, then execs `bootstrap.nu` with forwarded args. Docker keeps calling `nu -c` directly; both paths share `bootstrap.nu`. (0d095e4)
- `sandbox-toolkit/install/ensure-nu.sh` + `.nushell-version` — version-pin fallback for nushell (pre-1.0, syntax drifts between releases). Both `bootstrap.sh` and the Dockerfile call `ensure-nu.sh` before running `bootstrap.nu`: it tries latest brew nushell first, smoke-tests it with `nu -c "use bootstrap.nu"`, and on parse failure downloads the tested version (currently `0.112.2`) from github releases into `~/.local/bin/nu` — already first on PATH so it shadows the broken latest. Architecture/OS detected the way brew picks bottles (`x86_64-unknown-linux-gnu` / `aarch64-apple-darwin` / etc.). If even the pinned version can't parse `bootstrap.nu`, the script fails loudly rather than silently degrading.
- `vendor.nu` honors `$env.GH_TOKEN` / `$env.GITHUB_TOKEN` — when set, requests use `Authorization: bearer …` and the per-IP GitHub API limit jumps from 60 to 5000 req/hr. No-op when neither is set, so unauthenticated runs behave as before. (f624b24)

### Changed

- Dockerfile collapsed from ~95 install lines to a single `RUN nu …/bootstrap.nu` (-95/+16 net). Docker-isms (USER, ENV, COPY, apt setup, pbcopy, build-time `/etc/gitconfig`, `/etc/sandbox-persistent.sh`) stay inline; everything else moved into `bootstrap.nu` so host and Docker share one install path. Broot init moved into bootstrap step 7 so the host gets it too. `ARG MODULES_SOURCE` and `ARG INSTALL_CLAUDE` dropped — add back if a real second caller wants them. (52d0c50)
- Continue the bootstrap.nu transition: move every remaining USER-root layer (apt installs, pbcopy, git identity, `/etc/apt/apt.conf.d/90proxy`, `/etc/sandbox-persistent.sh` claude env exports) out of the Dockerfile into `bootstrap.nu`'s new `setup-docker-system` step (auto-gated on `/etc/sandbox-persistent.sh`). Sudo is kept only where unavoidable: apt itself, and the apt proxy file (sudo strips `APT_CONFIG` so env-var indirection would silently fail under `sudo apt`). pbcopy now installs to `~/.local/bin/` (already on PATH); git user.name/email folds into XDG `~/.config/git/config` alongside the other runtime settings (works for both apt-git and brew-git, unlike `/etc/gitconfig`); the apt-sources https-rewrite is dropped as vestigial. Dockerfile drops `USER root` entirely and now only carries true Docker-isms: `FROM`, `USER agent`, `ENV`, brew + nushell bootstrap, COPY staging, the bootstrap invocation, README.
- `--local` flag now means "force refresh from sibling repos" rather than "host install". Host install by default consumes the freshly-cloned `cozy/vendor/` as-is (the dir is committed, not gitignored), avoiding a redundant tarball-download pass through `vendor.nu` on every bootstrap. `vendor.nu` only runs when `vendor/` is empty or `--local` forces it. (d60fb7e)
- `setup-docker-system` and Docker-staged vendor consumption now key off filesystem markers instead of the old `--in-docker` flag: `/etc/sandbox-persistent.sh` (shipped by `docker/sandbox-templates`) gates Docker-runtime setup; populated `/tmp/vendor` gates Docker-build vendor reuse. Same `cozy install bootstrap` invocation now works in a fresh sandbox, in a docker-build `RUN`, and on a macOS host. (ad6285a)
- `bootstrap.nu` always passes `--docker` to `push-to-machine`. The dotfiles `paths-default.csv` was never vendored (cozy is docker-first) so host mode previously died on a missing file; `paths-docker.csv` is the right paths file for both targets. (6ab6541)
- Git `user.name` / `user.email` written unconditionally in step 2 (was gated on `--in-docker`). On a real host, git precedence puts `~/.gitconfig` ahead of XDG, so any user's personal identity still overrides; the XDG entry only kicks in when nothing else is set, which is exactly what host-install-inside-a-fresh-sandbox needs. (23ae7fe)
- Apt sources rewritten to `https://` (idempotent across deb822 `.sources` and one-line `.list` formats) and the `/etc/apt/apt.conf.d/90proxy` file dropped entirely. Collapses docker-build, fresh-sandbox install, and `cozy:v1` re-runs into one path with no proxy dependency — sandbox VMs allow port 443 (where brew already worked) but block direct port 80, which the previous http-via-proxy setup only handled inconsistently. (61d9702)
- Vendored `dotfiles/claude` — `editorMode=normal` (modal prompt editing), `verbose=true`, and `cleanupPeriodDays=36500` (~100 years session-log retention) baked into `~/.claude/settings.json` via `paths-docker.csv`, so cozy rebuilds restore these defaults instead of falling back to Claude Code's bare settings. (00c63b7, 86e43d0)
- Vendored `claude-nu` — `claude-export` gains `--tools` and `--include-thinking` flags for filtering transcript exports. (7e8e4e7)
- Vendored `nu-cmd-stack` — `apply-keybindings` refactor. (7e8e4e7)
- Vendored `dotfiles/zellij` — `todo-nu` simplifications and `hx-scrollback` adjustments. (7e8e4e7, 3fc1646)
- Vendored `nu-goodies` — `arrange.nu` updated from upstream. (3fc1646)
- Vendored `nutest` — broad refresh (formatter/runner/store/orchestrator) following local sync with vyadh/nutest main. (3fc1646)

### Fixed

- `vendor.nu` no longer feeds HTML/JSON error bodies into `tar xz` and lets the cryptic "gzip: stdin: not in gzip format" surface — `curl` now uses `-fsSL` so HTTP errors fail the pipeline at the network step with the real status code. (f624b24)
- Bootstrap on a base-image sandbox now exports the same `XDG_*` / `HELIX_RUNTIME` / `LANG` vars the Dockerfile bakes in, and copies `sandbox-toolkit/` + `docker-files/` from the cloned cozy repo into `~/repos/cozy/`. Without these, `nu` died at startup on `env.nu` (missing `XDG_DATA_HOME`) and `module-imports.nu` (missing `~/repos/cozy/sandbox-toolkit/`). (1055fdd)
- Docker-mode bootstrap re-runs wipe colliding nushell config (`config.nu`, `env.nu`, `autoload/`) at the start of `setup-docker-system` while preserving `history.sqlite3*`, so a pre-launched `nu` no longer leaves default config that collides with the autoload write or dotfiles snapshot. (05930ab, 31c23f5)
- Runtime git settings (`safe.directory '*'`, `gc.auto=0`, `core.fsync=all`, `core.fsyncMethod=fsync`, global ignore for `.DS_Store` / `Thumbs.db`) moved from `/etc/gitconfig` to `~/.config/git/` (XDG). Brew git's sysconfdir is `/home/linuxbrew/.linuxbrew/etc`, not `/etc`, so every `git config --system` write was going to a file the runtime brew git never reads — `.DS_Store` ignore and the VirtioFS corruption guards from 0.1.1 were silently broken. XDG is read by every git binary regardless of sysconfdir and isn't overwritten by `docker sandbox create`. (288a2c9)
- Cold-start after `bash bootstrap.sh` in a vanilla shell sandbox no longer crashes `nu` on "Cannot find column XDG_DATA_HOME": `env.nu` now defaults `XDG_DATA_HOME` from `$HOME` when unset, and bootstrap prints a hint to `exec bash -l` when the current shell predates the env exports just written to `/etc/sandbox-persistent.sh`. (4e546fc)
- `cozy install bootstrap` on macOS host now resolves `nu` via `which nu` at runtime for the `claude mcp add` registration. Previously hardcoded `/home/linuxbrew/.linuxbrew/bin/nu`, which doesn't exist on Apple Silicon brew (`/opt/homebrew/bin/nu`), so the MCP server registered against a non-existent binary and silently failed on host installs. (da7f93b)
- `topiary install` on macOS no longer runs `sudo apt-get install` when gcc is missing — branches on `$nu.os-info.name` and points users at `xcode-select --install` instead, errors on unknown OS. (47946af)
- `topiary install` finds the vendored grammar via a `~/git/topiary-nushell → ~/repos/topiary-nushell` symlink — the old Dockerfile shell shim was lost in the nushell rewrite, so topiary was silently missing the vendored grammar (or falling back to a github clone). No clone fallback per fail-fast: missing vendor dir now errors loudly. (53970d8)
- `populate-repos` runs `rm -rf` on each vendor destination before `cp -r`, mirroring the cozy_dst loop earlier in the file — files removed from upstream vendored modules no longer persist indefinitely in user homes. (362ce1f)
- `vendor.nu` derives its target directory from `path self | path dirname | path dirname` instead of `pwd`, so invoking it from any cwd writes vendor in the right place and doesn't depend on the caller's working directory. (f4d3590)
- Host-mode bootstrap re-runs now clean `~/.config/nushell/autoload/` before copying, mirroring the docker behaviour — stale autoload entries from removed upstream sources no longer linger on host. The duplicate docker-only wipe in `setup-docker-system` is removed; cozy now owns the autoload dir from a single site. (121ee4a)
- `setup-docker-system` env block (XDG/HELIX_RUNTIME/LANG exports) is now idempotent in `/etc/sandbox-persistent.sh` — wrapped with `# >>> cozy env >>>` / `# <<< cozy env <<<` markers and replaced in place on each run, instead of blindly appending duplicates. (45cc3d9)
- Dropped the unconditional `mkdir ~/workspace` from `populate-repos` — the docker path auto-creates the dir via `COPY README.md /home/agent/workspace/README.md`, and host installs were left with an unused empty `~/workspace/` that confused users who never run the docker path. (7ecd43a)

## [0.1.1] - 2026-04-29

### Added

- `cozy git-harden` command — sets `gc.auto=0` and `receive.autoGc=false` in `.git/config` to prevent VirtioFS shared-mount corruption when host and sandbox both touch the same `.git/`. Two prior incidents (torn pack on cozy, zero-byte index on temp2) traced to non-atomic flushes across the VM/host boundary (ba35a06)
- `cozy install nushell`, `polars`, `nu-plugin-image`, and `zellij` now auto-install rust when missing instead of erroring with "cargo not found — run `toolkit install rust` first" (b156778, d077ee5)

### Changed

- Sandbox `/etc/gitconfig` sets `gc.auto=0` (kills the auto-repack that produced a torn pack) and `core.fsync=all` + `core.fsyncMethod=fsync` (writes wait for real disk commits) — protects against VirtioFS corruption on shared host↔sandbox mounts (ba35a06)
- `LANG=C.UTF-8` set as a Dockerfile ENV — fixes git-delta showing UTF-8 multi-byte sequences (e.g. em-dashes) as literal `<E2><80><94>` hex escapes when piping through less (ed407d1)
- `wezterm-cozy` zellij attach uses `nu --login --execute` instead of `--commands`, matching the current nushell flag (a80c590)
- Vendored `nushell-skills` bumped to 1.2.0 — adds Nushell 0.100→0.112 migration guide and enhancements references covering renamed/removed commands and new idioms; activates on phrases like "update nushell script" (33111cc)
- Vendored `nu-kv` — new `setp` shorthand for `pbpaste | set pbpaste`, and `kv get --pbcopy` flag to pipe the retrieved value through `pbcopy` in one call (ab672c9)
- Vendored `nu-goodies` — new `rgv` command wraps `rg --vimgrep` and parses output into a `{path, content}` table that pairs with WezTerm's quick-select pattern; `gradient-screen.nu` collapsed back to inline pipeline form (da884ca)
- Vendored `nu-cmd-stack` — `cmd-stack init` accepts `--quiet` (suppresses help/result messages) and `--force-keybindings` (overrides conflicts); the interactive `history` selector passes `--quiet` so it doesn't reprint banners (d13dd1d)
- Vendored `dotfiles/wezterm` — quick-select regex generalized from a nushell-error-only pattern to `[^\s│]+:\d+:\d+`, matching `rg --vimgrep`, nushell table rows, stack traces, and error headers (cfcaaae)
- Vendored `dotfiles/zellij` — `hx-scrollback` opens helix at line +99999 so scrollback dumps land at the bottom (most recent output) instead of the top; `todo-nu` no longer overwrites an existing `todo/CLAUDE.md` (06ae5f1)
- Vendored `dotfiles/claude` — adds Conciseness (STRICT) section with anti-verbosity rules; reorganizes English-rephrasing into Communication (4f18cc0)

### Fixed

- `cozy install nushell` (and other cargo-dependent scripts) timing out on flaky proxy — `~/.cargo/config.toml` is now written with `retry=5`, `http.timeout=120s`, and sparse registry protocol during `cozy install rust` (1367dfb)
- `nu-kv` storage path env var unset when `$env.WORKSPACE_DIR` was set — `tee { mkdir $in }` was wrapped in a record literal that returned the record instead of the path (caceab4)
- `nu-complete sandbox names` completions broken — `docker sandbox ls --json` reports stale "running" status for all machines; switched to `detect columns --guess` over the flat output (8bf56ff)

## [0.1.0] - 2026-04-10

### Added

- `cozy install claude` subcommand to install Claude Code inside a running sandbox — complements the `INSTALL_CLAUDE=false` build arg from 0.0.9, letting you start from an agent-free image and add Claude on demand (517703c)
- `--no-mcp` flag for `cozy install nushell` to skip MCP server registration (cf1ab49)
- `fd` (fd-find) to the sandbox Homebrew install list (29d9bc8)
- `nu-multiproof` vendored module for multi-proof utilities (d539cc0, 4c9d8df, 691b3c0)
- `vendor check` command to detect new `nushell-prophet` repos that aren't yet vendored, with `--add` to append them to `vendor.yml` (cb268a0, 11973ee)

### Changed

- Default vendoring now downloads GitHub tarballs instead of full git clones — faster builds, no `.git/` bloat (302275c)
- `vendor.nu` modules table extracted into `vendor.yml` as the single source of truth for vendored modules (425ebe8)
- Nushell `vars_menu` rewritten to use fzf via `executehostcommand` — native menu broke after nushell 0.101 scope changes (`scope variables` inside menu closures no longer sees REPL variables) (56cdac1)
- `working_dirs_cd_menu` switched to `GROUP BY cwd ORDER BY MAX(start_timestamp)` — the previous `DISTINCT cwd ORDER BY id DESC` returned every row because SQLite resolved `id` by adding it to the DISTINCT key (a1619a7)
- WezTerm QuickSelect patterns no longer include trailing punctuation (591cf4c)
- Vendored `nu-goodies` `gradient-screen` and other modules refreshed from upstream (681e421, b98008c, 835bbf6, 6765bb1, bf4e0f1)

### Removed

- Nushell keybindings `fzf_history_sessions` (Alt-Ctrl-F) and `paste_interpolation` (Alt-Shift-') (56cdac1)

### Fixed

- Rust install scripts now limit cargo parallelism and disable LTO — prevents OOM kills during `brew install` in memory-constrained build environments (41f5782)
- `safe.directory = *` moved from `--global` to `--system` git config so it survives `docker sandbox create` wiping `~/.gitconfig` (25fc7b5)
- Build-time git user identity now set at `--system` level so build commits don't fail when `~/.gitconfig` is wiped on sandbox recreation (e1f4050)
- `core.excludesFile` re-bound to `/home/agent/.gitignore` at `--system` level — global gitignore was lost on sandbox recreation (596f7b9)
- Dockerfile clone mode (`--build-arg MODULES_SOURCE=clone`) now includes `topiary-nushell` and `nu-multiproof` (691b3c0)

## [0.0.9] - 2026-03-29

### Added

- `INSTALL_CLAUDE` build arg to make Claude Code installation optional — pass `--build-arg INSTALL_CLAUDE=false` for an agent-free terminal environment (7b88616)

### Changed

- `sync-repos` now covers dotfiles, nutest, nushell-skills, and my-claude-skills — previously required a full rebuild to update (09fb006)
- Nushell pre_prompt hook tags history entries with non-zero exit codes and clears the tag on success (f651592)

### Fixed

- Zellij `dump-screen` uses `--path` flag instead of positional argument, matching current zellij CLI (f651592)
- `git update-index --cacheinfo` uses separate arguments for cross-version compatibility (f1d8aae)
- Stale gitignore files removed from dotfiles vendor (4ea246e)

## [0.0.8] - 2026-03-25

### Changed

- Consolidated `cozy-docker-sandbox-toolkit` into `cozy/sandbox-toolkit/` — the toolkit is no longer a separate repo. The whole `cozy` repo is cloned into the sandbox, giving one `git pull` for both toolkit and vendored module updates. `sync-repos` now pulls `cozy` instead of `cozy-docker-sandbox-toolkit` (f5e842c)
- Updated vendored modules (a83af56)

### Removed

- `cozy-docker-sandbox-toolkit` entry from `vendor.nu` — toolkit lives directly in the repo, no longer vendored from a sibling directory (f5e842c)
- `~/workspace/cozy-docker-sandbox-toolkit` symlink from Dockerfile — no longer needed (f5e842c)
- Stale `use toolkit.nu` and `toolkit *` entries from history seed — replaced with current `cozy *` commands (f5e842c)

### Fixed

- Skills directory not created before copying — broke fresh builds where `~/.claude/skills/` didn't exist yet (771d7bf)

## [0.0.7] - 2026-03-25

### Added

- `cozy dev-link` command to replace vendored `~/repos/` copies with symlinks to the mounted workspace — enables edit-and-test without rebuild (1a36b53)
- `cozy configure claude-settings` command to merge default Claude settings (effortLevel, cleanupPeriodDays) into sandbox (1a36b53)
- `install-skills` dotfiles toolkit command to deploy Claude skills from sibling skill repos into `~/.claude/skills/` (1a36b53)
- Zellij helper scripts: `broot-paste.nu` pastes broot selection into focused pane, `lazygit-helix.nu` sends Esc/reload-all to helix around lazygit, `hx-scrollback.nu` wraps helix for scrollback editing (1a36b53)
- Nushell hook for auto-renaming Zellij tabs based on current directory (1a36b53)
- Helix keybindings: `Ctrl+w` write, `Ctrl+r` reload, `Ctrl+Shift+g` git-commit current buffer, `+ e` dotnu-embeds-update, `+ f` flatten-to-nuon, `+ g` git-commit shortcut, `+ n` timestamp, `+ p` pandoc reformat, `+ v` voice via kokoro, `+ C` remove commented output (1a36b53)

### Changed

- `platform apply` platform parameter changed from `--platform` flag to positional argument (1a36b53)
- Windows detection regex in `platform.nu` simplified — single pattern `'^/:?[a-zA-Z]/'` replaces two separate checks (1a36b53)
- Helix whitespace rendering set to show all characters (nbsp, newline, nnbsp, space) instead of none (1a36b53)
- Zellij `Super Shift e` now uses built-in `EditScrollback` instead of custom dump-and-open-in-helix flow (1a36b53)
- Zellij `Super Alt l` runs lazygit through `lazygit-helix.nu` wrapper instead of directly — sends Esc before and `:reload-all` after for helix integration (1a36b53)
- Zellij `Super Alt b` runs broot through `broot-paste.nu` wrapper — pastes selection into the focused tiled pane instead of the floating one (1a36b53)
- Zellij scrollback editor changed to `hx-scrollback` wrapper that passes `--config ~/.config/helix/config-no-wrap.toml` (1a36b53)
- Zellij release notes disabled (`show_release_notes false`) (1a36b53)
- WezTerm SSH agent forwarding disabled (`mux_enable_ssh_agent = false`) (1a36b53)
- Nushell OSC 8 clickable links in `ls` output disabled (1a36b53)

### Removed

- Zellij `Super Alt t` shortcut for opening a tab in `~/temp/` (1a36b53)

### Fixed

- CLAUDE.md build example used wrong agent type — corrected to `shell` (6bd2641)

## [0.0.6] - 2026-03-24

### Added

- Claude Code skills vendored and deployed to `~/.claude/skills/` in image — includes nushell-style, nushell-completions, and my-skills plugins (b1e2a53)
- `toolkit docs` command to download Docker sandbox documentation as local markdown for offline reference (991b20e)

### Changed

- Updated nu-goodies from upstream (aa2e881)

### Fixed

- Windows detection in `platform.nu` — incorrect OS check broke platform-specific logic (1ccec18)

## [0.0.5] - 2026-03-21

### Added

- Combined `sandbox-state export` / `sandbox-state import` commands that run both history and projects operations in one call (4053c75)
- WezTerm config vendored into sandbox image (172d4dc, 2da8940)

### Fixed

- Autoload directory not created before copying nushell scripts — broke fresh builds without cached layers (cb7e15d)

## [0.0.4] - 2026-03-21

### Added

- Global gitignore in sandbox image for `.DS_Store` (macOS) and `Thumbs.db`/`desktop.ini` (Windows) — host workspace mounts bring these in (839aa13, ed6995f)

### Changed

- Vendor dotfiles selectively from local sibling repo instead of cloning from GitHub at build time — only Docker-relevant configs (broot, claude, helix, jj, lazygit, nushell, zellij) are included; irrelevant dirs (hammerspoon, macos-fresh, wezterm, visidata) excluded (1898b2b)
- Vendor topiary-nushell (languages.ncl, queries, LICENSE) to eliminate GitHub clone during default build — only tree-sitter-nu grammar compilation still requires network (5cd891d)
- Move `nu-kv` state directory into `sandbox-state/` (4322f8a)

### Removed

- Stale `md_backups` rsync excludes from `vendor.nu` — directories were cleaned up upstream (0dd61f6)

### Fixed

- `topiary.nu` import path in Dockerfile not updated after toolkit refactor to directory-based structure — broke fresh builds on Windows where no cached layers existed (2d2c23d)
- Empty directory skeletons left in vendored copies (233 empty helix query dirs, empty broot/zellij dirs) — added `--prune-empty-dirs` to rsync (ef27066)

## [0.0.3] - 2026-03-19

### Added

- `wezterm-cozy` command to launch a WezTerm window into a sandbox with Zellij auto-attach (97b77c6)
- `cozy-docker-sandbox-toolkit` available as `cozy` in Nushell autoload (c895984, 25df314)

### Changed

- Zellij no longer shows startup tips (9d5421b)

### Fixed

- Git operations (lazygit, etc.) failing on mounted workspace due to `safe.directory` ownership check — sandbox mounts have a different uid (05b9cf5)
- Sandbox completions reported wrong statuses via `docker sandbox ls --json`; switched to flat output (1a62f77)

## [0.0.2] - 2026-03-18

### Added

- Topiary code formatter with Nushell grammar support (b6a02fe)
- Git LFS (63df5b2)
- Initial dotfiles state committed at build time for trackable config changes (67b04bd)
- `validate-docs` Claude Code skill for cross-referencing docs against code (47f1ea9)

### Changed

- Rename project from `ai-sandbox` to `cozy` and Docker image from `nushell-ai-sandbox` to `cozy` (7cf05da)
- Rename companion toolkit from `ai-sandbox-toolkit` to `cozy-docker-sandbox-toolkit` (7cf05da)
- Switch base image from `docker/sandbox-templates:claude-code` to `docker/sandbox-templates:shell`; install Claude Code via Anthropic's recommended install script (`claude.ai/install.sh`) as a late Dockerfile layer — the `claude-code` image updates frequently and invalidated all cached layers on every rebuild (8fa0652)
- `nu-kv` store directory defaults to the workspace directory (e8ede4f)
- Sandbox state paths from `~/mounted` to `~/workspace/mounted` (605991d)
- Sandbox `CLAUDE.md` appended to dotfiles `CLAUDE.md` instead of overwriting (d9e7c49)
- Internal home directory renamed from `~/git/` to `~/repos/` (f70b045)

### Removed

- Carapace completions engine (63df5b2)

### Fixed

- Shift+Enter in WezTerm now works for Claude Code newlines (73830f8)
- History export/import no longer uses symlinks — Docker sandbox doesn't preserve them (907d5c6)
- Build failure when git identity was not set before dotfiles clone (ffc2322)

## [0.0.1] - 2026-03-08

### Added

- Docker sandbox-based terminal environment for AI agents, built on `docker/sandbox-templates:claude-code` with Homebrew toolchain (42325d7, 92a25c6)
- Nushell as primary shell with sensible defaults, autoload scripts, and MCP server pre-configured for Claude Code (f3effc3, 96944a9)
- Zellij terminal multiplexer with custom keybindings (`ctrl+shift+g` mode toggle, `cmd+t/n/w` for tabs and panes) (47c55a3)
- Helix editor configured with Nushell backend and `+ s` menu for XML-wrapped clipboard copy (47c55a3)
- Lazygit with git-delta side-by-side diffs, accessible via `cmd+alt+l` in Zellij (96944a9)
- Broot file manager with `:pbq`/`:pbfq` path-to-clipboard commands (47c55a3)
- FZF integration for Nushell history navigation (`ctrl+f`, `alt+f`) (46e9b07)
- Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, ai-sandbox-toolkit (f3effc3)
- Dotfiles deployment from my-dotfiles repo via `toolkit push-to-machine` (47c55a3)
- WezTerm config with kitty protocol keybindings, QuickSelect patterns, and sandbox/zen mode support (c53545b)
- Git author attribution so Claude Code commits are attributed to `claude@anthropic.com` (0cb6fbc)
- OSC 52 clipboard shim for sandbox-to-host copy (2f44e98)
- Build and management toolkit (`build.nu`, `vendor.nu`) with sandbox create/recreate commands (75111b8, cf612a5)
- Sandbox image test script with tool launch verification (a333bb6)
- Supports both `arm64` and `amd64` architectures via Docker sandbox

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.2.3...HEAD
[0.2.3]: https://github.com/nushell-prophet/cozy/compare/0.2.2...0.2.3
[0.2.2]: https://github.com/nushell-prophet/cozy/compare/0.2.1...0.2.2
[0.2.1]: https://github.com/nushell-prophet/cozy/compare/0.2.0...0.2.1
[0.2.0]: https://github.com/nushell-prophet/cozy/compare/0.1.1...0.2.0
[0.1.1]: https://github.com/nushell-prophet/cozy/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/nushell-prophet/cozy/compare/0.0.9...0.1.0
[0.0.9]: https://github.com/nushell-prophet/cozy/compare/0.0.8...0.0.9
[0.0.8]: https://github.com/nushell-prophet/cozy/compare/0.0.7...0.0.8
[0.0.7]: https://github.com/nushell-prophet/cozy/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/nushell-prophet/cozy/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/nushell-prophet/cozy/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/nushell-prophet/cozy/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/nushell-prophet/cozy/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/nushell-prophet/cozy/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/nushell-prophet/cozy/releases/tag/0.0.1
