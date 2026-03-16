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

Documentation drifts from reality after renames, dependency changes, and refactors. This skill
systematically catches those gaps by treating code as the source of truth and docs as claims
to verify.

## What counts as documentation

Scan for all of these in the project:
- `README.md`, `CLAUDE.md` (at any level)
- `CHANGELOG.md`
- Inline comments that describe architecture or list components
- Any `.md` file that describes how the project works

## What counts as source of truth

- `Dockerfile` and docker-compose files — installed packages, paths, base images
- Build scripts and config files — tool lists, paths, env vars
- Directory structure on disk — module names, file existence
- `package.json`, `requirements.txt`, `Cargo.toml`, etc. — dependency names and versions
- Test files that assert tool presence or paths
- Git history for recent renames (check `git log --oneline -20` for rename/refactor commits)

## Validation process

### 1. Gather facts from code

Read the key source-of-truth files first. Extract concrete, verifiable facts:
- Which tools/packages are installed and how
- What directories and files exist
- What modules are vendored or cloned
- What commands are documented for building/running
- What env vars are set
- What paths are referenced

### 2. Scan documentation for claims

Read every documentation file. For each, identify claims that can be checked:
- Lists of tools, packages, or modules
- Directory paths and file paths
- Command examples
- Architecture descriptions
- Version numbers or image names

### 3. Cross-reference

For each claim in docs, verify it against the facts gathered in step 1. Common issues:

| Issue type | Example |
|---|---|
| **Stale name** | Doc says `nushell-kv` but code uses `nu-kv` |
| **Removed item still listed** | Doc lists `carapace` but Dockerfile no longer installs it |
| **Added item not listed** | Dockerfile installs `bat` but doc's tool list omits it |
| **Wrong path** | Doc says `~/git/` but code uses `~/repos/` |
| **Command mismatch** | Doc says `docker sandbox run` but project uses `docker sandbox create` |
| **Missing from tests** | Tool added to Dockerfile but not to test file's check list |

### 4. Report findings

Present a numbered list of inconsistencies, grouped by file. For each issue, show:
- The file and line
- What the doc says
- What the code says
- The fix needed

### 5. Fix

Apply all fixes. Documentation is the thing being corrected — code is the source of truth.
In ambiguous cases (e.g., two docs disagree and neither matches code), ask the user.

After fixing, briefly list what was changed so the user can review or revert with git.

## Important guidelines

- Read code files before documentation. Form your understanding of reality first, then
  check docs against it — not the other way around.
- Check vendored copies too. If a file exists both as a vendored copy and in a source repo,
  both should be consistent.
- Don't flag changelog entries that describe past renames or removals — those are historical
  records, not current claims.
- Don't rewrite docs beyond fixing inaccuracies. Preserve the author's style and structure.
- If a doc file is auto-generated, note it but skip fixes (the generator is the source of truth).
