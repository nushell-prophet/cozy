# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, cozy-docker-sandbox-toolkit (f3effc3)
- Dotfiles deployment from my-dotfiles repo via `toolkit push-to-machine` (47c55a3)
- WezTerm config with kitty protocol keybindings, QuickSelect patterns, and sandbox/zen mode support (c53545b)
- Git author attribution so Claude Code commits are attributed to `claude@anthropic.com` (0cb6fbc)
- OSC 52 clipboard shim for sandbox-to-host copy (2f44e98)
- Build and management toolkit (`build.nu`, `vendor.nu`) with sandbox create/recreate commands (75111b8, cf612a5)
- Sandbox image test script with tool launch verification (a333bb6)
- Supports both `arm64` and `amd64` architectures via Docker sandbox

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.0.8...HEAD
[0.0.8]: https://github.com/nushell-prophet/cozy/compare/0.0.7...0.0.8
[0.0.7]: https://github.com/nushell-prophet/cozy/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/nushell-prophet/cozy/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/nushell-prophet/cozy/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/nushell-prophet/cozy/compare/0.0.3...0.0.4
[0.0.3]: https://github.com/nushell-prophet/cozy/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/nushell-prophet/cozy/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/nushell-prophet/cozy/releases/tag/0.0.1
