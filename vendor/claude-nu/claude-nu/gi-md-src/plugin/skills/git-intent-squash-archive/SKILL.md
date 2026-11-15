---
name: git-intent-squash-archive
description: Squash every commit on the current branch into one, keeping the original commit stream recoverable in an `archive/<branch>` git tag. Use this whenever a working branch is finished and its step-by-step history should stop being noise for whoever reads the trunk — "squash branch", "squash and archive", "finalize this branch", "collapse these commits", "archive the history before merging" — even when the user never names the skill. For gi working branches; when the branch also needs merging and `todo/`/`gi-canvas/` kept off the trunk, use `/land-branch` instead.
allowed-tools: Bash(git *)
---

A working branch's commits are rollback points while the work runs, and noise the moment it is done:
an agent that later reads `git log` on the trunk wades through abandoned attempts and reversed decisions instead of history.
So the branch lands as one commit.
But those abandoned attempts are the record of *why* the surviving shape won,
so the original stream is kept in a tag rather than dropped
— squash for the reader, archive for the record.

This rewrites the branch (`git reset --soft`, `git tag -f`).
That is why steps 1 and 6 stop instead of warning:
on a trunk the reset would rewrite history other people have,
and once it has run there is nothing left to confirm.

Verify the working tree is clean (`git status --porcelain` returns empty).
If not, stop and ask the user to commit or stash first.

## Replies

The user reads these replies as he reads the output of a shell command:
he looks for the same element in the same place every time.
So the plan of step 6, the report of step 11 and every stop have a fixed shape.

- The reply is a column of rows and nothing else:
  no paragraph before it, no question after it.
- Each row is one Markdown line:
  the emoji of a shared label, the label in backticks, `│`, then one line of value, as `` 🟢 `go` │ <what go does> ``.
  The shared labels and their emoji: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`;
  a label of this skill alone has none.
  A value of several lines, such as a commit list, goes in a `text` block right under its row.
  The skeletons below show the rows as plain text;
  the reply adds the emoji, the backticks and the `│`.
- The labels and the fixed values (`squash as shown`, `nothing changed`, `nothing`) are in English;
  the free text of a value is in the language of the session.
- A row prints only when it has something to say:
  a check that passed gets no row.
- `warn` holds a fact that changes what he does or expects.
- In a canvas session, at most four rows and 480 bytes, counting every line of a `text` block and its fences:
  the gi Stop hook passes no more, unless he ran the skill as a slash command.
  There the `text` blocks go:
  the plan adds `git log --oneline <base>..<branch>` to its `squash` row,
  and the report keeps its `history` row.

The plan of step 6:

```text
squash    <branch> → <base> · <N> commits
          (text block: git log --oneline <base>..<branch>)
tag       archive/<branch> | archive/<branch> · overwrites <Change-Id> <subject>
warn      <a fact that changes what he expects>
go        squash as shown
```

`tag` names the commit it overwrites by its short `Change-Id`, by sha only where the commit carries none.

The report of step 11:

```text
squashed  <branch> → <Change-Id> · <N> → 1
          (text block: git log --oneline -5)
history   git log archive/<branch>
next      <the exact action for him> | nothing
```

A stop
— a dirty tree, the trunk in step 1, no commits in step 4 —
has this shape:

```text
stop      <step number, or "clean tree">: <the cause in one line>
state     nothing changed
proof     <one line>
next      <the exact action for him>
```

`stop`, `state` and `next` always print.

## Procedure

Archive and squash all commits on the current branch:

1. Get branch name: `git branch --show-current`.
   If `master` or `main` — **STOP immediately**,
   inform the user this command cannot run on the main branch,
   do not proceed with any further steps
2. Find base: `git merge-base main <branch>` (fall back to `master` if `main` doesn't exist)
3. List all commits on the branch: `git log --oneline <base>..<branch>`
4. If no commits — stop: nothing to squash
5. Check if tag `archive/<branch>` already exists (`git tag -l archive/<branch>`).
   If it does, show the user what it points to and warn that it will be overwritten
6. Show the user the plan of *Replies*: commit list, total count, tag overwrite warning (if applicable).
   **STOP.**
   Wait for confirmation before proceeding
7. `git tag -f archive/<branch> HEAD`
8. `git reset --soft <base>`
9. Generate commit message:
   - **Subject**: one line — what the branch accomplished
   - **Body**: summarize the decisions made on this branch, preserving the user's reasoning from original commit bodies where present,
     then an `Archive:` trailer naming the archived tip:
     its `Change-Id`, read with `git log -1 --format='%(trailers:key=Change-Id,valueonly)' archive/<branch>`,
     or the tag name `archive/<branch>` when that prints nothing
   - Strip every `Change-Id:` trailer from the bodies you fold in:
     where a `commit-msg` hook stamps ids (cozy installs one), it adds an id only to a message that has none,
     so a copied trailer would become this commit's id
     — the same id as an archived commit
   - No hash and no short `Change-Id` of a commit inside `<base>..<branch>` in the body, the `Archive:` trailer aside:
     those name commits the trunk will not have,
     and the trailer names the archived tip on purpose
   - No diff restating; no listing of things you checked and didn't find
10. `git commit`
11. Report in the shape of *Replies*:
    `git log --oneline -5`, the new commit by its short `Change-Id` where it carries one (by sha only where the repo stamps none), and `git log archive/<branch>` for the full history

## Related

- `/gi:git-intent` — process commits as instructions and propagate choices before squashing
- `/land-branch` — `40-land-branch` in the my-claude-skills of the gi author;
  without it, merge by hand.
  The general-development counterpart: same squash-and-archive,
  but it also merges to the trunk and drops `todo/`/`gi-canvas/`.
  Use it when the branch is not gi working material.
