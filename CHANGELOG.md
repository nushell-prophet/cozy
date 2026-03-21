# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Vendor topiary-nushell (languages.ncl, queries, LICENSE) to eliminate GitHub clone during default build — only tree-sitter-nu grammar compilation still requires network (5cd891d)

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

- Docker sandbox-based terminal environment for AI agents, built on `docker/sandbox-templates:shell` with Homebrew toolchain and Claude Code installed via npm (42325d7, 92a25c6)
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

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.0.3...HEAD
[0.0.3]: https://github.com/nushell-prophet/cozy/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/nushell-prophet/cozy/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/nushell-prophet/cozy/releases/tag/0.0.1
