---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/mod.nu
  - toolkit/vendor.nu
  - toolkit/vendor.yml
  - toolkit/check.nu
  - toolkit/docs.nu
  - cozy-module/vendored-repos.nuon
reconciled-at: 0eeb1329e2cc38cd941ba552592ecd09684ff189
---

# toolkit — host-side vendor tooling

Runs **on the host**, not inside the sandbox. The commands themselves are self-documenting (`help toolkit ...`); this file records only the packaging mechanism behind them.

## Vendoring modules

`toolkit vendor` refreshes [`vendor/`](../vendor/) — the packaging step that pulls module source into the repo, from where every install path copies it. [`../toolkit/vendor.yml`](../toolkit/vendor.yml) is the source of truth: each entry is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of the upstream repo into `vendor/<repo>/`.

- Default pulls GitHub tarballs; `--local` rsyncs from the sibling repos next to `cozy/` instead — the edit-locally-then-vendor loop.
- Refreshing all wipes the whole `vendor/`; naming one repo wipes just that dir. Auto-commits unless `--no-commit`.
- `toolkit vendor check` lists `nushell-prophet` repos not yet in `vendor.yml`.
- Each run regenerates [`../cozy-module/vendored-repos.nuon`](../cozy-module/vendored-repos.nuon) — a repo→clone-URL projection of `vendor.yml` (plus `cozy` itself). `cozy sync-repos` runs **inside** the sandbox, where the host-only `vendor.yml` isn't shipped, so it reads this generated manifest instead. `vendor.yml` stays the single authored source; the manifest is derived and committed alongside the `vendor/` bump.

Wired in [`toolkit/vendor.nu`](../toolkit/vendor.nu).

## Consistency checks

`toolkit check` (in [`toolkit/check.nu`](../toolkit/check.nu)) is a host-side guard, no sandbox needed — run it before building. Two invariants that nothing else enforces:

- The env block (XDG dirs, `HELIX_RUNTIME`, `LANG`) is spelled out three times — [`../Dockerfile`](../Dockerfile) `ENV`, [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml) `environment.variables`, and the `export` block `bootstrap.nu` writes to `/etc/sandbox-persistent.sh`. The three formats can't share one literal, so the check asserts they agree and fails loud on drift. The `PATH` prefix is checked across two of the three only — `bootstrap.nu`'s block writes no `PATH`, so `check.nu` records it as `(n/a)` there.
- `vendored-repos.nuon` matches `vendor.yml` (catches a manifest left stale).

## Local docs

`toolkit docs` (in [`toolkit/docs.nu`](../toolkit/docs.nu), wired into `mod.nu` alongside `vendor` and `check`) syncs Docker sandbox docs into `docs.docker.com/` (its own gitignored repo). Pages are auto-discovered from docs.docker.com's `llms-full.txt` index, filtered to the sandbox/sbx path prefixes — no hardcoded page list to keep in sync. Idempotent.
