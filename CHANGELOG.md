# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Rename project from `ai-sandbox` to `cozy` and Docker image from `nushell-ai-sandbox` to `cozy`
- Rename companion toolkit from `ai-sandbox-toolkit` to `cozy-docker-sandbox-toolkit`

## [0.0.1] - 2026-03-08

### Added

- Docker sandbox-based terminal environment for AI agents, built on `docker/sandbox-templates:claude-code` with Homebrew toolchain
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

[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.0.1...HEAD
[0.0.1]: https://github.com/nushell-prophet/cozy/releases/tag/0.0.1
