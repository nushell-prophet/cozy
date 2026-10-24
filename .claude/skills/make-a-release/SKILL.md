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
- You are on a task branch in `wtr/cozy`, never on the mono `master`: the release commit reaches `master` through `/mono-land` (step 6)
- The recipient `public/cozy-public` is checked out beside the mono (steps 2 and 6 read it)

If any prerequisite fails, stop and tell the user what needs to happen first.

## Procedure

### 1. Determine version number

Ask the user if they don't specify one.
Suggest based on changes:

- Breaking changes → major bump
- New features → minor bump
- Bug fixes only → patch bump

### 2. Audit git log for missed changes

The release tags live in the recipient (step 6), and the commits not exported yet live only in the mono, so read both histories.
Set the recipient path first; this form holds from any directory of the mono, a worktree included:

```sh
R="$(git rev-parse --path-format=absolute --git-common-dir)/../../public/cozy-public"
test -d "$R" || { echo "no cozy-public checkout at $R"; exit 1; }
```

- Exported already: `git -C "$R" log --oneline <previous-tag>..<branch>`, with `<branch>` from the `branch` of cozy in `../mono.yml`.
- Not exported yet: `git log --oneline <mono-sha>..HEAD -- .`, where `<mono-sha>` is the `Mono-Commit` trailer of the recipient's tip, `git -C "$R" log -1 --format='%(trailers:key=Mono-Commit,valueonly)' <branch>`.

Which history the `CHANGELOG.md` hashes cite is not decided yet; `validate-docs` checks them against the recipient.

Cross-reference each commit against the `[Unreleased]` entries in `CHANGELOG.md`.

Look for:
- Commits with user-facing changes that have no corresponding changelog entry
- Changelog entries whose commit hashes don't appear in the log (stale or wrong hash)
- Multiple commits that should be merged into a single changelog entry

If you find missed changes, draft new entries and show them to the user before adding.
Not every commit needs a changelog entry — skip internal refactors, CI tweaks, and implementation details that don't affect the user.

### 3. Review and finalize Unreleased entries

Read `CHANGELOG.md`.
The writing policy lives in `cozy/CLAUDE.md` ("Changelog" section) — entries target potential new users evaluating cozy, with the KEEP/DROP filters and the "one line per entry, two at most" norm (also stated in the CHANGELOG header).

Before cutting the release, every `[Unreleased]` entry should clear these release-time checks:

- Written from the **user's perspective** — what changed for them, not what happened in the code
- One line per entry, two at most — i.e., one sentence usually, two when the WHY genuinely needs it
- Related commits merged into single entries where they describe one user-facing change
- Ends with short commit hash(es) in parentheses: `(abc1234)` or `(abc1234, def5678)`
- Categories are only the six standard ones (Added, Changed, Deprecated, Removed, Fixed, Security), in that order; empty ones omitted

**Release-specific skip list** (in addition to CLAUDE.md's DROP rules):

- Sub-details of new commands — state purpose + the one key flag, not every fallback / auto-close / pane-direction behavior
- Restating what the previous version did to motivate the current one — link the version inline if the reader needs it

Past released sections are frozen.
Do not rewrite them while tidying — only the new entries are in scope.

If entries need cleanup, fix them before proceeding.
Show the user what you changed.

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

cozy lives in the mono, so a tag here would tag the mono.
The tag goes into the recipient `public/cozy-public` instead, until the user decides otherwise: the sbx kit clones from its GitHub remote.
Land the release commit on the mono `master` with `/mono-land`, run `nu toolkit/mono.nu export cozy` from the mono root, then tag the exported commit, found by its `Mono-Commit` trailer.
`<release sha>` is the sha on `master` after the landing: `/mono-land` rewrites the branch, so the sha from the branch names nothing there.
Stop if the search finds nothing — an empty `$sha` would make `git tag` tag the recipient's `HEAD`:

```sh
R="$(git rev-parse --path-format=absolute --git-common-dir)/../../public/cozy-public"
test -d "$R" || { echo "no cozy-public checkout at $R"; exit 1; }
sha=$(git -C "$R" log --format=%H --grep '^Mono-Commit: <release sha>')
test -n "$sha" && git -C "$R" tag X.Y.Z "$sha"
```

No `v` prefix.
Lightweight tag (no `-a`), matching existing convention.

Treat the release commit as final once tagged.
If the user asks to tweak the changelog after this point, add a follow-up commit: it preserves the tag but leaves it pointing at the pre-tweak version.
Not amend + retag because: the release commit is already on the mono `master` and exported, and a rewrite there breaks the `Mono-Commit` trailers.

### 7. Report

After completing, tell the user:

- The new version number and date
- Summary of what was released
- Remind them to push from the host, in `public/cozy-public`: `git push && git push --tags` — that publishes the release, and it is what the sbx kit clones on every `sbx run`
- For the main Apple `container` path, pushing changes nothing locally: rebuild the image with `container build -t cozy:latest .` (`up` defaults to `cozy:latest`), and recreate the container to pick it up (`container stop <name>; container delete <name>`, then `nu toolkit/container.nu up`)
