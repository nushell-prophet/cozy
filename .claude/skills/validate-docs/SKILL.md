---
name: validate-docs
description: >
  Cross-reference project documentation against actual code, configs, scripts,
  and directory structure to find and fix stale or incorrect references.
  Use this skill whenever the user asks to "validate docs", "check docs against code",
  "are my docs up to date", "cross-check README", "verify documentation",
  "docs consistency check", or any variation of reviewing documentation for accuracy.
  Also trigger when the user has just done a rename, refactor, or dependency change
  and wants to make sure docs still match reality.
---

# Validate Docs

Cross-reference all documentation files against the actual codebase and fix inconsistencies.
Code is the source of truth.
Docs are claims to verify.

## Replies

Step 4 prints the `pass`, `drift` and `hash` rows, every `drift` and `hash` row `to fix`, and the run goes on to step 5 with no wait.
After step 6 the full report prints, with the final state of each row, and ends with `next`.
Both follow the global rule *A skill reply reads like shell output*.
This skill adds:

- No row says that a check found nothing: no "all CHANGELOG hashes resolve", no list of the claims that are consistent.
- `drift`, `hash` and `open` rows carry one number sequence (`<#>` below, `drift 3`); a number stays the same in every later reply of the run.
  An `open` row about a drift or a hash takes the number of that row.
- `drift` rows are grouped by file; the file with the most expensive drift comes first.

A report has these rows, in this order:

```text
pass      incremental from <marker short Change-Id> · <n> commits | full · branch <task branch>
drift     <#> <file>:<line> · doc: <the claim> → code: <the fact> · fixed in <short Change-Id> | to fix
hash      <#> <the stale hash> in <the entry in a few words> · rehashed → <new hash> | typo → <the real hash> | to fix
upstream  <repo> <short Change-Id> on <branch>: <file>: <what was fixed in the source of a vendored copy>
open      <#> <the open item in full: what the doc says, what the code says>
marker    refs/cozy/docs-validated → <short Change-Id> | stays at <short Change-Id>: <the reason>
warn      <a fact that changes what the user does or expects>
next      <the answer an `open` row waits for> | /mono-land
```

- `drift`: step 3, one row per mismatch between a doc and the code; before step 5 its state is `to fix`.
  `/update-design` uses the same label for the same kind of row.
- `hash`: *CHANGELOG commit hashes*, one row per hash that does not resolve.
- `upstream`: a vendored doc fixed in its source repo (see *Guidelines*).
- `open`: an ambiguous case of step 5, or a typo hash with no unambiguous match; the skill asks, it does not guess.
- In the full report, `pass` and `marker` always print.

## Incremental baseline

Two modes, with a git marker recording the last clean full pass.

- **Incremental (default).**
  The local ref `refs/cozy/docs-validated` points at the commit whose tree was last fully validated.
  Get the changed set with `git diff --name-only refs/cozy/docs-validated..HEAD` and check only what it touches: re-verify every changed doc, and for every changed code/config path, grep the docs for references the change may have broken.
  If the ref does not exist yet there is no baseline — fall through to a full scan.
- **Full (on request, or when no marker exists).**
  Scan the whole project.
  Inconsistencies hide in unexpected places — vendored copies, test files, inline component lists — so a narrow ask still means a full sweep here.
  This is the mode that *earns* trust in the baseline.

After a clean pass — incremental or full, once any fixes are committed — move the marker to the validated commit:

```sh
git update-ref refs/cozy/docs-validated HEAD
```

This is a **local-only** ref by design: it lives outside `refs/tags/` and `refs/heads/`, so `git push` and `git push --tags` leave it alone — it records *your* validation state, not something to share.
The baseline is only as good as the last full pass that set it, so when in doubt, run a full scan to re-establish it.

## Process

In incremental mode every step below is scoped to the changed set from the baseline; in full mode, to the whole project.

1. **Read code first** — Dockerfile, scripts, configs, test files, directory structure, `git log --oneline -20` for recent renames.
   Extract the facts.

2. **Read all docs** — every `.md` file: README, CLAUDE.md, CHANGELOG, vendored READMEs, inline comments that list components.

3. **Cross-reference** — check each doc claim against the facts.
   Look for:
   - Stale names (renamed in code but not docs)
   - Removed items still listed
   - Added items not listed
   - Wrong paths
   - Command mismatches
   - Test files that check for removed/renamed things
   - CHANGELOG contradictions between sequential versions (e.g. v0.0.2 says "switch from A to B" but v0.0.1 already claims B)
   - CHANGELOG commit hashes that no longer resolve to a commit on the branch — see *CHANGELOG commit hashes* below

4. **Report** in the shape of *Replies* — one numbered `drift` row per issue, grouped by file.
   Show what the doc says vs what the code says.

5. **Fix** — edit the docs to match code.
   Preserve the author's style.
   In ambiguous cases, ask the user with an `open` row.

6. **Advance the marker** — once fixes are committed and the pass is clean, `git update-ref refs/cozy/docs-validated HEAD`.
   Skip this if you only checked a subset the user named rather than the full changed set — a partial check must not move the baseline.

## CHANGELOG commit hashes

Every hash cited in `CHANGELOG.md` must resolve to a commit reachable from the branch of the recipient `public/cozy-public` (the `branch` of cozy in `mono.yml`), not from whatever that checkout has at `HEAD`.
Why the recipient and not the mono: the import into the mono rewrote every sha, and the cited hashes and the release tags live in the recipient.
This is a stopgap: which history new entries cite is not decided yet.
This check **always runs over the whole file**, even in incremental mode — a rebase (or any history edit) rewrites the hash a commit is known by *without changing a single byte of `CHANGELOG.md`*, so scoping to the changed-file set would skip exactly the drift this catches.

```sh
M="$(git rev-parse --path-format=absolute --git-common-dir)/.."
R="$M/../public/cozy-public"
test -d "$R" || { echo "no cozy-public checkout at $R"; exit 1; }
B=$(nu --commands "open '$M/mono.yml' | where name == cozy | get 0.branch")
grep -oE '\(([0-9a-f]{7,40}(, )?)+\)' CHANGELOG.md | grep -oE '[0-9a-f]{7,40}' | sort -u \
| while read h; do git -C "$R" merge-base --is-ancestor "$h" "$B" 2>/dev/null || echo "unresolved: $h"; done
```

`merge-base --is-ancestor` is stricter than `rev-parse`: a commit rebased off the branch still exists as a dangling object, but is no longer an ancestor of `HEAD`, so it is correctly flagged.

Fixing an unresolved hash:

- **Rehashed by a rebase** — the same patch lives on the branch under a new hash.
  Find it by matching the entry's described change to a commit subject (`git log <last-release-tag>..HEAD`), and confirm with `git patch-id` (`git diff old^ old | git patch-id --stable` vs the candidate — identical patch-id means it's the same change).
  A confident patch-id match is safe to swap automatically.
- **Never existed (typo)** — no patch-id match anywhere.
  Locate the real commit by its message (`git log --all -i --grep='<keywords>'`); if the match is unambiguous, fix it, otherwise ask with an `open` row.

## Guidelines

- Check vendored copies for issues, but fix them in the upstream source repos (`../`), not in `vendor/` — vendored files are snapshots that get overwritten on re-vendor.
- Don't flag changelog entries about past renames — those are history, not current claims.
- Don't rewrite docs beyond fixing inaccuracies.
