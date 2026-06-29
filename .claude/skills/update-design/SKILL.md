---
name: update-design
description: >
  Reconcile the cozy design/ notes against the code and patch them in place. Use when the
  user says "update the design", "reconcile the design notes", "the design notes are stale",
  "refresh design/", "/update-design" (or the older "update the spec" / "refresh spec/"), or
  after changing the build order, an install step, the Dockerfile/bootstrap.nu, or the reason
  something is compiled from source, vendored, or shipped. The target is cozy/design/ — the
  build-and-rationale notes (one map + per-subsystem files), NOT the README or CLAUDE.md.
---

# Update Design

Keep `cozy/design/` in sync with the code. Code is the source of truth; each design file is a
set of claims to verify. This is a **reconcile-and-patch** skill — preserve the existing
hand-written wording, fix only what drifted. Do not regenerate from scratch.

## What design/ is (and isn't)

`design/` records the part no single script can carry: the **build order** (it spans the
`Dockerfile`, `bootstrap.nu`, and the kit) and the **motivation** — why each tool is compiled
from source, why each module is vendored, why each file ships into the sandbox.

It is **not** a command reference. The Nushell modules are self-documenting (`help <cmd>` and
doc comments). So this skill does **not** check Purpose strings, flag lists, or per-command
contracts — restating those here is the duplication we removed. Check whether the *build steps*
and the *reasons* still hold, not what a command's signature is.

`design/README.md` is the Tier-1 map (why + a one-line pointer per file); the per-subsystem
files (`build.md`, `install.md`, `modules.md`, `autoload.md`, `toolkit.md`) hold the detail.

## What to verify

- **Code anchors resolve.** Every `Code:` pointer (file path, and a symbol when given) still
  exists. No line numbers — symbols and paths are stable, line numbers drift.
- **The rationale is still true.** This is the core check and it needs judgment, not string
  matching. Did a tool switch from source-compile to a brew binary? Did a workaround become
  unnecessary (e.g. the proxy issue that forces topiary's hand-compiled grammar)? Did a build
  flag's reason change? If the *why* no longer matches the code, fix the prose.
- **Coverage is complete.** New build step / install tool / vendored module / shipped
  docker-file in a `covers:` source but not in the notes? Add it, in source order. Removed one
  still documented? Delete it.
- **Order is canonical** — see below.

## Canonical-order invariant (STRICT)

The `Dockerfile` defines the canonical order of operations; that order flows through `design/`,
`README.md`, and `CLAUDE.md`. `build.md` is the spine: it walks the `Dockerfile` top to bottom,
then `bootstrap.nu` steps 0–9. **If the Dockerfile or bootstrap order changed, reorder
`build.md` first**, then keep every other design file in the order its source reaches it. If the
change also affects `README.md`/`CLAUDE.md` order, **flag it** for `validate-docs` rather than
editing those files here — this skill owns `design/` only.

## Frontmatter

Every design file (except the map, which omits `covers`) carries:

```
---
human-check: pending   # pending | verified
covers:
  - <source paths this file is reconciled against, relative to cozy/ root>
reconciled-at: <sha>   # commit this file was last reconciled against; absent = never
---
```

`covers:` drives reconciliation — diff exactly those paths. A directory entry means "all source files under it." `reconciled-at:` is the incremental baseline — the commit whose tree this file was last checked against (see *Incremental baseline*). **When you patch a file's content, reset its `human-check` to `pending`** — the field means "a human has read the current content," and your edits invalidate that. `reconciled-at` is the orthogonal machine axis ("code this file was checked against"), so advance it on every clean reconcile but never let it stand in for a human read.

## Incremental baseline

Default to incremental — only reconcile files whose `covers:` sources actually moved.

1. Capture `HEAD` once at the start of the run; this is the SHA you will stamp.
2. If a file has no `reconciled-at` (or the user asked for a **full** check), reconcile it in full — this establishes the baseline.
3. Otherwise run `git log <reconciled-at>..HEAD -- <covers paths>`. **Empty ⇒ skip the file**, it is still in sync. Non-empty ⇒ reconcile against that diff.
4. After a file is reconciled — whether you patched it or confirmed it clean — set its `reconciled-at:` to the captured `HEAD`. A skipped file keeps its old value.

The stamp only advances on a real reconcile, so it always means "this file's claims held against the code at that commit." A `--full` run ignores every `reconciled-at`, re-checks all files, then re-stamps them — that is how you rebuild a baseline you no longer trust. Stamp the run-start `HEAD`, not the commit you are about to make: your commit touches only `design/`, never a `covers:` path, so the next run's `git log` over those paths stays empty for unchanged sources and nothing re-reconciles by mistake.

## Process

1. **Read** `design/README.md`, then each subsystem file and its frontmatter.
2. **For each file the *Incremental baseline* didn't skip**, read the `covers:` sources and run the four checks above (anchors, rationale, coverage, order).
3. **Check the map** — does `README.md` still point at every file, in build order, no dead links?
4. **Report** — numbered list grouped by file: what the notes say vs. what the code says.
5. **Patch** — fix in place, preserve wording, reset `human-check: pending` on every file you edit, and set `reconciled-at` to the run-start `HEAD` on every file you reconciled (patched or confirmed clean). When a doc claim and the code genuinely contradict (a stale rationale you can't resolve from the code alone), ask rather than guess.
6. **Verify your own edits** — re-check that each `Code:` anchor you touched still resolves and
   `human-check` is back to `pending`. Reordering and rewrites are exactly when an anchor quietly
   goes stale.

## Guidelines

- Reconcile against source repos under `../` only if a `covers:` path points there; vendored
  copies in `vendor/` are snapshots.
- Don't expand scope: this skill maintains `design/`. README/CLAUDE.md accuracy beyond the order
  invariant is `validate-docs`.
- Flag, don't fix, genuine code bugs found while reconciling (a lying doc comment, a
  contradictory invariant) — surface them; the user decides.
