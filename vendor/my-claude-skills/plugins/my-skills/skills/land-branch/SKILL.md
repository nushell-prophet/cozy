---
name: land-branch
description: Land a finished branch on the trunk as a coherent, reviewed sequence of commits — read the branch's own history, fold any commit that only corrects or completes an earlier one's subject (a review-found bug and its fix, a typo, a reverted attempt) into whatever it corrects, archive the original history in a tag, keep `todo/` and `gi/` out of the trunk unless the repo's own CLAUDE.md says it is never published, then merge. Usually lands as one squashed commit; lands as a few commits by subject instead when the branch genuinely bundles more than one (fast-forwarded onto the trunk one after another) — pass `--grouped` to skip straight there. Use when the user says "land the branch", "land this", "merge to main", "finish this branch", or "squash and merge".
argument-hint: [--grouped] [trunk branch, if not main/master]
allowed-tools: Bash(git *), Read, Write, Edit
---

A working branch carries rollback points: a bug review found and the atomic commit that fixed it, an attempt and the commit that reverts it, a typo caught two commits later.
These are not sloppy — an agent-authored fix is usually just as clean and atomic as the commit it corrects.
What makes a commit a rollback point is its subject, not its tone: it exists only to correct or complete something an earlier commit in the same branch already claimed.
The moment the branch lands none of that may survive — not as its own commit, not as a line in a message.
A later agent reading `git log` on the trunk should find the coherent story the branch tells, not the back-and-forth it took to arrive there.

So the branch lands as the smallest sequence of commits that story actually has — usually **one**, squashed; a genuine few when the branch bundles more than one (see *Landing as more than one commit*, at the end of this file).
Either way its full history survives in a tag, and the working material (`todo/`, `gi/`) never reaches the trunk at all.

The tag is insurance against the rewrite: `reset --soft` makes the original commits unreachable, and the tag is what keeps them.
When the branch is already a single clean commit there is no rewrite, it lands on the trunk untouched, and a tag pointing at it preserves nothing that the trunk does not already hold.
Then no tag is written.

## Authorization

The global rule is that the agent never merges on its own initiative, because a merge touches the trunk.
**This skill is the named exception.**
The user invoking `/land-branch` *is* the authorization — that is not inference.
So do not stop one command short and hand back a merge command to paste.

What the exception buys is one confirmation, not silence: show the whole plan at step 8, wait, then run it.
Everything before that stop is read-only.

Two things stay off-limits even here: **never push**, and never run this on the trunk itself.

## Repo snapshot

The block below runs once, before any of this reaches Claude — steps 1, 3, and 4 start with the answer already in hand instead of each costing its own tool call and turn.
It assumes the default trunk (`main`, falling back to `master`); it does not read `$ARGUMENTS`, so a trunk name given there is not covered — resolve that case by hand, per step 3.

```!
branch=$(git branch --show-current)
echo "current-branch: ${branch:-<detached HEAD>}"
if git rev-parse --verify -q main >/dev/null 2>&1; then trunk=main
elif git rev-parse --verify -q master >/dev/null 2>&1; then trunk=master
else trunk=""
fi
echo "default-trunk: ${trunk:-<none found>}"
if [ -n "$trunk" ]; then
  base=$(git merge-base "$trunk" HEAD 2>/dev/null)
  echo "merge-base: $base"
  echo "trunk-head: $(git rev-parse "$trunk")"
  echo "trunk-moved: $([ "$(git rev-parse "$trunk")" = "$base" ] && echo no || echo yes)"
  echo "commits base..HEAD:"
  git log --oneline "$base"..HEAD 2>/dev/null
fi
```

## Procedure

Steps 1–8 only read.
Nothing is changed until the user confirms.

1. **Branch guard.**
   Use `current-branch` from the snapshot above.
   If it is `main` or `master` — **stop immediately** and say so.
   Do not continue.

2. **Clean-tree check.**
   `git status --porcelain` must be empty.
   If not, stop and ask the user to commit or stash.
   A soft reset would otherwise sweep unrelated edits into the landing commit.

3. **Find the trunk.**
   Strip `--grouped` out of `$ARGUMENTS` first — it's the multi-commit shortcut, not a branch name.
   What remains is the trunk name if given (verify it yourself with `git rev-parse --verify <name>` — the snapshot only covers the default case), else the snapshot's `default-trunk`.

4. **Find the base.**
   For the snapshot's default trunk, its `merge-base` and `commits base..HEAD` already answer this.
   For a custom trunk from step 3, run `git merge-base <trunk> HEAD` and `git log --oneline <base>..HEAD` yourself.
   Either way, an empty commit list means "nothing to land" — report that and exit.

5. **Has the trunk moved?**
   For the default trunk, the snapshot's `trunk-moved` already answers this.
   For a custom trunk, compare `git rev-parse <trunk>` with `<base>` yourself.
   If they differ, the trunk advanced and `--ff-only` will fail.
   The plan then gains a `git rebase <trunk>` between the squash and the merge — one commit to replay, but say plainly that a conflict there needs the user's hands.
   Never substitute a merge commit for the rebase without saying so.

6. **Read the history for the message.**
   `git log <base>..HEAD` with full bodies.
   This is the part that must not be lost: why this approach, why an alternative was rejected, what the user said.
   Drop only the mechanics — not just `wip` or a typo fix, but any commit whose whole job is correcting or completing an earlier commit's own subject, however cleanly that correction itself is written: a bug review found and its atomic fix, an attempt and the commit that reverts it.
   None of these earns a line, even a summarized one; the message describes the approach that survived, not the road to it.
   If the branch has a `gi/` canvas or the current session holds reasoning that never reached a commit body, pull it in here — the tag preserves the old bodies, but only this commit is read on the trunk.

   **No run status in the body.**
   Lines like `235 tests passed`, `all checks green`, `verified with nutest` do not belong in the commit message.
   They were true at one moment on one tree; on the trunk they are unverifiable and often already false.
   Report them in the chat reply, where the user reads them while they still mean something.
   The body carries *why*, not *it worked*.

   **No hash of a commit inside `base..HEAD` either.**
   The commit you are writing is the only address those changes will have on the trunk; every hash in the branch's own bodies names a commit the landing is about to rewrite.
   When a body you are folding cites one, the citation goes with the rest of the correction.
   A message is worse than a file here: a file can be repointed afterwards, a body cannot without rewriting the trunk — so this is the only moment.
   The exception is a message whose subject *is* the rewrite; then name `archive/<branch>` beside the hash, so the reader has something that resolves.

7. **Find the working material.**
   `git diff --name-status <base>..HEAD -- todo/ gi/`.
   Keep the status letters; they decide what the working tree looks like afterwards (step 11).

   **First: does this repo publish them?**
   Read the repo's root `CLAUDE.md`.
   If it says the repo is a monorepo, personal, internal, or never sent upstream, then `todo/` and `gi/` are ordinary content there — they land with everything else, and steps 7, 11 and 11a have nothing to do.
   Say so once in the step 8 block instead of listing paths to drop.
   Only when nothing says it is the repo published, which is the default this step assumes.

   7a. **Find the branch's own commits cited inside the tree.**
   A changelog line, a design doc, a code comment may quote a commit hash.
   The landing rewrites those commits, so each such hash keeps resolving — the archive tag holds the object — while no longer being an ancestor of the trunk, which is what a reader following it, and any doc check, actually tests.
   Find them on the added lines of the branch's own diff:

   ```sh
   git diff <base>..HEAD | grep '^+' | grep -v '^+++' | grep -oE '\b[0-9a-f]{7,40}\b' | sort -u |
   while read -r h; do
     [ "$(git cat-file -t "$h" 2>/dev/null)" = commit ] || continue
     git merge-base --is-ancestor "$h" HEAD 2>/dev/null || continue
     git merge-base --is-ancestor "$h" <base> 2>/dev/null && continue
     echo "$h"
   done
   ```

   The two `--is-ancestor` tests are the filter: reachable from `HEAD`, not reachable from `<base>`, so only the commits this landing rewrites come out.
   A hash naming an older trunk commit, or one from another repo, fails a test and is left alone.
   Only added lines are scanned — a line already on the trunk cannot cite a commit this branch made.
   `git grep -n <hash>` then names the file and line citing each hit, which is what step 8 has to show.

8. **Judgement, then STOP.**
   Two calls to make first:
   - Already one clean commit with a good body?
     Then there is nothing to rewrite — skip straight to the merge (step 13).
     No `reset --soft`, no new commit, no `Archive:` trailer, and **no archive tag**.
   - Otherwise, read the history from step 6 as a story, not a diff.
     The test for a chapter is subject, not tone: a commit that only corrects or completes an earlier commit's own subject — a bug review found and its atomic fix, an attempt and its revert, a typo caught later — is never its own chapter, however cleanly it is written itself; it folds into whichever commit it corrects and leaves no trace in any message (see *Folding corrections*, at the end of this file).
     A commit that opens a subject of its own — a second feature the user asked for on the same branch, say — is a chapter in its own right; two such subjects never fold together just because they share a branch.
     What is left after folding is the branch's real chapter count: usually one, occasionally a genuine few when the branch bundles more than one subject.
     Build exactly that many commits — never split further just because a correction happened along the way, never merge two subjects into one just because they happen to share a file (*Splitting a shared file*, at the end of this file, decides that case).
     Say so plainly whenever the count comes out above one, whether or not `--grouped` was passed — the shape is the branch's own; `--grouped` only lets the user skip straight to it.

   Show the user, in one block: the chapters found and which original commits fold into each, the generated message(s), the `todo/`/`gi/` paths being dropped, each hash from step 7a with the file citing it and whether it is dropped or repointed (step 11a), an `archive/<branch>` overwrite warning if `git tag -l` finds one, the rebase warning from step 5, the exact merge command, and the branch-delete command from step 13a.
   **Wait for confirmation.**

## Landing

9. **Archive first** — only on the squash path.
   `git tag -f archive/<branch> HEAD`.
   This runs before anything destructive, and it is what makes the rest reversible — every original commit, including the `todo/` ones, stays reachable.
   Skip it entirely when step 8 sent you to the merge: there is nothing to make reachable.

10. **Squash.**
    `git reset --soft <base>`.
    The whole branch is now staged as one change.

11. **Drop the working material.**
    For the paths found in step 7: `git restore --staged -- <paths>`.
    Only pass paths that actually appear there; a pathspec matching nothing is an error.

    This is the whole `todo/`/`gi/` mechanism — no filtering, no history rewrite, one command at the one moment it is natural.
    What it leaves behind depends on the status letter, and you must **report** the leftovers rather than claim a clean tree:
    - `A` (added on the branch) → the file becomes untracked.
      This is the normal case, and exactly where a parked note belongs.
    - `M` (modified) → the change stays in the working tree, unstaged.
    - `D` (deleted) → the file is missing from disk while the index holds it back; shows as an unstaged deletion.

    A note this branch **finished** is not parked any more — it is done.
    Say so at step 14 and offer to delete it, instead of leaving it in the working tree where the next session reads it as open work.
    Same for a `gi/` canvas whose thread closed with this branch.
    Judge each file: only the ones this branch actually resolved — a branch often adds a note about something it did not fix, and that one stays.
    The archive tag holds every one of them, so deleting loses nothing.

    Then check `git diff --cached --quiet`: if nothing is staged any more, the branch held *only* working material.
    Report that and stop — there is nothing to land.

    11a. **Settle the cited hashes** from step 7a, in the working tree, then `git add` each file you touched.

    A commit cannot carry its own hash — writing it in changes it.
    On the squash path every cited commit folds into the one commit being written, so there is nothing to repoint: **drop the citation**.
    Drop the whole `(…)` group when every hash in it folds here, or just that hash when the group also names commits from before `<base>`.
    Nothing is lost — the entry and the change it describes now land together, so `git blame <file>` names the commit in one step.
    This is also what survives step 5's rebase, which changes every landed hash a second time; a citation kept by any other means would break again there.

    Skip a hash whose file was dropped at step 11 — that file is not landing.

12. **Commit** with the message from step 6, plus an `Archive: archive/<branch>` trailer.
    Run the drafted message through step 7a's loop first, with the message text in place of the diff — a hash reaching the body is usually one copied out of a folded commit, and after the commit exists there is no fixing it.

13. **Merge.**
    `git switch <trunk>` then `git merge --ff-only <branch>`.
    With the rebase from step 5 if the trunk moved.

    13a. **Delete the branch.**
    The tag from step 9 is what makes this safe — every commit it points at, including the dropped `todo/`/`gi/` ones, stays reachable through `archive/<branch>`, so nothing is lost.
    On the squash path, `git reset --soft` produced a new commit object that differs from the branch tip, so git won't recognize it as merged: use `git branch -D <branch>`.
    When step 8 sent you straight to the merge (already one clean commit, no squash, no tag), the branch tip *is* the trunk tip now, so the plain `git branch -d <branch>` works.

14. **Report**, briefly: the trunk's new commit, that the user is now standing on `<trunk>` (say it plainly — the next edit would otherwise land there), that `<branch>` was deleted, and — if step 9 ran — that `git log archive/<branch>` still holds the full history.
    Split the leftover working-tree state from step 11 into notes still open and artifacts this branch completed; for the completed ones give the `rm` command (`allowed-tools` here is git only, so the user runs it).
    This is also where run status belongs — `nutest run` → `57 passed`, not in the commit body.
    Do not push.

## Landing as more than one commit

Step 8's own analysis is what decides a branch needs more than one commit — not a flag.
`--grouped` only saves a round trip: pass it when you already know the branch bundles more than one subject, and the plan goes straight to the multi-commit shape instead of first proposing a single squash.

The trade-off is the same either way, and the user takes it on by confirming the plan: the chapter commits reach the trunk as ordinary commits, one after another, with no merge commit around them.
A multi-subject branch is an accident of workflow, not a unit — a merge commit would record that accident, and its body would have to describe several subjects at once.
Landing plain keeps the history one shape: linear, exactly like the squash path.
The cost: each chapter's body must be self-sufficient, because no other place survives to carry its reasoning.

Steps 1–7a and 9 run unchanged.
The archive tag still matters: `reset --soft` makes the original commits unreachable here too.

### Folding corrections, grouping by subject

A chapter is a subject in the branch's own story, not a raw file path — but paths are the mechanism for building one.
Walk the history from step 6 and assign each commit to the chapter whose subject it belongs to.
The test is what the commit is *for*, not how it reads: a bug review found and the atomic fix that followed it, a typo caught later, an attempt and its revert — each of these corrects or completes a subject an earlier commit already opened, so none is a chapter of its own no matter how clean the commit itself is.
It folds into the chapter it corrects, and contributes nothing to that chapter's message (same rule as step 6's *no run status* — extended to *no trace of the correction itself*).

This folding is automatic once you group by subject, and needs no hunk-editing to work: staging a path with `git add` after `reset --soft` stages that path's **final** working-tree content, not any one commit's diff.
A bug fixed by its own later commit, a typo fixed three commits after, or a file added and then fully reverted, already comes out right — or vanishes entirely — in whichever chapter's commit picks up that path.

When a file's changes cannot be attributed to a single chapter — a correction's own changes touch two candidates, or two independently-motivated subjects both need the file — the file is **split** between the chapters (next section), not the chapters merged.
Merging chapters is the last resort, reached only when the split itself is unsafe: it erases the branch's real shape just because two subjects happened to share a file.

### Splitting a shared file

There is still no `rebase -i` and no editing inside a hunk — a split uses only mechanisms whose staged result can be checked.
Two, tried in this order:

1. **Ordered history — pure git.**
   If every commit of the earlier chapter that touches the file precedes every commit of the later one that touches it (check with `git log --oneline <base>..HEAD -- <file>`), then after the soft reset `git restore --source=<earlier chapter's last commit> --staged -- <file>` stages exactly the earlier chapter's version.
   No patch is built, and the staged state really existed on the branch — so it built at least once.
   The later chapter's plain `git add <file>` then stages the rest.
2. **Interleaved history — whole-hunk patch.**
   Otherwise, take `git diff -- <file>` (index vs worktree, after the soft reset), write only the hunks belonging to the earlier chapter into a patch file in the scratchpad, and stage them with `git apply --cached <patch>`.
   Whole hunks only, copied verbatim: never edit lines inside a hunk.

The limit that remains: when unrelated changes share a single hunk, there is no safe cut — merge the affected chapters into one and name the file as the reason in the step 8 plan.
Never let a file land in one chapter while its other change silently disappears — that ships a commit that does not build.

Name every split file in the step 8 plan, with the mechanism used.
An intermediate commit holding part of a file may not build — the ordered-history mechanism avoids this, the patch one does not — and by confirming the plan the user takes that risk on.

### Steps 10–12, replaced

- `git reset --soft <base>` — the whole branch is staged, as in step 10.
- `git restore --staged .` — unstage all of it.
  The working tree is untouched.
- Per chapter: `git add <the chapter's paths>` — a split file is staged by its mechanism from *Splitting a shared file* instead — then `git commit` with that chapter's message.
  The last chapter's body also carries the `Archive: archive/<branch>` trailer; one pointer is enough.
- Step 11a runs per chapter, just before that chapter's commit, and gains one case: a hash folding into a chapter **already committed** can be repointed at its real new hash, since that hash now exists — unless step 5 found the trunk moved, because the rebase then changes that hash again and the citation breaks a second time; drop it instead.
  A hash folding into the chapter being written, or into a later one, is dropped as on the squash path — the first cannot name itself, the second does not exist yet, and reaching back to fix it later would rewrite the chapter that cites it.
- `todo/` and `gi/` are never added, so step 11's `git restore --staged` has nothing to do and disappears — the same result reached by doing nothing.
  What they leave behind in the working tree, and your duty to report it instead of claiming a clean tree, is exactly as step 11 describes.
- If every chapter comes out empty, the branch held only working material.
  Report that and stop, as step 11 says.

### Step 13, unchanged

Step 13 runs as written: `git switch <trunk>`, then `git merge --ff-only <branch>` — with the step 5 rebase first if the trunk moved (several commits to replay now, and a conflict there still needs the user's hands).

13a: `reset --soft` rebuilt the chapters, but the ff-merge just put that rebuilt tip on the trunk itself, so the plain `git branch -d <branch>` works.

## Related

- `/git-intent-squash-archive` — the same shape, but inside the gi loop: it squashes and archives a canvas branch and stops there, without merging.
  Reach for it when the branch is gi working material; reach for `land-branch` for ordinary development.
