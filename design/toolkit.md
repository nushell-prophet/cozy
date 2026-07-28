---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/mod.nu
  - toolkit/vendor.nu
  - toolkit/vendor.yml
  - toolkit/check.nu
  - toolkit/docs.nu
  - toolkit/container.nu
  - toolkit/sbxw.nu
  - toolkit/wezterm.nu
  - cozy-module/vendored-repos.nuon
reconciled-at: 6dd20b1779e5df6bb4a2f60d02c1aa7674d2389d
---

# toolkit — host-side vendor tooling

Runs **on the host**, not inside the sandbox. The commands themselves are self-documenting (`help toolkit ...`); this file records only the packaging mechanism behind them. [`toolkit/mod.nu`](../toolkit/mod.nu) is the wiring: it re-exports `vendor`, `docs`, `check`, `container` and `sbxw`.

## Vendoring modules

`toolkit vendor` refreshes [`vendor/`](../vendor/) — the packaging step that pulls module source into the repo, from where every install path copies it. [`../toolkit/vendor.yml`](../toolkit/vendor.yml) is the source of truth: each entry is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of the upstream repo into `vendor/<repo>/`.

- Default pulls GitHub tarballs; `--local` rsyncs from the sibling repos next to `cozy/` instead — the edit-locally-then-vendor loop.
- Refreshing all wipes the whole `vendor/`; naming one repo wipes just that dir. Auto-commits unless `--no-commit`.
- `toolkit vendor check` lists `nushell-prophet` repos not yet in `vendor.yml`.
- Each run regenerates [`../cozy-module/vendored-repos.nuon`](../cozy-module/vendored-repos.nuon) — a repo→clone-URL projection of `vendor.yml` (plus `cozy` itself). `cozy sync-repos` runs **inside** the sandbox, where the host-only `vendor.yml` isn't shipped, so it reads this generated manifest instead. `vendor.yml` stays the single authored source; the manifest is derived and committed alongside the `vendor/` bump.

Wired in [`toolkit/vendor.nu`](../toolkit/vendor.nu).

## Consistency checks

`toolkit check` (in [`toolkit/check.nu`](../toolkit/check.nu)) is a host-side guard, no sandbox needed — run it before building. Three invariants that nothing else enforces:

- The env block (XDG dirs, `HELIX_RUNTIME`, `LANG`) is spelled out three times — [`../Dockerfile`](../Dockerfile) `ENV`, [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml) `environment.variables`, and the `export` block `bootstrap.nu` writes to `/etc/sandbox-persistent.sh`. The three formats can't share one literal, so the check asserts they agree and fails loud on drift. The `PATH` prefix is checked across two of the three only — `bootstrap.nu`'s block writes no `PATH`, so `check.nu` records it as `(n/a)` there. Values are normalized before comparing (`$HOME`/`${HOME}` → `/home/agent`), because the kit spells the paths out while the other two expand a variable.
- `vendored-repos.nuon` matches `vendor.yml` (catches a manifest left stale).
- The egress proxy image is pinned by digest and identical in its two copies — `services.egress.image` in [`../compose.yaml`](../compose.yaml) and `egress_image` in [`toolkit/container.nu`](../toolkit/container.nu). Both cage the agent behind the same proxy holding the same policy, so the two literals must agree. The `@sha256:` is asserted separately: swapping in a floating tag silently un-pins the one container that has internet, and comparing the copies alone would not catch it. See [`firewall.md`](firewall.md).

## Driving a run path from the host

Two run paths need host-side orchestration; they are split by runtime rather than by job, because almost nothing generalizes between them.

- [`toolkit/container.nu`](../toolkit/container.nu) — the Apple `container` path (`up` / `restart` / `reload-egress` / `attach`), i.e. what `compose.yaml` plus `docker compose exec` are for the docker path. `container` has no compose, so the three pieces compose declares are assembled by hand: a host-only network with no way out, a squid dual-homed onto it and the default network, and the agent attached to the caged one only. Same image, same policy directory, same residual risks — see [`firewall.md`](firewall.md). Needs macOS 26+: `container network create` does not exist before it, and without the network there is no cage at all.
- [`toolkit/sbxw.nu`](../toolkit/sbxw.nu) — the sbx twin of `container attach`: open a sandbox in a new WezTerm window and attach its zellij session. It knows nothing about the cage.

Opening the window needs an **interactive** nu (`use toolkit/sbxw.nu`, not `nu toolkit/sbxw.nu`; same for `container attach`): the window is a background job, and a job dies with the one-shot nu that spawned it. That holds for `sbxw` and `container attach` only — `container up` / `restart` / `reload-egress` run fine as `nu toolkit/container.nu <sub>`. The one thing the two paths genuinely share — opening that window — lives in [`toolkit/wezterm.nu`](../toolkit/wezterm.nu), which both `use`.

## Local docs

`toolkit docs` (in [`toolkit/docs.nu`](../toolkit/docs.nu), wired into `mod.nu` alongside `vendor` and `check`) syncs Docker sandbox docs into `docs.docker.com/` (its own gitignored repo). Pages are auto-discovered from docs.docker.com's `llms-full.txt` index, filtered to the sandbox/sbx path prefixes — no hardcoded page list to keep in sync. Idempotent.
