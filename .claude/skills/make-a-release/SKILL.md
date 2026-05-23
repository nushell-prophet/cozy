---
name: make-a-release
description: >
  Cut a new release for the cozy project: finalize CHANGELOG.md, create a git tag,
  and summarize what to do next. Use when the user says "make a release", "cut a release",
  "release", "bump version", "tag a release", or "prepare release".
---

# Make a Release

Full release procedure for the cozy project.

## Prerequisites

- Working directory is clean (`git status` shows no uncommitted changes)
- `## [Unreleased]` in `CHANGELOG.md` has entries to release
- You are on the `main` branch (or the branch the user intends to release from)

If any prerequisite fails, stop and tell the user what needs to happen first.

## Procedure

### 1. Determine version number

Ask the user if they don't specify one. Suggest based on changes:

- Breaking changes → major bump
- New features → minor bump
- Bug fixes only → patch bump

Current versions use `0.0.x` — the project is pre-1.0.

### 2. Audit git log for missed changes

Run `git log --oneline <previous-tag>..HEAD` to see all commits since the last release. Cross-reference each commit against the `[Unreleased]` entries in `CHANGELOG.md`.

Look for:
- Commits with user-facing changes that have no corresponding changelog entry
- Changelog entries whose commit hashes don't appear in the log (stale or wrong hash)
- Multiple commits that should be merged into a single changelog entry

If you find missed changes, draft new entries and show them to the user before adding. Not every commit needs a changelog entry — skip internal refactors, CI tweaks, and implementation details that don't affect the user.

### 3. Review and finalize Unreleased entries

Read `CHANGELOG.md`. Before cutting the release, review `[Unreleased]` entries for quality:

- Every entry is written from the **user's perspective** — what changed for them, not what happened in the code
- No verbatim commit messages — rewrite if needed
- Related commits merged into single entries where they describe one user-facing change
- Each entry ends with short commit hash(es) in parentheses: `(abc1234)` or `(abc1234, def5678)`
- Categories are only the six standard ones (Added, Changed, Deprecated, Removed, Fixed, Security), in that order
- Empty categories omitted
- Internal refactors, CI changes, and implementation details excluded

**Conciseness (STRICT).** One main fact per entry plus the minimum WHY a reader needs. Aim for one sentence; two when the WHY genuinely needs it. Three sentences = too much. Skip:

- Per-file "Affects: …" lists for renames/refactors — `git log` and the linked compare URL have that
- Sub-details of new commands (state purpose + the one key flag, not every fallback / auto-close / pane-direction behavior)
- "Broad refresh from upstream", "preserves the original intent of …", "(previously only X)" framing — state the change directly
- Restating what the previous version did to motivate the current one — link the version inline if the reader needs it

Past released sections are frozen. Do not rewrite them while tidying — only the new entries are in scope.

If entries need cleanup, fix them before proceeding. Show the user what you changed.

### 4. Update CHANGELOG.md

1. Create new version heading: `## [X.Y.Z] - YYYY-MM-DD` (today's date, ISO 8601)
2. Move all `[Unreleased]` entries under the new version heading
3. Leave `## [Unreleased]` empty (no category subsections)
4. Insert the new version between `[Unreleased]` and the previous latest version
5. Update comparison links at the bottom:
   - `[Unreleased]` link: compare new tag to HEAD
   - New version link: compare previous tag to new tag
   - Tags use bare numbers (e.g., `0.0.9`), not `v`-prefixed

Example link update for releasing `0.0.9` after `0.0.8`:
```
[Unreleased]: https://github.com/nushell-prophet/cozy/compare/0.0.9...HEAD
[0.0.9]: https://github.com/nushell-prophet/cozy/compare/0.0.8...0.0.9
```

### 5. Commit

Commit message: `release: X.Y.Z`

Body includes a brief summary of what's in this release (2–4 lines, not the full changelog).

### 6. Tag

```sh
git tag X.Y.Z
```

No `v` prefix. Lightweight tag (no `-a`), matching existing convention.

Treat the release commit as final once tagged. If the user asks to tweak the changelog after this point, ask whether to **amend + retag** (clean history, safe while the tag is unpushed) or **add a follow-up commit** (preserves the tag but leaves it pointing at the pre-tweak version). Default to follow-up commit if they don't have a preference.

### 7. Report

After completing, tell the user:

- The new version number and date
- Summary of what was released
- Remind them to push: `git push && git push --tags`
- Remind them to rebuild the image if needed: `docker build -t cozy:vX .`
