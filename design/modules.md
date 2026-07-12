---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/vendor.yml
  - docker-files/nushell-autoload/modules-core.nu
  - docker-files/nushell-autoload/modules-repl.nu
reconciled-at: 03a87ce2f81ce9eadf5835c34f9e6f4288a050c5
---

# Vendored Nushell modules — why and how they load

The Nushell modules fanned out under `~/repos/` by `bootstrap.nu` Step 3. This file is pointers only: why each is vendored and how it loads. What each command does lives in the module's own repo and in `../README.md`'s "Nushell modules loaded by default" section — not duplicated here.

`../toolkit/vendor.yml` is the source of truth for *which* modules are vendored and which subdir of each repo is copied. The autoloaded ones are imported by `../docker-files/nushell-autoload/modules-core.nu` and `modules-repl.nu`, split by whether they're safe in a non-interactive `nu -c` (see below).

> Per-module specs are expected to move *into the modules themselves* over time and reconcile back here. The modules are separate repos for distribution and historical reasons, but cozy is their main customer now — their development follows cozy's needs.

## Autoloaded (no manual `use`)

Two files carry these. `modules-core.nu` holds the set that must work everywhere — it loads from autoload *and* from non-interactive `nu --config ~/.config/nushell/autoload/modules-core.nu -c` (Helix's `shell`, agent `nu -c`); see `autoload.md`. `modules-repl.nu` holds session tools loaded only in interactive shells.

**Core (`modules-core.nu`):**

- **nu-goodies** — everyday data-wrangling and history helpers. Loaded as an overlay, no prefix. Repo `nushell-prophet/nu-goodies`.
- **nu-kv** — key-value store; backing path follows `$env.WORKSPACE_DIR` (sandbox-state) when mounted, else `~/.local/share/nu-kv`. Prefix `kv`. Repo `nushell-prophet/nu-kv`.
- **dotnu** — literate programming for `.nu` files. Prefix `dotnu`. Repo `nushell-prophet/dotnu`.
- **numd** — literate programming for `.md` files. Prefix `numd`. Repo `nushell-prophet/numd`.

**Interactive-only (`modules-repl.nu`):**

- **claude-nu** — toolbox for Claude Code sessions. `claude-nu` namespace. Repo `nushell-prophet/claude-nu`.
- **nu-cmd-stack** — command-history stacking. No prefix. Repo `nushell-prophet/nu-cmd-stack`.

## Vendored but not autoloaded (need a manual `use`)

- **nutest** — Nushell test framework. Third-party, MIT, `vyadh/nutest`.

## Vendored, not command modules

These are in `vendor.yml` but are configs or skills, not Nushell command modules:

- **dotfiles** (`nushell-prophet/my-dotfiles`) — personal configs, deployed by `bootstrap.nu` Steps 4–5; see `autoload.md`.
- **my-claude-skills** (`maxim-uvarov/my-claude-skills`) and **nushell-skills** (`nushell-prophet/nushell-skills`) — Claude Code skills installed by `toolkit install-skills`.
- **topiary-nushell** (`blindFS/topiary-nushell`) — grammar + queries for the topiary formatter, wired up in `bootstrap.nu` Step 8; see `install.md`.
