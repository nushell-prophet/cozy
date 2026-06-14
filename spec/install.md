---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-spec reconciles this file against
  - cozy-module/install/mod.nu
  - cozy-module/install/claude.nu
  - cozy-module/install/rust.nu
  - cozy-module/install/polars.nu
  - cozy-module/install/topiary.nu
  - cozy-module/install/zellij.nu
  - cozy-module/install/nushell.nu
  - cozy-module/install/nu-plugin-image.nu
  - cozy-module/install/_clone-or-fail.nu
---

# cozy install sub-surface

The per-tool builders `bootstrap.nu` invokes during the build (and that `cozy install <tool>` re-runs on demand). Exports are wired in `../cozy-module/install/mod.nu`. The boot sequence that calls these lives in `build.md`.

Each entry: **Purpose** is the first line of the command's own doc comment (verbatim). **Flags** are derived from the signature. **Code** points at the symbol; the full rationale stays there. Each `cozy install <tool>` is a thin wrapper that imports the tool's own `install` and forwards flags — the contract below is the `install` it calls.

Entries follow `mod.nu` export order. Every Rust-based builder is idempotent (safe to re-run, skips steps already done), installs Rust on demand, and compiles with `-j 1` plus `profile.release.lto=false` to survive the small sandbox VM's RAM. Each clone goes through the `_clone-or-fail` helper (last entry).

## cozy install bootstrap
End-to-end install: brew tools, vendored modules, dotfiles, skills, broot, topiary, Claude Code + nushell MCP.
**Flags:** `--local` forces a vendor refresh from sibling repos; Docker vs. host is auto-detected via filesystem markers
**Code:** `cozy-module/install/mod.nu` → `export use bootstrap.nu`
See `build.md` for the step-by-step boot sequence.

## cozy install claude
Install claude using official install script.
Skipped when `claude` is already on PATH (e.g. inside `sbx run claude`, whose base image ships Claude Code pre-installed).
**Code:** `cozy-module/install/claude.nu` → `export def install`

## cozy install rust
Install Rust via rustup.
Idempotent — skips if `rustc` is present. Writes `~/.cargo/config.toml` (retry 5, 120s timeout, sparse registry) to survive the flaky sandbox proxy; installs `build-essential` if no C linker; strips a bad `source ...env.nu` line rustup appends to `config.nu`.
**Code:** `cozy-module/install/rust.nu` → `export def install`

## cozy install polars
Install nu_plugin_polars and register it with Nushell.
Compiles `nu_plugin_polars` from source (skipped if the binary already exists), then `plugin add`s it. Restart Nushell or `plugin use polars` to load.
**Code:** `cozy-module/install/polars.nu` → `export def install`

## cozy install topiary
Install topiary formatter with nushell support.
Installs the topiary binary via brew, clones `topiary-nushell` (grammar/queries), copies `languages.ncl` with a 4-space indent override, symlinks `queries/nu.scm` into `~/.config/topiary/`, and compiles the tree-sitter-nu grammar `.so` by hand (cloning tree-sitter-nu and running gcc) rather than `topiary prefetch`, whose HTTP client fails behind proxies.
**Code:** `cozy-module/install/topiary.nu` → `export def install`

## cozy install zellij
Build zellij from source without web session sharing.
Clones the repo, checks out the latest `v*` tag, and builds with `--no-default-features` (excludes `web_server_capability`). Uninstalls a brew-provided zellij if present, then copies the binary into `~/.cargo/bin`.
**Flags:** `--low-resource-compilation` — split codegen into smaller units to lower peak RAM (avoids OOM in small VMs)
**Code:** `cozy-module/install/zellij.nu` → `export def install`

## cozy install nushell
Build nushell from source.
Default builds the latest release tag. `--dev` builds `main`. `--no-mcp` drops the `mcp` default feature (warns and falls back to all defaults if `mcp` isn't a default). Copies the binary into `~/.cargo/bin`.
**Flags:** `--dev` build from main instead of latest release; `--no-mcp` build without MCP support
**Code:** `cozy-module/install/nushell.nu` → `export def install`
> NOTE: mod.nu's doc comment says "(latest release or --dev for main)"; the command's own first doc line is "Build nushell from source." — used the command's line per the verbatim rule.

## cozy install nu-plugin-image
Build nu_plugin_image from source and register it with Nushell.
Clones the repo, checks out the tag matching the running Nushell version (`v<nu-version>`), builds `--locked`, copies the binary into `~/.cargo/bin`, and `plugin add`s it. Provides `to png` and `from png`. Restart Nushell or `plugin use image` to load.
**Code:** `cozy-module/install/nu-plugin-image.nu` → `export def install`

## _clone-or-fail (helper)
Wraps `git clone` with `GIT_TERMINAL_PROMPT=0` so a 404 over HTTPS fails immediately instead of hanging on git's credential prompt.
Used by `topiary`, `zellij`, `nushell`, and `nu-plugin-image` for every repo clone. Not a `cozy install` subcommand.
**Code:** `cozy-module/install/_clone-or-fail.nu` → `export def main`
