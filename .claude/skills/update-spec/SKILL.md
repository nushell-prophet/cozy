---
name: update-spec
description: >
  Reconcile the cozy spec/ files against the code and patch them in place. Use when the
  user says "update the spec", "reconcile the spec", "the spec is stale", "refresh spec/",
  "/update-spec", or after changing a command, flag, doc comment, install step, or the
  Dockerfile order. The spec is the multi-file functional reference under cozy/spec/
  (one map + per-subsystem files), NOT the README or CLAUDE.md.
---

# Update Spec

Keep `cozy/spec/` in sync with the code. Code is the source of truth; each spec file is a
set of claims to verify. This is a **reconcile-and-patch** skill — preserve the existing
hand-written wording, fix only what drifted. Do not regenerate from scratch.

The spec is progressive disclosure: `spec/README.md` is the Tier-1 map (one paragraph per
subsystem + link); the per-subsystem files (`build.md`, `install.md`, `modules.md`,
`autoload.md`, `cozy-module.md`, `toolkit.md`) hold the Tier-2 entries. `spec/cozy-module.md`
is the canonical FORMAT reference — match it.

## Entry format (per command/script)

- **Purpose** = the first line of the command's own doc comment, reused as-is. Keep it
  identical to the source — the reconcile compares the two directly, so a paraphrase silently
  breaks that check. If a command has no doc comment, write a precise one-liner and flag it.
- One optional behavior/side-effect sentence MAY follow the Purpose — only when it adds
  non-obvious information (what the command does to the system), never a restatement of the
  name or a step-by-step of the code. The full rationale stays at the code anchor.
- **Flags:** derived from the signature — only when the command has flags/args. Omit otherwise.
- **Code:** `relative/path.nu` → `export def name` — symbol anchor, **no line numbers**
  (line numbers drift; symbols are stable).
- Never copy code bodies or full multi-line docstrings.

## Frontmatter

Every spec file (except the map, which omits `covers`) carries:

```
---
human-check: pending   # pending | verified
covers:
  - <source paths this file is reconciled against, relative to cozy/ root>
---
```

`covers:` drives reconciliation — diff exactly those paths. A directory entry (e.g.
`cozy-module/sandbox-state/`) means "all source files under it."

**When you patch a file's content, reset its `human-check` to `pending`.** The field means
"a human has read the current content." Your edits invalidate that. Leave `verified` files
untouched if their `covers:` sources haven't changed.

## Canonical-order invariant (STRICT)

The `Dockerfile` defines the canonical order of operations and their descriptions. That order
flows through ALL docs — `spec/`, `README.md`, and `CLAUDE.md`. Within each spec file, order
entries the way the source reaches them (module `mod.nu` export order; the build sequence).
`build.md` is the spine: it walks the `Dockerfile` top to bottom, then `bootstrap.nu` steps
0–9. **If the Dockerfile or bootstrap order changed, reorder `build.md` first, then propagate
the same reordering to README, CLAUDE.md, and any affected spec file.** Report every place you
touched for the order change.

## Process

1. **Read the spec** — `spec/README.md` first, then each subsystem file and its frontmatter.
2. **For each file**, read the `covers:` sources. Check, in order:
   - Does every `Code:` anchor still resolve (file exists, `export def name` present)?
   - Does each Purpose still match the doc comment's first line?
   - Do the Flags still match the signature?
   - Are entries in source order?
   - New commands/scripts/files in `covers:` not yet in the spec? Add them in source order.
   - Removed commands still listed? Delete them (don't leave stale entries).
3. **Check the map** — does `spec/README.md` still describe every subsystem file, in build
   order, with no dead links?
4. **Check the order invariant** — if the Dockerfile/bootstrap sequence changed, fix `build.md`
   and propagate (see above).
5. **Report** — numbered list grouped by file: what the spec said vs. what the code says.
6. **Patch** — fix in place, preserve wording, reset `human-check: pending` on every file you
   edit. In ambiguous cases (a doc comment that contradicts behavior, a command that looks
   misplaced), ask rather than guess.
7. **Verify your own edits** — for every file you changed, re-check that each `Code:` anchor
   still resolves (file exists, symbol present) and that `human-check` is back to `pending`.
   Reordering and rewrites are exactly when an anchor quietly goes stale; this catches it
   before the user does.

## Vendored modules (modules.md)

Depth is **pointer + in-sandbox surface** only: purpose + the commands the user actually
touches + where the code lives. Do not document module internals — they live in each module's
own repo. Reuse the curated descriptions in `README.md`'s "Nushell modules loaded by default"
section where they exist. Confirm load order and prefixes against
`docker-files/nushell-autoload/module-imports.nu`. `toolkit/vendor.yml` is the source of truth
for which modules exist.

> Per-module specs are expected to move into the modules themselves over time and be reconciled
> back here. When a module ships its own spec, prefer linking to it over duplicating.

## Guidelines

- Reconcile against the source repos under `../` only if a `covers:` path points there; the
  spec covers `cozy/`'s own surface, and vendored copies in `vendor/` are snapshots.
- Don't expand scope: this skill maintains `spec/`. For README/CLAUDE.md accuracy beyond the
  order invariant, that's `validate-docs`.
- Flag, don't fix, genuine code bugs you find while reconciling (a lying doc comment, a
  contradictory invariant) — surface them; the user decides.
