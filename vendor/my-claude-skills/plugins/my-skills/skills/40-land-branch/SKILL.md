---
name: 40-land-branch
description: Land a finished branch on the trunk as a coherent commit — fold the rollback commits into the work they correct, carry the branch's reasoning into the message, archive the old history in a tag, keep `todo/` and `gi/` off the trunk, then merge. Use when the user says "land the branch", "land this", "merge to main", "finish this branch", or "squash and merge".
argument-hint: [--grouped] [trunk branch, if not main/master]
allowed-tools: Bash(git *), Read, Write, Edit
---

A working branch carries rollback points: a bug review found and the atomic commit that fixed it, an attempt and the commit that reverts it, a typo caught two commits later.
These are not sloppy — an agent-authored fix is usually just as clean and atomic as the commit it corrects.
What makes a commit a rollback point is its subject, not its tone: it exists only to correct or complete something an earlier commit in the same branch already claimed.
The moment the branch lands none of that may survive — not as its own commit, not as a line in a message.
A later agent reading `git log` on the trunk should find the coherent story the branch tells, not the back-and-forth it took to arrive there.

So the branch lands as the smallest sequence of commits that story actually has — usually **one**, squashed; a genuine few when the branch bundles more than one (see `references/grouped.md`).
Either way its full history survives in a tag, and the working material (`todo/`, `gi/`) never reaches the trunk at all.

The tag is insurance against the rewrite: `reset --soft` makes the original commits unreachable, and the tag is what keeps them.
When the branch is already a single clean commit there is no rewrite, it lands on the trunk untouched, and a tag pointing at it preserves nothing that the trunk does not already hold.
Then no tag is written.

## Authorization

The global rule is that the agent never merges on its own initiative, because a merge touches the trunk.
**This skill is the named exception.**
The user invoking `/40-land-branch` *is* the authorization — that is not inference.
So do not stop one command short and hand back a merge command to paste.

What the exception buys is one confirmation, not silence: show the whole plan at step 8, wait, then run it.
Everything before that stop is read-only.

Two things stay off-limits even here: **never push**, and never run this on the trunk itself.

## Repo snapshot

The block below runs once, before any of this reaches Claude — steps 1, 3, and 4 start with the answer already in hand instead of each costing its own tool call and turn.
It assumes the default trunk (`main`, falling back to `master`); it does not read `$ARGUMENTS`, so a trunk name given there is not covered.
When step 3 lands on a trunk the snapshot did not use, re-run these same queries against it; steps 4 and 5 then read your numbers in place of the snapshot's.

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
   The snapshot's `merge-base` and `commits base..HEAD` answer this.
   An empty commit list means "nothing to land" — report that and exit.

5. **Has the trunk moved?**
   The snapshot's `trunk-moved` answers this.
   If it moved, `--ff-only` will fail.
   The plan then gains a `git rebase <trunk>` between the squash and the merge — one commit to replay, but say plainly that a conflict there needs the user's hands.
   Never substitute a merge commit for the rebase without saying so.

   5a. **Does the trunk already hold part of this branch?** — only when step 5 said the trunk moved.
   A branch that sat while a sibling landed carries commits whose work is on the trunk already, under different hashes.
   `git log --cherry-mark` will not find them: what this skill writes is a squash, so nothing shares a patch-id with it — the skill's own output defeats the only duplicate check git offers.
   The trunk is then ahead in topology while the branch is behind in content, and step 13's plain `rebase <trunk>` stages a reversal of the trunk's newer work.

   Find the **content fork-point** instead: the newest commit on the branch whose every file touched since `<base>` already has the same blob on the trunk.

   ```sh
   for c in $(git rev-list <base>..HEAD); do          # newest first
     files=$(git diff --name-only <base> "$c")        # everything the branch touched up to c
     [ -z "$files" ] && continue
     git diff --quiet <trunk> "$c" -- $files && { echo "content fork-point: $c"; break; }
   done
   ```

   That file list is cumulative on purpose, and narrowing it to the files `c` itself touched breaks the step.
   When the trunk holds a later commit's work but not an earlier one's — a cherry-picked hotfix, a partial landing — the narrow test names the later commit as the fork-point, and `rebase --onto` then deletes the earlier one with nothing on screen to show for it.

   Nothing printed means the whole branch is new — carry on with `<base>` unchanged.
   A commit printed means everything up to and including it is already on the trunk: **that commit is the real base**, every step from 6 on uses it in place of `<base>`, and the replay is `git rebase --onto <trunk> <real base> <branch>` — never the plain `rebase <trunk>` from step 5.

   Show the evidence in the step 8 plan: how many commits fall away, the trunk commit that landed them — find it by subject in `git log <base>..<trunk>` — and the blob comparison that proves the trees agree.
   Dropping commits is the one thing here the user cannot check by reading a diff, so it is stated, never assumed.

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
     The commits step 6 drops as corrections are not chapters either — the same test decides both, and it folds each one into whatever it corrects.
     A commit that opens a subject of its own — a second feature the user asked for on the same branch, say — is a chapter in its own right; two such subjects never fold together just because they share a branch.
     What is left after folding is the branch's real chapter count: usually one, occasionally a genuine few when the branch bundles more than one subject.
     Build exactly that many commits — never split further just because a correction happened along the way, never merge two subjects into one just because they happen to share a file (`references/grouped.md` decides that case).
     Say so plainly whenever the count comes out above one, whether or not `--grouped` was passed — the shape is the branch's own; `--grouped` only lets the user skip straight to it.

   Show the user, in one block: the chapters found and which original commits fold into each, the generated message(s), the `todo/`/`gi/` paths being dropped, each hash from step 7a with the file citing it and whether it is dropped or repointed (step 11a), an `archive/<branch>` overwrite warning if `git tag -l` finds one, the rebase warning from step 5, the content fork-point from step 5a with its evidence if one was found, any branch step 13b will offer to re-base, the exact merge command, and the branch-delete command from step 13a.
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
    Safe only because of the tag from step 9, the dropped `todo/`/`gi/` commits included.
    On the squash path, `git reset --soft` produced a new commit object that differs from the branch tip, so git won't recognize it as merged: use `git branch -D <branch>`.
    When step 8 sent you straight to the merge (already one clean commit, no squash, no tag), the branch tip *is* the trunk tip now, so the plain `git branch -d <branch>` works.

    13b. **Re-base the branches built on this one.**
    They are long-routed now: their history holds commits the trunk no longer has, so a later merge or rebase there re-applies or conflicts with work that is already in.
    Find them with the tag from step 9, which is the old branch tip itself — use the trunk tip instead when step 8 skipped the squash:

    ```sh
    git branch --format='%(refname:short)' | while read -r b; do
      [ "$b" = "<trunk>" ] && continue                # contains itself on the no-squash path
      git merge-base --is-ancestor archive/<branch> "$b" 2>/dev/null && echo "$b"
    done
    ```

    For each one: run step 5a's fork-point against the new trunk, tag the tip (`git tag archive/<other>-prerebase <other>` — a rebase orphans the originals exactly as `reset --soft` does), then `git rebase --onto <trunk> <its fork-point> <other>`.
    The branch keeps its own commits and loses the duplicated ones.
    **Ask before running it**: this rewrites work the user did not name, and `git worktree list` may show one of these branches checked out elsewhere, where a rebase moves that worktree's files under whoever is working in it.
    The test catches a branch that contains the whole landed branch; one forked from its middle is caught by step 5a when its own turn comes.

14. **Report**, briefly: the trunk's new commit, that the user is now standing on `<trunk>` (say it plainly — the next edit would otherwise land there), that `<branch>` was deleted, and — if step 9 ran — that `git log archive/<branch>` still holds the full history.
    Split the leftover working-tree state from step 11 into notes still open and artifacts this branch completed; for the completed ones give the `rm` command (`allowed-tools` here is git only, so the user runs it).
    This is also where run status belongs — `nutest run` → `57 passed`, not in the commit body.
    Name every branch step 13b re-based, with its `archive/<other>-prerebase` tag, and every one you offered and the user declined — a branch left long-routed is the next session's conflict.
    Do not push.

## Landing as more than one commit

`references/grouped.md` holds that path: how the chapters are found, how a file shared by two of them is split, and which of steps 10–13 change.
Read it at step 8, once the chapter count comes out above one — or straight away when `--grouped` was passed.

## Related

- `/git-intent-squash-archive` — the same shape, but inside the gi loop: it squashes and archives a canvas branch and stops there, without merging.
  Reach for it when the branch is gi working material; reach for `land-branch` for ordinary development.
