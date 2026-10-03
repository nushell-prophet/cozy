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
  - cozy-module/install/_nu-release.nu
reconciled-at: mzxsrtwkwnskuypxowpvxoowtpoqnrnw
---

# cozy install — why these compile from source

The per-tool builders behind `cozy install <tool>`.
`bootstrap.nu` invokes only two of them during the build (`topiary` in Step 8, `claude` in Step 9); the rest are on-demand.
Exposing them is deliberate: the user can build an up-to-date app inside the running sandbox, instead of being stuck with the version the build landed on.
The trade-off is build time — a large crate like polars takes a while.

What each builder *does* is in its own doc comment and code (wired in [`../cozy-module/install/mod.nu`](../cozy-module/install/mod.nu)).
This file records only why each one compiles from source rather than taking a packaged binary, and where `--github` takes the packaged binary instead.

Shared by every Rust-based builder: installs Rust on demand (skipped on the `--github` paths, which build nothing), and holds memory down for the small sandbox VM — `zellij`, `nushell` and `nu-plugin-image` build with `-j 1` + `profile.release.lto=false`, `polars` with `-j 1`.
Re-running skips the clone but rebuilds: only the already-built check in `polars` short-circuits.
Every cargo builder uses `--locked`, so a lockfile that drifted from `Cargo.toml` fails the build instead of being silently rewritten, and `cargo install` keeps the crate's own lockfile instead of resolving the newest compatible dependencies.
Clones go through `_clone-or-fail`, which sets `GIT_TERMINAL_PROMPT=0` so a 404 fails fast instead of hanging on git's credential prompt.
The built binary is put in place by `_install-binary`, never a plain `cp`: writing into a file the kernel is executing fails with `ETXTBSY`, which `cozy install nushell` hits every time it is run from the very nushell it replaces.
It copies beside the destination first (the build dir may sit on another filesystem, where a bare rename fails) and then `mv --force`s over the name, so a running process keeps its old inode and a failed replacement raises.
That staging copy is the external `^cp`, whose exit code raises: nushell's builtin `cp` prints an OS error to stderr and carries on, so a copy cut short (disk full) would be moved over a working binary.

- **claude** — official install script; skipped when `claude` is already on PATH (e.g. inside [`sbx run claude`](https://docs.docker.com/ai/sandboxes/agents/claude-code/), whose base image ships it).
- **rust** — via rustup.
  Writes `~/.cargo/config.toml` (retries, long timeout, sparse registry) to survive the flaky sandbox proxy, and raises `RUSTUP_MAX_RETRIES` for the fetcher that config does not cover: rustup never reads `~/.cargo/config.toml`, and a pinned toolchain (zellij's `rust-toolchain.toml`) is downloaded by rustup *before* cargo fetches a crate, so the first download died on the proxy with rustup's default of 3 tries.
  Exported with `--env` so it reaches the caller — the failing download happens in the calling builder's process, not in this one.
- **polars** — `nu_plugin_polars` from source, then `plugin add`.
  `--github` instead takes the binary from the nushell release tarball whose tag equals the running `nu` version — never the latest release, because a plugin loads only into the `nu` it was built for.
  A dev build of `nu` has no such release, so `--github` fails there and the source build stays the default.
- **topiary** — binary via brew, but the tree-sitter-nu grammar `.so` is compiled by hand (clone + gcc) because `topiary prefetch`'s HTTP client can fail behind the sandbox proxy.
- **zellij** — from source with `--no-default-features` to exclude `web_server_capability` (no web session sharing).
  `--low-resource-compilation` raises `codegen-units` and drops `opt-level` to 0 — the optimization passes are the dominant memory consumer.
  `--github` downloads the latest release binary instead: the `zellij-no-web-*` asset zellij publishes beside each release, the same feature set as the source build.
  `--web-server` opts in to the full asset with web session sharing; it needs `--github`, since the source build never has it.
  `--github` refuses `--low-resource-compilation`: there is no build to lower.
- **nushell** — from source so cozy can track the latest release (or `main` via `--dev`), and drop the `mcp` feature with `--no-mcp` when needed.
  `--github` downloads the latest release binary instead; it refuses `--dev` (main has no release) and `--no-mcp` (the release binary is built with MCP).
  Both `--github` paths share `_nu-release`: every nushell release tarball carries `nu` and the bundled plugins, `nu_plugin_polars` among them.
- **nu-plugin-image** — from source at the tag matching the running `nu` version; provides `to png` / `from png`.

**Code:** [`cozy-module/install/`](../cozy-module/install/) — one file per tool.
The boot sequence that calls them is in [`build.md`](build.md).
