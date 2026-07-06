# Changelog

All notable user-facing changes are documented in this file. Entries are brief — one line per entry, two at most.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.4] - 2026-07-06

### Changed

- `~/.cargo/bin` now sits before brew on PATH, so binaries you compile via `cozy install nushell` (etc.) win over the brew copies — previously new zellij tabs kept opening the brew nu because the zellij server had captured a PATH from before the cargo dir existed. (934821c)
- Vendored `claude-nu` — the git-intent interface moved here from `my-claude-skills`: `gi-hook enable` seeds the gi skills and canvas output style into `.claude/skills`; the hook now blocks turns that end on main/master, names the working doc in block messages, and lets the agent flag a misfired block instead of obeying it. (f6118f6, 542445b)
- Vendored `dotfiles` — nushell gains fish-style inline autosuggestions drawn from history recorded in the current folder; `$env.LOCAL_COMPLETIONS = 0` switches to whole-history hints. (469c0a8)
- Vendored `nu-goodies` — `copy-out --cwd` prepends the working directory as a comment line to the copied output. (1d36c21)
- Vendored `nushell-skills` — `nushell-style` now versions with the nushell minor it targets (1.114.0, covering the 0.114 breaking changes); `nushell-completions` 1.2.0. (03ac164)
- Shipped agent guidance gains two rules: question an instruction that conflicts with a concern before executing it, and stay skeptical of agent-written code passing through — surface suspicious things instead of ignoring them. (e58e30b, 60ab962)

### Fixed

- `cozy install nushell` no longer checks out the 2019-era `0_5_0` tag (whose dead rust toolchain broke the build) — upstream's legacy underscore tags sorted above modern `0.x.y` versions; the tag pick now filters to dot-separated numeric tags. (92e9758)
- Vendored modules and autoload scripts run clean on nushell 0.114 — adapted to `scan --fold`, `str lowercase`, stricter parse-time typing, and the new structured error `details`. (096d102, bb6566b, 0c66de4, 09c3545, f762022, 94e9bfa)

## [0.3.3] - 2026-07-03

### Changed

- All install paths (sbx kit, Dockerfile, host) now run one shared boot-tail script, so their command sequences can't drift apart; `./host-install.sh` is removed — run `cozy-module/install/run-install.sh` instead. The Homebrew it auto-installs on Linux now lands on PATH (`brew shellenv`) — previously the install succeeded but the very next command couldn't find brew. (45cb593)
- The Dockerfile is now marked legacy and unmaintained — with `docker sandbox` deprecated, the `sbx-kit/` in-sandbox build is the supported path. (4a7aa11)
- Vendored `numd` — new `numd run --dry-run` lists the blocks a file would execute without running them; unknown fence options now error instead of warn-and-run, and short-form fence options are removed. (4e7234b)
- Vendored `dotnu` — new `extract-module-command` pulls a command plus its full dependency cascade into one self-contained script, and `expand-code` generates code from `#**` directives; `embed-add` now folds in the capture config and requires sqlite history. (e297aa7, e8948dc)
- Vendored `nu-goodies` — `copy-out` strips the trailing `#exit_<code>` failure tag so the copied text matches the command shown on screen. (05128fb, d61ec1f)
- Vendored `dotfiles` — WezTerm QuickSelect matches two- and three-dot git commit ranges (`hash..hash`, `hash...hash`) as one block. (97eedc9)

### Fixed

- Inside an `sbx` sandbox `.DS_Store`/`Thumbs.db`/`desktop.ini` stopped being ignored — `sbx` sets `core.excludesFile` on every create, which shadows cozy's XDG ignore. A new autoload re-heals it on shell start by mirroring cozy's patterns into whatever excludesFile resolves to. (05fd413)
- The pbcopy shim now installs on every Linux host, not only in the docker step — on a plain Linux host every copy keybinding (helix, lazygit, broot, nushell, zellij, visidata) died with command-not-found. (3050e08)
- The no-flag install from the README no longer dies on a stock macOS shell — `run-install.sh` guarded empty args against bash 3.2 under `set -u`. (6d0a0f6)
- Bootstrap now fails fast on a Linux host without gcc instead of hitting a `sudo apt-get` prompt at step 8; the gcc/libc6-dev prerequisite is documented. (a56a4ab, 3ff3a56)
- A bootstrap re-run no longer silently overwrites uncommitted in-sandbox edits to `~/.config/*` — `--commit-existing` snapshots the prior state into git history first. (068112a)
- The kit's cozy clone can no longer hang on git's credential prompt (404 or proxy auth failure) — guarded with `GIT_TERMINAL_PROMPT=0`. (94cf1fb)
- The host install path no longer hangs on Homebrew's confirmation prompt — `ensure-nu.sh` now exports `HOMEBREW_NO_ASK`/`HOMEBREW_NO_AUTO_UPDATE` itself. (3b29e0b)
- `cozy verify` no longer false-fails the git-identity and JJ_CONFIG checks when run under the nushell MCP — it now reads the env from a login shell, so the result is the same however verify is launched. (b4c1aad)

## [0.3.2] - 2026-07-01

### Changed

- `toolkit docs` auto-discovers sandbox doc pages from Docker's `llms-full.txt` index instead of a hardcoded list, so new or renamed pages sync with no edit; it now also returns a `{discovered, ok, failed}` summary readable through the nushell MCP. (58cea01, 439b3aa)

### Removed

- Removed the host-side `nu toolkit/test.nu test` build check — `sbx` runs only registry images and can't test a local `docker build`, so `cozy verify` (run inside a sandbox) is now the only verification path. (e7d3811)

### Fixed

- `toolkit docs` no longer fails on sync — repointed from the retired `docker sandbox` doc URLs (now 404) to the current `sbx` pages. (bc174b0)

## [0.3.1] - 2026-07-01

### Added

- Nushell modules load in a non-interactive `nu -c` via `nu --config ~/.config/nushell/autoload/modules-core.nu -c …` (runs even in `-c`, unlike autoload). Helix's `shell` uses it, so its `:pipe`/snippet commands can call `kv`, `cozy`, `nu-goodies`, etc. (d99607c)

### Changed

- `sbx` is now the only documented run path; the deprecated `docker sandbox` command is dropped from completions and docs. Run with `sbx run shell --kit sbx-kit/` (in-sandbox build) — a local `docker build` image can't be fed to `sbx`. (8251c9f, 028d088)
- `cozy verify` returns the check table as a value instead of only printing it, so the nushell MCP, tests, and `cozy verify | where not pass` get structured data. (b8731de)
- Vendored `claude-nu` — new `claude-nu -f` regex search over project messages (`--all-projects`, `--no-rg`); session columns collapse to one `--columns` string; `ask` one-shot Claude wrapper split out. (ce11989)
- Vendored `dotfiles` — helix `s`/`S` copy repo-relative vs absolute file paths, `+ b` inserts nushell output as a table column; new `hx-nu` launcher loads cozy's nu modules; lazygit copies agent-ready file pointers. (610da85, c7c8c81)
- Vendored `my-claude-skills` — adds the Canvas output style. (c68f436)

### Fixed

- `brew install` no longer hangs the build — `HOMEBREW_NO_ASK=1` silences Homebrew's new confirmation prompt (no TTY in build); `HOMEBREW_NO_AUTO_UPDATE=1` also speeds and pins builds. (3645ca8, 3c23179)

## [0.3.0] - 2026-06-15

### Added

- `cozy verify` — run post-build checks against the sandbox you're in (binaries, vendored repos, autoload, env, MCP, topiary, git config). The same checks back `nu toolkit/test.nu test` from the host, deriving every expected value from the repo so they can't drift. (763d780)
- `zellij install --low-resource-compilation` builds zellij from source in a memory-tight VM by dropping optimization (opt-level=0, more codegen units) — trades runtime speed for a build that fits. Default build unchanged. (591d352, c789ae7)
- cozy now ships every `my-claude-skills` plugin, adding the `git-intent`, `git-intent-squash-archive`, and `gnuplot` skills to the sandbox. (5cc439b, 5747d3a)

### Changed

- Host installer no longer fetches modules from GitHub or rsyncs from sibling repos — it uses the committed `vendor/` snapshot as-is and fails fast if it's missing. Refreshing `vendor/` is `toolkit/vendor.nu`'s job before a build. (14b2941)
- `sbx` kit directory renamed `kit/` → `sbx-kit/`; the name now says which tool it's for. Invoke with `sbx run shell --kit cozy/sbx-kit/`. (8b3c9bf)
- Host installer renamed `bootstrap.sh` → `host-install.sh`. The name now says its role (host-only wrapper) and no longer collides with the core `bootstrap.nu`; `ensure-nu.sh` and `bootstrap.nu` are unchanged. (c0f2a74)
- Claude Code's "Show last response in external editor" is now on by default in built sandboxes (`externalEditorContext` in `~/.claude.json`). (d745e0d)
- visidata config now comes from the dotfiles repo (single source of truth) instead of a cozy-owned `.visidatarc`; the bundled config adds `zy` to copy a cell to both the internal and system clipboard. (77b372a, ba7f5e5, 6479476)
- Default Helix theme switched to `ayu_evolve`. (6e87c69)
- Vendored `claude-nu` — session commands reworked around a pipeline-native `projects | sessions | messages` flow; `parse-session` folded into `sessions`, plus per-message token usage as a cost signal for subscription users. (f91214d, 1b2aeb7)
- Vendored `nu-goodies` — `fzf-preview` gains `--content` (browse cell values) and `--column` (pick the path column); new `screen center` / `screen splash` center text in the terminal. (8f0dcf9, 746afb7)
- Vendored `nu-multiproof` — new `seal` runs the full timestamp-and-sign pipeline in one command. (fa88a4d)
- Vendored `nushell-skills` — `nushell-style` 1.5.0 and `nushell-completions` 1.1.1. (bd48206)

### Fixed

- Login banner (cozy logo + "run nu" hint) now prints once per session instead of 2-3 times. (83beebd)

## [0.2.5] - 2026-05-30

### Added

- `cozy logo` prints the cozy banner on demand; bash login now shows it above the nushell-launch hint. (545f151, 19d05af)
- `cozy sandbox-state` export/import now also carries the global `~/.claude/CLAUDE.md`, so user-level Claude instructions survive sandbox recreation alongside history and project sessions. (7a95bd7)

### Changed

- Dropped the `~/workspace/mounted` symlink — `$env.WORKSPACE_DIR` is now the single source of truth for the mounted workspace path; `cozy dev-link` and `cozy sandbox-state {history,projects,global-claude} {export,import}` default to it and hard-error when it's unset. (da9fb29)
- `wezterm-cozy` sets the sandbox window background via `--config` at spawn (new `--background` flag, no startup color flash) and launches the sandbox as a background job. (2ff0d77, f5e34af, 3be2adf)
- Zellij scrollback-edit keybindings reworked: `Super Shift e` edits the visible viewport in a floating Helix pane; full scrollback moves to `Super Alt e`. (7ddd1f8)
- `~/workspace/README.md` is now a workspace-orientation note (where modules and config live) instead of cozy's build doc. (1c28ee9)
- `vendor.nu` accepts a single repo name to refresh one module and auto-commits each refresh; `--no-commit` opts out. (af8e7f0, 0090e21)
- Pinned nushell fallback bumped 0.112.2 → 0.113.0 (used by `ensure-nu.sh` when the latest brew nu can't parse `bootstrap.nu`). (0247c42)
- Vendored `nu-goodies` — `hist --all-codes` shows commands of any exit status; `ansi-to-png` rewritten on ansisvg + rsvg-convert with a pure-black default background; `in-vd history` stashes the displayed history into the kv store for later recall. (b5ccdba, c1bbdc2, 55a1e84)
- Vendored `nushell-skills` — `nushell-style` 1.3.0 (adds 0.113 migration notes) plus a new `nushell-history` skill. (772ede4)

### Fixed

- visidata clipboard copy (`y`) uses the pbcopy/OSC 52 shim instead of `xclip`, which isn't installed in the sandbox. (57dbe16)
- Git `safe.directory='*'` re-asserted from the nushell autoload on shell start — `docker sandbox create` narrows it to the workspace root, tripping "dubious ownership" on the vendored repos beneath it. (c71afc5)
- `cozy sync-repos` now refreshes `nu-multiproof` — it was vendored but missing from the sync list, so it never updated without a rebuild. (3ba1e13)

## [0.2.4] - 2026-05-25

### Added

- `bootstrap.sh` auto-installs Homebrew on Linux when sudo is passwordless. On macOS or other prompting hosts it prints the `NONINTERACTIVE=1` install one-liner alongside the brew.sh link. (c9fe9cf, 5e6b6b1)
- Bash login prints a one-line hint to launch nushell — the `shell` agent drops into bash by default, but everything cozy ships is nu-first. (1f86c86)

### Changed

- Replaced `cozy platform` / `cozy platform apply` with a single narrow command `cozy swap-zellij-super` — rewrites Super→Alt in `~/.config/zellij/config.kdl` for Windows hosts. The old auto-detect was unreliable on Windows and a no-op elsewhere. (b88e29e)
- `sbx` CLI kit (`kit/spec.yaml`) clones cozy in-sandbox instead of bundling sources via `files/`. README gains an `### sbx kit` subsection under `Install elsewhere`. (9958cdf, d0347a6)

### Removed

- `toolkit/pack-kit.nu` and the `kit/files/` gitignore entry — superseded by the in-sandbox clone. (9958cdf)

### Fixed

- `WORKSPACE_DIR` from sbx on Windows hosts — translates `C:\Users\...` → `/c/Users/...` and normalizes backslashes, with hard-error on miss. (fff77fd, aac188b)
- `cozy install <plugin>` clones now fail loudly when an upstream URL is gone — git previously hung on a credential prompt because GitHub returns 404 for deleted repos. (c495b22)

## [0.2.3] - 2026-05-23

### Changed

- Renamed `sandbox-toolkit/` → `cozy-module/` — aligns the folder name with how it's loaded inside the sandbox (`overlay use ~/repos/cozy/cozy-module/ as cozy --prefix`). Custom scripts importing from the old path need updating. (674684d, b7636c8)
- Vendored `nu-goodies` — adds `fzf-preview` (pipe paths through fzf with bat preview, jumps to `file:line[:col]`) and `in-pane` (open a zellij pane running `nu --execute <command>`). (6395628)
- Vendored `nu-multiproof` — upstream refactor refresh: `--path` → `--repo` across commands; `tree-hashes` fixes for concurrent runs and bare `<manifest>.sig` detection. (86398d3)
- Vendored `dotfiles/wezterm` — QuickSelect `file:line` regex excludes `╭─[` so nushell error headers no longer match with the box-drawing prefix. (81e25dc)

### Fixed

- Bootstrap `claude install` no longer skips the real install during docker build. The `which claude` guard from e67ed1d matched the `claude install` module command itself (added by `use claude.nu`), making the subsequent `^claude mcp add` fail with `Command 'claude' not found`. Now filters to `type == external`. (a51a5c7)

## [0.2.2] - 2026-05-14

### Added

- `dotfiles/toolkit push-to-machine --delete-orphans` — removes machine files whose repo source has been deleted upstream. Opt-in; bootstrap does not pass it. (24e1ce7)

### Changed

- WezTerm `cmd+shift+n` / `alt+cmd+n` launch a fresh WezTerm instance via `open -n -a WezTerm --args start --always-new-process` — the old action collapsed new windows under the existing Dock icon. (7269696)
- Vendored `nu-cmd-stack` — `cmd-stack init` accepts `--quiet` and `--force-keybindings` directly. (a8af768)

### Removed

- Vendored dotfiles slash commands `/commit-git`, `/git-improve-history`, and the `commit-git` agent — superseded by upstream Claude Code's built-in `/commit-git` skill. (a03aaf2)

### Fixed

- `env.nu` defaults `XDG_CONFIG_HOME` from `$HOME` when unset — fresh macOS shells and pre-bootstrap sandboxes crashed nu with "Cannot find column XDG_CONFIG_HOME". (a2e6bfe)
- `cozy install bootstrap` skips the `claude.ai/install.sh` curl|bash when `claude` is already on PATH. (e67ed1d)

## [0.2.1] - 2026-05-14

### Added

- `bootstrap.sh` / `bootstrap.nu` `--force` flag. Host installs refuse to clobber existing user configs on first run — fail-fast guard checks `XDG_CONFIG_HOME/{nushell,helix,zellij,lazygit,broot,jj,git}`, `~/.claude/`, `~/.visidatarc`, `~/repos/`. Re-runs skip the guard via a `~/.cozy-installed` stamp. (b459662)
- Third install path: a Docker sandbox kit (`kit/spec.yaml`, `kind: mixin`) layered on the standard `shell` agent. Eliminates `docker build` for users who only want the cozy environment on top of stock `shell`.

### Fixed

- macOS host install exports `XDG_CONFIG_HOME="$HOME/.config"` to the user's shell rc (`~/.zshrc` or `~/.bash_profile`) — without it, `nu` on macOS read defaults from `~/Library/Application Support/nushell/` and missed the dotfiles cozy had just deployed. (40d94b7)

## [0.2.0] - 2026-05-12

### Added

- `cozy install bootstrap` — single end-to-end installer (brew tools, vendored modules under `~/repos/`, dotfiles, Claude skills, broot, topiary, Claude Code + nushell MCP). `--local` re-vendors from sibling repos for development. (0c69ad8)
- `cozy/bootstrap.sh` — host entry that ensures brew + nu, then execs `bootstrap.nu`. Docker and host paths share `bootstrap.nu`. (0d095e4)
- `ensure-nu.sh` + `.nushell-version` — version-pin fallback for nushell (pre-1.0, syntax drifts between releases). Tries latest brew nushell, smoke-tests it, falls back to the tested version (currently `0.112.2`) into `~/.local/bin/nu` on parse failure.
- `vendor.nu` honors `$env.GH_TOKEN` / `$env.GITHUB_TOKEN` — GitHub API limit jumps from 60 to 5000 req/hr when set. (f624b24)

### Changed

- Dockerfile collapsed from ~95 install lines to a single `RUN nu …/bootstrap.nu`. Host and Docker share one install path. (52d0c50)
- `--local` flag now means "force refresh from sibling repos"; host install consumes the committed `cozy/vendor/` as-is by default. (d60fb7e)
- Vendored `dotfiles/claude` — `editorMode=normal`, `verbose=true`, `cleanupPeriodDays=36500` baked into `~/.claude/settings.json`. (00c63b7, 86e43d0)
- Vendored `claude-nu` — `claude-export` gains `--tools` and `--include-thinking` flags. (7e8e4e7)
- Vendored `nutest` — broad refresh following vyadh/nutest main sync. (3fc1646)
- Vendored `nu-goodies` — `arrange.nu` updated from upstream. (3fc1646)

### Fixed

- `vendor.nu` uses `curl -fsSL` — HTTP errors fail at the network step with the real status code instead of feeding HTML into `tar xz`. (f624b24)
- Runtime git settings (`safe.directory '*'`, `gc.auto=0`, `core.fsync=all`, `.DS_Store` / `Thumbs.db` ignore) moved from `/etc/gitconfig` to `~/.config/git/` (XDG). Brew git's sysconfdir is `/home/linuxbrew/.linuxbrew/etc`, so `--system` writes never reached the runtime brew git. (288a2c9)
- Cold-start after `bash bootstrap.sh` no longer crashes `nu` on "Cannot find column XDG_DATA_HOME": `env.nu` defaults `XDG_DATA_HOME` from `$HOME` when unset. (4e546fc)
- `cozy install bootstrap` on macOS resolves `nu` via `which nu` for `claude mcp add` — previously hardcoded `/home/linuxbrew/.linuxbrew/bin/nu`, breaking Apple Silicon brew. (da7f93b)
- `topiary install` on macOS branches on OS and points users at `xcode-select --install` instead of running `sudo apt-get install`. (47946af)
- `populate-repos` runs `rm -rf` on each vendor destination before `cp -r` — files removed from upstream vendored modules no longer persist indefinitely. (362ce1f)
- Host bootstrap re-runs clean `~/.config/nushell/autoload/` before copying — stale autoload entries no longer linger. (121ee4a)

## [0.1.1] - 2026-04-29

### Added

- `cozy git-harden` — sets `gc.auto=0` and `receive.autoGc=false` in `.git/config` to prevent VirtioFS shared-mount corruption when host and sandbox both touch the same `.git/`. (ba35a06)
- `cozy install nushell`, `polars`, `nu-plugin-image`, `zellij` auto-install rust when missing. (b156778, d077ee5)

### Changed

- Sandbox `/etc/gitconfig` sets `gc.auto=0`, `core.fsync=all`, `core.fsyncMethod=fsync` — protects against VirtioFS corruption on shared host↔sandbox mounts. (ba35a06)
- `LANG=C.UTF-8` set as Dockerfile ENV — fixes git-delta showing UTF-8 multi-byte sequences as literal `<E2><80><94>` hex escapes through less. (ed407d1)
- Vendored `nu-kv` — `setp` shorthand for `pbpaste | set pbpaste`, and `kv get --pbcopy` flag to pipe values through `pbcopy`. (ab672c9)
- Vendored `nu-goodies` — new `rgv` wraps `rg --vimgrep` into a `{path, content}` table. (da884ca)
- Vendored `nu-cmd-stack` — `cmd-stack init` accepts `--quiet` and `--force-keybindings`. (d13dd1d)
- Vendored `nushell-skills` 1.2.0 — Nushell 0.100→0.112 migration guide. (33111cc)

### Fixed

- `cozy install nushell` timing out on flaky proxy — `~/.cargo/config.toml` written with `retry=5`, `http.timeout=120s`, sparse registry protocol. (1367dfb)
- `nu-complete sandbox names` completions broken — `docker sandbox ls --json` reports stale "running" status; switched to flat output. (8bf56ff)

## [0.1.0] - 2026-04-10

### Added

- `cozy install claude` — install Claude Code inside a running sandbox; complements `INSTALL_CLAUDE=false` from 0.0.9. (517703c)
- `--no-mcp` flag for `cozy install nushell` to skip MCP server registration. (cf1ab49)
- `fd` (fd-find) to the Homebrew install list. (29d9bc8)
- `nu-multiproof` vendored module. (d539cc0, 4c9d8df, 691b3c0)
- `vendor check` — detects new `nushell-prophet` repos not yet vendored; `--add` appends them to `vendor.yml`. (cb268a0, 11973ee)

### Changed

- Default vendoring downloads GitHub tarballs instead of full git clones — faster builds, no `.git/` bloat. (302275c)
- `vendor.nu` modules table extracted into `vendor.yml` as the single source of truth. (425ebe8)
- Nushell `vars_menu` rewritten to use fzf via `executehostcommand` — native menu broke after nushell 0.101 scope changes. (56cdac1)

### Removed

- Nushell keybindings `fzf_history_sessions` (Alt-Ctrl-F) and `paste_interpolation` (Alt-Shift-'). (56cdac1)

### Fixed

- Rust install scripts limit cargo parallelism and disable LTO — prevents OOM kills during `brew install` in memory-constrained build environments. (41f5782)
- `safe.directory = *` moved from `--global` to `--system` git config to survive `docker sandbox create` wiping `~/.gitconfig`. (25fc7b5)
- `core.excludesFile` re-bound at `--system` level — global gitignore was lost on sandbox recreation. (596f7b9)

## [0.0.9] - 2026-03-29

### Added

- `INSTALL_CLAUDE` build arg — pass `--build-arg INSTALL_CLAUDE=false` for an agent-free terminal environment. (7b88616)

### Changed

- `sync-repos` covers dotfiles, nutest, nushell-skills, my-claude-skills — previously required a full rebuild. (09fb006)
- Nushell pre_prompt hook tags history entries with non-zero exit codes, clears the tag on success. (f651592)

### Fixed

- Zellij `dump-screen` uses `--path` flag instead of positional argument, matching current zellij CLI. (f651592)

## [0.0.8] - 2026-03-25

### Changed

- Consolidated `cozy-docker-sandbox-toolkit` into `cozy/sandbox-toolkit/` — toolkit is no longer a separate repo. One `git pull` for both toolkit and vendored module updates. (f5e842c)

### Removed

- `cozy-docker-sandbox-toolkit` entry from `vendor.nu`. (f5e842c)

## [0.0.7] - 2026-03-25

### Added

- `cozy dev-link` — replace vendored `~/repos/` copies with symlinks to the mounted workspace for edit-and-test without rebuild. (1a36b53)
- `cozy configure claude-settings` — merges default Claude settings into sandbox. (1a36b53)
- `install-skills` dotfiles toolkit command — deploys Claude skills from sibling skill repos. (1a36b53)
- Helix keybindings: `Ctrl+w` write, `Ctrl+r` reload, `Ctrl+Shift+g` git-commit current buffer, `+ e` dotnu-embeds-update, `+ f` flatten-to-nuon, `+ g` git-commit, `+ n` timestamp, `+ p` pandoc reformat, `+ v` voice via kokoro, `+ C` remove commented output. (1a36b53)
- Nushell hook auto-renames Zellij tabs based on cwd. (1a36b53)

### Changed

- Helix whitespace rendering shows all characters (nbsp, newline, nnbsp, space). (1a36b53)
- Zellij `Super Shift e` uses built-in `EditScrollback` instead of custom dump-and-open-in-helix flow. (1a36b53)
- Zellij release notes disabled (`show_release_notes false`). (1a36b53)
- WezTerm SSH agent forwarding disabled (`mux_enable_ssh_agent = false`). (1a36b53)
- Nushell OSC 8 clickable links in `ls` output disabled. (1a36b53)

## [0.0.6] - 2026-03-24

### Added

- Claude Code skills vendored and deployed to `~/.claude/skills/` — nushell-style, nushell-completions, and my-skills plugins. (b1e2a53)
- `toolkit docs` — downloads Docker sandbox documentation as local markdown for offline reference. (991b20e)

## [0.0.5] - 2026-03-21

### Added

- Combined `sandbox-state export` / `sandbox-state import` — run both history and projects operations in one call. (4053c75)
- WezTerm config vendored into sandbox image. (172d4dc, 2da8940)

## [0.0.4] - 2026-03-21

### Added

- Global gitignore in sandbox image for `.DS_Store`, `Thumbs.db`, `desktop.ini`. (839aa13, ed6995f)

### Changed

- Vendor dotfiles selectively from sibling repo instead of cloning from GitHub at build time. (1898b2b)
- Vendor topiary-nushell to eliminate GitHub clone during default build — only tree-sitter-nu grammar compilation still needs network. (5cd891d)

## [0.0.3] - 2026-03-19

### Added

- `wezterm-cozy` — launches a WezTerm window into a sandbox with Zellij auto-attach. (97b77c6)
- `cozy-docker-sandbox-toolkit` available as `cozy` in Nushell autoload. (c895984, 25df314)

### Changed

- Zellij no longer shows startup tips. (9d5421b)

### Fixed

- Git operations on mounted workspace failing due to `safe.directory` ownership check — sandbox mounts have a different uid. (05b9cf5)

## [0.0.2] - 2026-03-18

### Added

- Topiary code formatter with Nushell grammar support. (b6a02fe)
- Git LFS. (63df5b2)
- `validate-docs` Claude Code skill — cross-references docs against code. (47f1ea9)

### Changed

- Renamed project from `ai-sandbox` to `cozy`; Docker image from `nushell-ai-sandbox` to `cozy`. (7cf05da)
- Companion toolkit renamed from `ai-sandbox-toolkit` to `cozy-docker-sandbox-toolkit`. (7cf05da)
- Base image switched from `docker/sandbox-templates:claude-code` to `docker/sandbox-templates:shell`; Claude Code installed via `claude.ai/install.sh` as a late layer — `claude-code` image updates frequently and invalidated cached layers on every rebuild. (8fa0652)
- Internal home directory renamed from `~/git/` to `~/repos/`. (f70b045)

### Removed

- Carapace completions engine. (63df5b2)

### Fixed

- Shift+Enter in WezTerm now works for Claude Code newlines. (73830f8)
- History export/import no longer uses symlinks — Docker sandbox doesn't preserve them. (907d5c6)

## [0.0.1] - 2026-03-08

### Added

- Docker sandbox-based terminal environment for AI agents, built on `docker/sandbox-templates:claude-code` with Homebrew toolchain. (42325d7, 92a25c6)
- Nushell as primary shell with autoload scripts and MCP server pre-configured for Claude Code. (f3effc3, 96944a9)
- Zellij terminal multiplexer with custom keybindings (`ctrl+shift+g` mode toggle, `cmd+t/n/w` for tabs and panes). (47c55a3)
- Helix editor configured with Nushell backend; `+ s` menu for XML-wrapped clipboard copy. (47c55a3)
- Lazygit with git-delta side-by-side diffs, accessible via `cmd+alt+l` in Zellij. (96944a9)
- Broot file manager with `:pbq` / `:pbfq` path-to-clipboard commands. (47c55a3)
- FZF integration for Nushell history navigation (`ctrl+f`, `alt+f`). (46e9b07)
- Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, ai-sandbox-toolkit. (f3effc3)
- WezTerm with kitty protocol keybindings, QuickSelect patterns, sandbox/zen mode support. (c53545b)
- OSC 52 clipboard shim for sandbox-to-host copy. (2f44e98)
- Supports `arm64` and `amd64` architectures via Docker sandbox.

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.3.4...HEAD
[0.3.4]: https://github.com/nushell-prophet/cozy/compare/0.3.3...0.3.4
[0.3.3]: https://github.com/nushell-prophet/cozy/compare/0.3.2...0.3.3
[0.3.2]: https://github.com/nushell-prophet/cozy/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/nushell-prophet/cozy/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/nushell-prophet/cozy/compare/0.2.5...0.3.0
[0.2.5]: https://github.com/nushell-prophet/cozy/compare/0.2.4...0.2.5
[0.2.4]: https://github.com/nushell-prophet/cozy/compare/0.2.3...0.2.4
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
