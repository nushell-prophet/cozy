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
Code is the source of truth. Docs are claims to verify.

Always scan the full project, even if the user mentions specific files — inconsistencies
hide in unexpected places like vendored copies and test files.

## Process

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

4. **Report** — numbered list of issues, grouped by file. Show what the doc says vs
   what the code says.

5. **Fix** — edit the docs to match code. Preserve the author's style. In ambiguous
   cases, ask the user.

## Guidelines

- Check vendored copies for issues, but fix them in the upstream source repos (`../`), not
  in `vendor/` — vendored files are snapshots that get overwritten on re-vendor.
- Don't flag changelog entries about past renames — those are history, not current claims.
- Don't rewrite docs beyond fixing inaccuracies.
