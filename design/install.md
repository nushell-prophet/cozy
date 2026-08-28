---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - cozy-module/install/mod.nu
  - cozy-module/install/claude.nu
  - cozy-module/install/rust.nu
  - cozy-module/install/polars.nu
  - cozy-module/install/topiary.nu
  - cozy-module/install/zellij.nu
  - cozy-module/install/nushell.nu
  - cozy-module/install/nu-plugin-image.nu
  - cozy-module/install/_clone-or-fail.nu
  - cozy-module/install/_install-binary.nu
reconciled-at: 874e4a409b8c7877a9c05a0db8f6acbefd07b1ef
---

# cozy install — why these compile from source

The per-tool builders behind `cozy install <tool>`.
`bootstrap.nu` invokes only two of them during the build (`topiary` in Step 8, `claude` in Step 9); the rest are on-demand.
Exposing them is deliberate: the user can build an up-to-date app inside the running sandbox, instead of being stuck with the version the build landed on.
The trade-off is build time — a large crate like polars takes a while.

What each builder *does* is in its own doc comment and code (wired in [`../cozy-module/install/mod.nu`](../cozy-module/install/mod.nu)).
This file records only why each one compiles from source rather than taking a packaged binary.

Shared by every Rust-based builder: installs Rust on demand, and holds memory down for the small sandbox VM — `zellij`, `nushell` and `nu-plugin-image` build with `-j 1` + `profile.release.lto=false`, `polars` with `-j 1`.
Re-running skips the clone but rebuilds: only the already-built check in `polars` short-circuits.
Clones go through `_clone-or-fail`, which sets `GIT_TERMINAL_PROMPT=0` so a 404 fails fast instead of hanging on git's credential prompt.
The built binary is put in place by `_install-binary`, never a plain `cp`: writing into a file the kernel is executing fails with `ETXTBSY`, which `cozy install nushell` hits every time it is run from the very nushell it replaces — and nushell's `cp` only prints that error to stderr, so the install used to report success over an unchanged binary.
It copies beside the destination first (the build dir may sit on another filesystem, where a bare rename fails) and then `mv --force`s over the name, so a running process keeps its old inode and a failed replacement raises.

- **claude** — official install script; skipped when `claude` is already on PATH (e.g. inside [`sbx run claude`](https://docs.docker.com/ai/sandboxes/agents/claude-code/), whose base image ships it).
- **rust** — via rustup.
  Writes `~/.cargo/config.toml` (retries, long timeout, sparse registry) to survive the flaky sandbox proxy, and raises `RUSTUP_MAX_RETRIES` for the fetcher that config does not cover: rustup never reads `~/.cargo/config.toml`, and a pinned toolchain (zellij's `rust-toolchain.toml`) is downloaded by rustup *before* cargo fetches a crate, so the first download died on the proxy with rustup's default of 3 tries.
  Exported with `--env` so it reaches the caller — the failing download happens in the calling builder's process, not in this one.
- **polars** — `nu_plugin_polars` from source, then `plugin add`.
  Source because there's no packaged build matching the running `nu`.
- **topiary** — binary via brew, but the tree-sitter-nu grammar `.so` is compiled by hand (clone + gcc) because `topiary prefetch`'s HTTP client can fail behind the sandbox proxy.
- **zellij** — from source with `--no-default-features` to exclude `web_server_capability` (no web session sharing).
  `--low-resource-compilation` raises `codegen-units` and drops `opt-level` to 0 — the optimization passes are the dominant memory consumer.
- **nushell** — from source so cozy can track the latest release (or `main` via `--dev`), and drop the `mcp` feature with `--no-mcp` when needed.
- **nu-plugin-image** — from source at the tag matching the running `nu` version; provides `to png` / `from png`.

**Code:** [`cozy-module/install/`](../cozy-module/install/) — one file per tool.
The boot sequence that calls them is in [`build.md`](build.md).
