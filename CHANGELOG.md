# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.2] - 2026-03-18

### Added

- Topiary code formatter with Nushell grammar support
- Git LFS
- Initial dotfiles state committed at build time for trackable config changes
- `validate-docs` Claude Code skill for cross-referencing docs against code

### Changed

- Rename project from `ai-sandbox` to `cozy` and Docker image from `nushell-ai-sandbox` to `cozy`
- Rename companion toolkit from `ai-sandbox-toolkit` to `cozy-docker-sandbox-toolkit`
- Switch base image from `docker/sandbox-templates:claude-code` to `docker/sandbox-templates:shell`; install Claude Code via Anthropic's recommended install script (`claude.ai/install.sh`) as a late Dockerfile layer — the `claude-code` image updates frequently and invalidated all cached layers on every rebuild
- `nu-kv` store directory defaults to the workspace directory
- Sandbox state paths from `~/mounted` to `~/workspace/mounted`
- Sandbox `CLAUDE.md` appended to dotfiles `CLAUDE.md` instead of overwriting
- Internal home directory renamed from `~/git/` to `~/repos/`

### Removed

- Carapace completions engine

### Fixed

- Shift+Enter in WezTerm now works for Claude Code newlines
- History export/import no longer uses symlinks — Docker sandbox doesn't preserve them
- Build failure when git identity was not set before dotfiles clone

## [0.0.1] - 2026-03-08

### Added

- Docker sandbox-based terminal environment for AI agents, built on `docker/sandbox-templates:shell` with Homebrew toolchain and Claude Code installed via npm
- Nushell as primary shell with sensible defaults, autoload scripts, and MCP server pre-configured for Claude Code
- Zellij terminal multiplexer with custom keybindings (`ctrl+shift+g` mode toggle, `cmd+t/n/w` for tabs and panes)
- Helix editor configured with Nushell backend and `+ s` menu for XML-wrapped clipboard copy
- Lazygit with git-delta side-by-side diffs, accessible via `cmd+alt+l` in Zellij
- Broot file manager with `:pbq`/`:pbfq` path-to-clipboard commands
- FZF integration for Nushell history navigation (`ctrl+f`, `alt+f`)
- Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, cozy-docker-sandbox-toolkit
- Dotfiles deployment from my-dotfiles repo via `toolkit push-to-machine`
- WezTerm config with kitty protocol keybindings, QuickSelect patterns, and sandbox/zen mode support
- Git author attribution so Claude Code commits are attributed to `claude@anthropic.com`
- OSC 52 clipboard shim for sandbox-to-host copy
- Build and management toolkit (`build.nu`, `vendor.nu`) with sandbox create/recreate commands
- Sandbox image test script with tool launch verification
- Supports both `arm64` and `amd64` architectures via Docker sandbox

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.0.2...HEAD
[0.0.2]: https://github.com/nushell-prophet/cozy/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/nushell-prophet/cozy/releases/tag/0.0.1
