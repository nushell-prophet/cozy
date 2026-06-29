---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/mod.nu
  - toolkit/vendor.nu
  - toolkit/vendor.yml
  - toolkit/check.nu
  - toolkit/docs.nu
  - toolkit/test.nu
  - cozy-module/vendored-repos.nuon
---

# toolkit — host-side vendor tooling

Runs **on the host**, not inside the sandbox. The commands themselves are self-documenting (`help toolkit ...`); this file records only the packaging mechanism behind them.

## Vendoring modules

`toolkit vendor` refreshes `vendor/` — the packaging step that pulls module source into the image. `../toolkit/vendor.yml` is the source of truth: each entry is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of the upstream repo into `vendor/<repo>/`.

- Default pulls GitHub tarballs; `--local` rsyncs from sibling `~/repos/` instead — the edit-locally-then-vendor loop.
- Refreshing all wipes the whole `vendor/`; naming one repo wipes just that dir. Auto-commits unless `--no-commit`.
- `toolkit vendor check` lists `nushell-prophet` repos not yet in `vendor.yml`.
- Each run regenerates `../cozy-module/vendored-repos.nuon` — a repo→clone-URL projection of `vendor.yml` (plus `cozy` itself). `cozy sync-repos` runs **inside** the sandbox, where the host-only `vendor.yml` isn't shipped, so it reads this generated manifest instead. `vendor.yml` stays the single authored source; the manifest is derived and committed alongside the `vendor/` bump.

Wired in `toolkit/vendor.nu`.

## Consistency checks

`toolkit check` (in `toolkit/check.nu`) is a host-side guard, no sandbox needed — run it before building. Two invariants that nothing else enforces:

- The env block (XDG dirs, `HELIX_RUNTIME`, `LANG`, the `PATH` prefix) is spelled out three times — `../Dockerfile` `ENV`, `../sbx-kit/spec.yaml` `environment.variables`, and the `export` block `bootstrap.nu` writes to `/etc/sandbox-persistent.sh`. The three formats can't share one literal, so the check asserts they agree and fails loud on drift.
- `vendored-repos.nuon` matches `vendor.yml` (catches a manifest left stale).

## Local docs

`toolkit docs` (in `toolkit/docs.nu`, wired into `mod.nu` alongside `vendor` and `check`) syncs Docker sandbox docs into `docs.docker.com/` (its own gitignored repo). Idempotent.

## Standalone (not wired into `mod.nu`)

- `toolkit/test.nu` — smoke-tests a fresh sandbox (`nu toolkit/test.nu test`): tools launch, files/dirs/env exist, MCP + pbcopy wiring is in place. Run directly; not exported from `mod.nu`.
