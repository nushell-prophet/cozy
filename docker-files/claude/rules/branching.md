# Branches

These rules hold in every repo whose own `CLAUDE.md` does not state its own.
They sit apart from `CLAUDE.md` so that such a repo can turn them off: `claudeMdExcludes` in its `.claude/settings.local.json` excludes a whole file, never a section.

## Never work on `main` or `master`

Run `git branch --show-current` before you edit the first file.
If it returns `main` or `master`, create a branch with `git switch --create <name>` before that edit, without asking, and name the branch in your report.
Why: the user reviews work as a diff and undoes it by dropping the branch.
A change that landed on the trunk takes that exit away.

## `todo/`, `gi-canvas/` and `gi/` must never reach a published repo

`todo/` holds the user's task notes (and the ones agents wrote when they asked); `gi-canvas/` holds the Canvas working files — the chat moved into version-controlled markdown.
`gi/` is the older name of that folder, still present in a few repos.
Both are working material, not product.
They sit in a repo only because git is the transport.

Never `git merge` (nor cherry-pick, nor rebase onto a shared branch) anything under `todo/`, `gi-canvas/` or `gi/` unless the user asks for that file by name.
Merging them into the trunk publishes a scratchpad.

A repo whose root `CLAUDE.md` says it is never published states its own rule for these folders, and that rule wins.
If nothing says it, assume the repo is published.
