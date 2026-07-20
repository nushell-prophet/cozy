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
reconciled-at: 0eeb1329e2cc38cd941ba552592ecd09684ff189
---

# cozy install — why these compile from source

The per-tool builders `bootstrap.nu` invokes during the build, also exposed as `cozy install <tool>`. Exposing them is deliberate: the user can build an up-to-date app on demand inside the running sandbox, instead of being stuck with the version baked into the image. The trade-off is build time — a large crate like polars takes a while.

What each builder *does* is in its own doc comment and code (wired in [`../cozy-module/install/mod.nu`](../cozy-module/install/mod.nu)). This file records only why each one compiles from source rather than taking a packaged binary.

Shared by every Rust-based builder: idempotent (skips work already done), installs Rust on demand, and compiles with `-j 1` + `profile.release.lto=false` — the small sandbox VM runs out of RAM otherwise. Clones go through `_clone-or-fail`, which sets `GIT_TERMINAL_PROMPT=0` so a 404 fails fast instead of hanging on git's credential prompt.

- **claude** — official install script; skipped when `claude` is already on PATH (e.g. inside `sbx run claude`, whose base image ships it).
- **rust** — via rustup. Writes `~/.cargo/config.toml` (retries, long timeout, sparse registry) to survive the flaky sandbox proxy.
- **polars** — `nu_plugin_polars` from source, then `plugin add`. Source because there's no packaged build matching the running `nu`.
- **topiary** — binary via brew, but the tree-sitter-nu grammar `.so` is compiled by hand (clone + gcc) because `topiary prefetch`'s HTTP client fails behind the proxy.
- **zellij** — from source with `--no-default-features` to exclude `web_server_capability` (no web session sharing). `--low-resource-compilation` splits codegen to avoid OOM in small VMs.
- **nushell** — from source so cozy can track the latest release (or `main` via `--dev`), and drop the `mcp` feature with `--no-mcp` when needed.
- **nu-plugin-image** — from source at the tag matching the running `nu` version; provides `to png` / `from png`.

**Code:** [`cozy-module/install/`](../cozy-module/install/) — one file per tool. The boot sequence that calls them is in [`build.md`](build.md).
