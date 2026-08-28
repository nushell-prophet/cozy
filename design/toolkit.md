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
reconciled-at: 874e4a409b8c7877a9c05a0db8f6acbefd07b1ef
---

# toolkit — host-side vendor tooling

Runs **on the host**, not inside the sandbox. The commands themselves are self-documenting (`help toolkit ...`); this file records only the packaging mechanism behind them. [`toolkit/mod.nu`](../toolkit/mod.nu) is the wiring: it re-exports `vendor`, `docs`, `check`, `container` and `sbxw`.

**One name per command.** `container.nu` and `vendor.nu` dispatch on `main <sub>` so the script form works (`nu toolkit/container.nu up …`), but a module import leaves that `main` in the middle — nushell collapses only a bare `main` into the module name, so the import would read `container main up`. Each subcommand therefore gets an `export alias` without it, and the `def` behind the alias is deliberately **not** exported: exporting both listed every command twice, once under each name. Script dispatch finds `main <sub>` in the file's own scope either way, and `help toolkit container up` still reaches the real flags through the alias. Each alias repeats its command's first doc line, because an alias with no comment of its own describes itself as an alias.

## Vendoring modules

`toolkit vendor` refreshes [`vendor/`](../vendor/) — the packaging step that pulls module source into the repo, from where every install path copies it. [`../toolkit/vendor.yml`](../toolkit/vendor.yml) is the source of truth: each entry is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of the upstream repo into `vendor/<repo>/`.

- Default pulls GitHub tarballs; `--local` rsyncs from the sibling repos next to `cozy/` instead — the edit-locally-then-vendor loop.
- Refreshing all wipes the whole `vendor/`; naming one repo wipes just that dir. Auto-commits unless `--no-commit`.
- `toolkit vendor check` lists `nushell-prophet` repos not yet in `vendor.yml`.
- Each run regenerates [`../cozy-module/vendored-repos.nuon`](../cozy-module/vendored-repos.nuon) — a repo→clone-URL projection of `vendor.yml` (plus `cozy` itself). `cozy sync-repos` runs **inside** the sandbox, where the host-only `vendor.yml` isn't shipped, so it reads this generated manifest instead. `vendor.yml` stays the single authored source; the manifest is derived and committed alongside the `vendor/` bump.

Wired in [`toolkit/vendor.nu`](../toolkit/vendor.nu).

## Consistency checks

`toolkit check` (in [`toolkit/check.nu`](../toolkit/check.nu)) is a host-side guard, no sandbox needed — run it before building. Three invariants that nothing else enforces:

- The env block is spelled out in three places — [`../Dockerfile`](../Dockerfile) `ENV`, [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml) `environment.variables`, and the `export` block `bootstrap.nu` writes to `/etc/sandbox-persistent.sh`. The three formats can't share one literal, so the check asserts they agree and fails loud on drift. Two key sets, because not every key belongs in all three: the *shared* five (XDG dirs, `HELIX_RUNTIME`, `LANG`) are compared across all three, and the *paired* five (`TERM`, `COLORTERM`, `TERM_PROGRAM`, `HOMEBREW_NO_ASK`, `HOMEBREW_NO_AUTO_UPDATE`) only across Dockerfile and kit — they are deliberately absent from `bootstrap.nu`'s block, which every login shell sources, and `TERM` belongs to the terminal that connected. A paired key missing from one of the two counts as drift rather than being skipped. `HOME` is in neither set: the Dockerfile omits it on purpose, so only the kit spells it out. The `PATH` is a *prefix* comparison across the same two — `bootstrap.nu`'s block writes no `PATH` (recorded as `(n/a)`), and the Dockerfile's tail is the base image's `${PATH}`, which no file here can say, so checking the full tail would only hardcode a second guess. Values are normalized before comparing (`$HOME`/`${HOME}` → `/home/agent`), because the kit spells the paths out while the other two expand a variable.
- `vendored-repos.nuon` matches `vendor.yml` (catches a manifest left stale).
- The egress proxy image is pinned by digest and identical in its two copies — `services.egress.image` in [`../compose.yaml`](../compose.yaml) and `egress_image` in [`toolkit/container.nu`](../toolkit/container.nu). Both cage the agent behind the same proxy holding the same policy, so the two literals must agree. The `@sha256:` is asserted separately: swapping in a floating tag silently un-pins the one container that has internet, and comparing the copies alone would not catch it. See [`firewall.md`](firewall.md).

## Driving a run path from the host

Two run paths need host-side orchestration; they are split by runtime rather than by job, because almost nothing generalizes between them.

- [`toolkit/container.nu`](../toolkit/container.nu) — the Apple `container` path (`up` / `restart` / `reload-egress` / `refresh-egress` / `attach`), i.e. what `compose.yaml` plus `docker compose exec` are for the docker path. `container` has no compose, so the three pieces compose declares are assembled by hand: a host-only network with no way out, a squid dual-homed onto it and the default network, and the cozy container attached to the caged one only. Same image, same policy directory, same residual risks — see [`firewall.md`](firewall.md). Needs macOS 26+: `container network create` does not exist before it, and without the network there is no cage at all. `attach` restarts the pair when the container is not running — both-stopped is exactly what a runtime restart leaves behind, and `attach` is the command a human reaches for then, so it heals rather than opening a window on a `container exec` that cannot enter. `up --ssh-agent` forwards the host's ssh-agent socket into the container; inside the cage that is for signing only — see [`firewall.md`](firewall.md).
- [`toolkit/sbxw.nu`](../toolkit/sbxw.nu) — the sbx twin of `container attach`: open a sandbox in a new WezTerm window and attach its zellij session. It knows nothing about the cage.

Opening the window needs an **interactive** nu (`use toolkit/sbxw.nu`, not `nu toolkit/sbxw.nu`; same for `container attach`): the window is a background job, and a job dies with the one-shot nu that spawned it. That holds for `sbxw` and `container attach` only — `container up` / `restart` / `reload-egress` / `refresh-egress` run fine as `nu toolkit/container.nu <sub>`, and the script form is the safer one anyway: an imported module can serve a stale definition long after the file changed (see [`autoload.md`](autoload.md)), which is how a moved egress pin was nearly recorded as applied while the old proxy came back up. The one thing the two paths genuinely share — opening that window — lives in [`toolkit/wezterm.nu`](../toolkit/wezterm.nu), which both `use`.

## Local docs

`toolkit docs` (in [`toolkit/docs.nu`](../toolkit/docs.nu), wired into `mod.nu` alongside `vendor` and `check`) syncs Docker sandbox docs into `docs.docker.com/` (its own gitignored repo). Pages are auto-discovered from docs.docker.com's `llms-full.txt` index, filtered to the sandbox/sbx path prefixes — no hardcoded page list to keep in sync. Idempotent.
