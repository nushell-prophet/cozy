---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/mod.nu
  - toolkit/vendor.nu
  - toolkit/vendor.yml
  - toolkit/docs.nu
  - toolkit/test.nu
---

# toolkit — host-side vendor tooling

Runs **on the host**, not inside the sandbox. The commands themselves are self-documenting (`help toolkit ...`); this file records only the packaging mechanism behind them.

## Vendoring modules

`toolkit vendor` refreshes `vendor/` — the packaging step that pulls module source into the image. `../toolkit/vendor.yml` is the source of truth: each entry is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of the upstream repo into `vendor/<repo>/`.

- Default pulls GitHub tarballs; `--local` rsyncs from sibling `~/repos/` instead — the edit-locally-then-vendor loop.
- Refreshing all wipes the whole `vendor/`; naming one repo wipes just that dir. Auto-commits unless `--no-commit`.
- `toolkit vendor check` lists `nushell-prophet` repos not yet in `vendor.yml`.

Wired in `toolkit/vendor.nu`.

## Standalone (not wired into `mod.nu`)

- `toolkit/docs.nu` — syncs Docker sandbox docs into `docs.docker.com/` (its own gitignored repo). Idempotent.
- `toolkit/test.nu` — smoke-tests a fresh sandbox (`nu toolkit/test.nu test`): tools launch, files/dirs/env exist, MCP + pbcopy wiring is in place.
