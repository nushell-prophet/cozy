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

Cross-reference all documentation files against the actual codebase and fix inconsistencies. Code is the source of truth. Docs are claims to verify.

## Incremental baseline

Two modes, with a git marker recording the last clean full pass.

- **Incremental (default).** The local ref `refs/cozy/docs-validated` points at the commit whose tree was last fully validated. Get the changed set with `git diff --name-only refs/cozy/docs-validated..HEAD` and check only what it touches: re-verify every changed doc, and for every changed code/config path, grep the docs for references the change may have broken. If the ref does not exist yet there is no baseline — fall through to a full scan.
- **Full (on request, or when no marker exists).** Scan the whole project. Inconsistencies hide in unexpected places — vendored copies, test files, inline component lists — so a narrow ask still means a full sweep here. This is the mode that *earns* trust in the baseline.

After a clean pass — incremental or full, once any fixes are committed — move the marker to the validated commit:

```sh
git update-ref refs/cozy/docs-validated HEAD
```

This is a **local-only** ref by design: it lives outside `refs/tags/` and `refs/heads/`, so `git push` and `git push --tags` leave it alone — it records *your* validation state, not something to share. The baseline is only as good as the last full pass that set it, so when in doubt, run a full scan to re-establish it.

## Process

In incremental mode every step below is scoped to the changed set from the baseline; in full mode, to the whole project.

1. **Read code first** — Dockerfile, scripts, configs, test files, directory structure,
   `git log --oneline -20` for recent renames. Extract the facts.

2. **Read all docs** — every `.md` file: README, CLAUDE.md, CHANGELOG, vendored READMEs,
   inline comments that list components.

3. **Cross-reference** — check each doc claim against the facts. Look for:
   - Stale names (renamed in code but not docs)
   - Removed items still listed
   - Added items not listed
   - Wrong paths
   - Command mismatches
   - Test files that check for removed/renamed things
   - CHANGELOG contradictions between sequential versions (e.g. v0.0.2 says
     "switch from A to B" but v0.0.1 already claims B)

4. **Report** — numbered list of issues, grouped by file. Show what the doc says vs
   what the code says.

5. **Fix** — edit the docs to match code. Preserve the author's style. In ambiguous
   cases, ask the user.

6. **Advance the marker** — once fixes are committed and the pass is clean, `git update-ref refs/cozy/docs-validated HEAD`. Skip this if you only checked a subset the user named rather than the full changed set — a partial check must not move the baseline.

## Guidelines

- Check vendored copies for issues, but fix them in the upstream source repos (`../`), not
  in `vendor/` — vendored files are snapshots that get overwritten on re-vendor.
- Don't flag changelog entries about past renames — those are history, not current claims.
- Don't rewrite docs beyond fixing inaccuracies.
