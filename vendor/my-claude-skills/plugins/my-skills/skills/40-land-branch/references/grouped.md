# Landing as more than one commit

Read this at step 8 of `../SKILL.md`, once the chapter count comes out above one — or straight away when `--grouped` was passed.
Everything not restated here runs exactly as `../SKILL.md` says.

Step 8's own analysis is what decides a branch needs more than one commit — not a flag.
`--grouped` only saves a round trip: pass it when you already know the branch bundles more than one subject, and the plan goes straight to the multi-commit shape instead of first proposing a single squash.

The trade-off is the same either way, and the user takes it on by confirming the plan: the chapter commits reach the trunk as ordinary commits, one after another, with no merge commit around them.
A multi-subject branch is an accident of workflow, not a unit — a merge commit would record that accident, and its body would have to describe several subjects at once.
Landing plain keeps the history one shape: linear, exactly like the squash path.
The cost: each chapter's body must be self-sufficient, because no other place survives to carry its reasoning.

Steps 1–7a and 9 run unchanged.
The archive tag still matters: `reset --soft` makes the original commits unreachable here too.

## Folding corrections, grouping by subject

A chapter is a subject in the branch's own story, not a raw file path — but paths are the mechanism for building one.
Walk the history from step 6 and assign each commit to the chapter whose subject it belongs to.
The test is what the commit is *for*, not how it reads: a bug review found and the atomic fix that followed it, a typo caught later, an attempt and its revert — each of these corrects or completes a subject an earlier commit already opened, so none is a chapter of its own no matter how clean the commit itself is.
It folds into the chapter it corrects, and contributes nothing to that chapter's message (same rule as step 6's *no run status* — extended to *no trace of the correction itself*).

This folding is automatic once you group by subject, and needs no hunk-editing to work: staging a path with `git add` after `reset --soft` stages that path's **final** working-tree content, not any one commit's diff.
A bug fixed by its own later commit, a typo fixed three commits after, or a file added and then fully reverted, already comes out right — or vanishes entirely — in whichever chapter's commit picks up that path.

When a file's changes cannot be attributed to a single chapter — a correction's own changes touch two candidates, or two independently-motivated subjects both need the file — the file is **split** between the chapters (next section), not the chapters merged.
Merging chapters is the last resort, reached only when the split itself is unsafe: it erases the branch's real shape just because two subjects happened to share a file.

## Splitting a shared file

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

## Steps 10–12, replaced

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

## Step 13, unchanged

Step 13 runs as written: `git switch <trunk>`, then `git merge --ff-only <branch>` — with the step 5 rebase first if the trunk moved (several commits to replay now, and a conflict there still needs the user's hands).

13a: `reset --soft` rebuilt the chapters, but the ff-merge just put that rebuilt tip on the trunk itself, so the plain `git branch -d <branch>` works.
13b runs as written too — a branch built on this one is long-routed however many commits landed.
