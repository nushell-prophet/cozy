---
name: 40-todo-verify
description: >
  Re-verify the notes in a repo's todo/ folder — the user's own, and the ones
  agents wrote when he asked — by reproducing each problem against the current
  tree, then archive only the ones proven fixed.
  Use this skill when the user says "todo-verify", "verify the todo notes",
  "check the todo folder", "проверь todo", "are these still broken",
  "clean up todo", or asks whether notes marked FIXED / DONE / completed
  are actually closed. Also use before planning work off a stale backlog.
version: 0.1.0
context: fork
agent: general-purpose
background: false
---

# Todo Verify

A `todo/` note is a problem written down to be dealt with later.
Most of them are the user's own; some were written by an agent, because he asked for one.
Notes accumulate, get marked closed by whoever passed by, and that marker is a claim like any other — added without re-running anything.
This skill turns the folder back into a backlog you can plan from: every closure claim is re-tested against the current tree, and a note leaves the folder only when a command proves it.

Who wrote a note does not change how it is handled — check it, verify it, then move it or keep it, the same either way.
It changes only how carefully the file itself is treated: most of this folder is the user's own writing, and it is not yours to rephrase.

## Core principle

A verdict comes from running something.
Reading the note, reading the fix commit, and reading the test file are all "the note says so" in three costumes.
If nothing was executed, the item is UNVERIFIABLE — not CONFIRMED FIXED.

## Scope

Target: the `todo/` folder of the current repo, or the path the user names.
One folder per run.
Do not crawl sibling repos — but a note may name a fix that landed in another repo, and that SHA is checked where it lives.

## Step 1 — Inventory

Read every note in the folder.
For each, extract:

- **The claim of closure**, in any of the shapes these notes take: `status: completed` (or `rejected`) in the frontmatter; prose like "Fixed in `9a81318`", "Closed in nu-cybergraph `6d9cac7`", "~~withdrawn~~"; a "Fixed in this session" section in an index note.
- **The original problem** and, if the note has one, its reproduction command.
- **The repo the SHA belongs to** — notes cross-reference sibling repos.

Index notes hold many items.
Split them: each item gets its own verdict.

Items with no closure claim are already open — carry them straight to STILL BROKEN without re-testing, and say they were not re-tested.

## Step 2 — Reproduce

For each closed item, in this order:

1. **Does the commit exist?**
   `git cat-file -t <sha>` in the repo the note names.
   A SHA that resolves nowhere makes the item UNVERIFIABLE, whatever the prose claims.
2. **Does the problem still happen?**
   Run the note's repro against the **current** tree.
   No repro command in the note → write one from the note's description; if you cannot, the item is UNVERIFIABLE.
3. **Is there a test that would catch a regression?**
   Name it if there is.
   Its absence does not overturn a clean repro run — report it as a gap.

Never use `git checkout`, `git switch`, or `git reset --hard` to reach an older state.
Where the repo leaves `todo/` uncommitted — which is every published repo — a checkout destroys the notes outright, and it has silently destroyed uncommitted work here before.
In an internal monorepo the notes are tracked and survive, but the same command still takes every other uncommitted change with it.
Use `git worktree add` into the scratchpad, or copy the tree.

## Step 3 — Three lists

- **CONFIRMED FIXED** — the SHA resolves, and the repro was run against the current tree and did not reproduce.
  Report both: the SHA and the exact command with the line that proves it.
- **STILL BROKEN** — the repro still reproduces, or the item was never claimed closed.
  The note's own marker does not outrank the run.
- **UNVERIFIABLE** — no runnable repro, a SHA that resolves nowhere, a check the environment blocks (network, Docker, host-only), or an item that is a design or naming decision rather than a defect.
  Say which of these it is and name the one thing that would settle it.

State the counts.
If a claimed-fixed item lands in STILL BROKEN, that is the headline of the report — say it first.

## Step 4 — Archive, do not delete

Move CONFIRMED FIXED notes to `todo/verified/`, adding to the frontmatter:

```
verified: <sha> — <the command that proved it> (<yyyy-MM-dd>)
```

Why move and not delete: the verdict is yours, not the user's, and a wrong CONFIRMED FIXED would erase the evidence that would have shown it wrong.
In a published repo the notes are also uncommitted, so `rm` is unrecoverable — git will not bring them back.
Emptying `todo/verified/` is then one command, on the user's own schedule.

An index note with a mix of verdicts stays in `todo/`.
Strike its confirmed items down to one line each — the finding, the SHA, the proving command — and leave the rest untouched.

Leave STILL BROKEN and UNVERIFIABLE notes where they are.
You may append a dated line with what you ran and what happened.
Do not rewrite their reasoning; it is the user's record, not a draft.

Leave the folder as the repo keeps it.
A published repo keeps `todo/` uncommitted, so commit nothing; a repo that is never published tracks it like any other file, so the moves and the appended lines are committed with the rest.
Two signs mark such a repo: `mono` in the path, and the repo's own root `CLAUDE.md` saying it is internal, personal, or never sent upstream — the `CLAUDE.md` decides, and the monorepo is only its commonest case.

## Report format

```
## todo-verify — <repo>/todo (N notes, M items)

### STILL BROKEN (n)
1. <finding> — <note file>
   claimed: <the closure claim, verbatim>
   repro:   <command> → <the line that shows it still happens>

### UNVERIFIABLE (n)
1. <finding> — <note file>
   why: <no repro | sha <x> not found | blocked: no network>
   would settle it: <the one thing>

### CONFIRMED FIXED (n) → moved to todo/verified/
1. <finding> — <sha>, <command> → <the line that proves it>
```

## Edge cases

- **The note describes a fix that is now wrong for a different reason.**
  That is a new problem, not this note's.
  Report it in the run's output and leave the old note alone; write a new note only if the user asks for one.
- **The repro is destructive** (writes into the user's store, mutates a graph).
  Run it in a copy under the scratchpad, and say that is where it ran.
- **Two notes describe the same defect.**
  Keep the older one, and point the newer at it in a single line — do not merge their text.
