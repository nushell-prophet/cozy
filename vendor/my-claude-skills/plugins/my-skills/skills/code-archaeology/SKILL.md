---
name: code-archaeology
description: >
  Recover from git history why a piece of code is the way it is — what was tried
  and dropped, what changed together with it, and the reasoning the author wrote
  down at the time. Use this skill when the user asks "why is this like this",
  "why was it done this way", "what was tried before", "почему так", "откуда это",
  "history of this function", "who decided X and why", or before changing code
  whose shape looks arbitrary. Also use when a fix keeps regressing — the history
  usually holds the constraint the current attempt is breaking.
version: 0.1.0
---

Code shows WHAT.
The reasoning behind it — the alternative that was tried and reverted, the constraint that forced an ugly shape, the file that must change alongside — lives in commit bodies, in deleted diffs, and in the shape of what changed together.
None of that is visible in the working tree.
This skill retrieves it.

The output is not a story.
It is a set of quotes with addresses: a SHA, a date, the author's own words, a `file:line`.
Everything you cannot attribute that way is your inference, and it must be labelled as one.
A confident retelling of history you did not verify is worse than no answer — the user then has to go check it themselves, which is the work you were asked to do.

## First: is this repo the right repo

Two workspace habits move the history somewhere other than where the code sits.

**Vendored copies.**
In the `cozy` workspace, modules are rsynced from sibling repos into `cozy/`.
The vendored copy has no shared history with its source: `git log` there shows only `vendor: <repo> — <summary>` bumps.
The commit bodies, the attempts, the `# Why:` reasoning are all in the sibling repo.
Check `cozy/toolkit/vendor.yml` for which paths are copies, and run the archaeology in the source repo.

**Squashed landings.**
A branch lands on the trunk as one commit, by design — the trunk is written for a reader, not as a record of the road.
The road survives in a tag.
So `git log` on the trunk is the wrong place to ask "what was tried", and absence of an attempt there is not evidence it was never tried.
See step 3.

## Procedure

The steps are ordered, but the question tells you where the answer most likely sits, so start there:

- **"why is this the way it is"** — a shape you are about to change.
  Start at step 1.
- **"was X ever tried"** — an approach you are about to introduce.
  Start at step 4: the code is not in the tree, so line history will never reach it.
- **"what else has to change with this"** — start at step 5.

That says where to look *first*.
It does not say to look less.
Every question still passes through step 3, because the branch history may be archived, and step 6, because the reasoning is usually already written down.

Past that, keep going.
Reading history is cheap and a missed commit is a wrong answer, so when you are weighing whether one more `git log` is worth running, it is — there is no budget here to protect and no credit for finishing early.
The only search you can safely leave unrun is one whose result you were never going to mention.
And the moment you are about to write that an approach was never tried, or that nothing ever chased a root cause, that is precisely the search you now have to run: see *An absence is a claim* below.

**1. Pin the target to lines.**
`git log -L` needs a file and a line range, so turn the question into `<file>:<start>,<end>` first.
If the user named a symbol, Grep for it.
Use the range of the whole function or block, not one line — a single line's history is usually just the last reformat.
Note that the ranges apply to `HEAD`: if the working tree has uncommitted edits above the block, the numbers shift, so pin against the committed file.

**2. Read the history of exactly those lines.**

```
git log -L <start>,<end>:<file> --no-patch
```

`-L` follows the block as it moves inside the file, which is what makes it better than `git log -- <file>` (every unrelated change to that file) and better than `git blame` (only the last touch).
Start with `--no-patch` for the list of commits, then drop the flag and read the diffs — every one whose body does not already settle what it did, which in practice is most of them.

`-L` cannot be combined with `--follow` (git: `--follow requires exactly one pathspec`).
If the file was renamed, find the rename with `git log --follow --name-status -- <file>`, then re-run `-L` against the old path for the earlier part of the history.

**3. Hop into the archived branch history.**
For each commit from step 2, read its full body.
A body ending in `Archive: archive/<branch>` means that commit is a squash — the branch's real history is in that tag, and that is where the attempts are:

```
git log archive/<branch>              # the road, including reverted attempts
git log main..archive/<branch>        # only what the landing dropped
```

For search-shaped questions, `--all` reaches tags directly, so one command covers the trunk and every archive at once: `git log --all -S '<string>'`.
Use `git tag -l 'archive/*'` to see what exists.

Worked example from this repo: `git log main..archive/add-toolkit-nu` shows `fix: address nushell-reviewer findings in toolkit.nu`.
That commit is on no branch.
The review that produced it, and the bug it fixed, exist nowhere else.

**4. Find what was removed.**
Code that was tried and dropped leaves no trace in the tree, only in diffs.

```
git log --all -S '<exact string>'          # commits where the count of that string changed
git log --all -G '<regex>'                 # commits whose diff mentions the pattern
git log --all --diff-filter=D --name-only -- <path>
git log --all --grep='^Revert'
```

`-S` is the one that answers "was this approach ever in the tree".
It reports the commit that introduced the string and the commit that removed it; read both bodies.

**5. Find what changed together.**
For each key commit: `git show --stat <sha>`.
Then look across the set — files that keep appearing in the same commits are coupled, and that coupling is usually an invariant nobody wrote down.
This is what a per-file history cannot give you, and it is the part that predicts what your own change will break.
Count over a window you can name out loud ("the 30 most recent commits touching this file"), and read *History has a shelf life* below before trusting the counts.

**6. Read bodies before diffs.**
This project mandates the user's reasoning in the commit body, closely paraphrased or verbatim.
So the answer is often already written in plain words, and a diff read first will send you inventing a rationale for something already explained.

```
git show -s --format='%h %ad%n%B' <sha>
```

**7. Look outside git for what git does not carry.**
`# Why:` and `# Not <alternative> because:` comments sit at the decision point in the code.
`todo/` notes carry a known-but-unfixed problem and an `origin_session:` UUID pointing at the full session.
`gi/` holds the canvas discussion.
`todo/` and `gi/` are deliberately kept off the trunk, so they exist only on branches and inside archive tags — reachable through step 3, invisible from `main`.

## History has a shelf life

A commit explains the code as it was structured *then*.
When the structure has since moved, the reasoning can be sound and the conclusion still wrong — and that failure is invisible, because an outdated commit body reads exactly as authoritative as a current one.

So for every finding, check that what it assumed still holds.
A rationale that turns on a file, a function, or a list that no longer exists there is superseded: say so, and say roughly from when.
The same goes for co-change counts — files that always moved together before a refactor split them prove nothing about today.
Prefer the commits after the last structural change to that area, and name the window you counted over so the reader can judge it.

The *measurements* inside a commit body expire the same way, and this one is easy to miss because the sentence reads like a fact rather than a reading.
"No row in the database is NULL" was true on the day it was written; quoting it as the current state passes a stale reading off as a fresh one.
Whenever the decision you are reporting rests on such a number, re-run the check yourself and say that you re-ran it — that turns someone else's old evidence into evidence the reader can act on today.

## The output contract

**Open with the answer to the question that was actually asked.**
Nobody wants archaeology for its own sake — they are about to change something, and the history is evidence for that decision.
So the first sentences say what to do: this was already tried and reverted, this shape is load-bearing, nothing is recorded either way.
Then comes the evidence, which is what makes it a checkable answer instead of an opinion.
A report that makes the reader assemble the conclusion themselves has done half the job.

Report each finding in this shape, most relevant first:

```
<short sha>  <date>  <subject>
  > verbatim quote from the body — the author's words, not yours
  touched together: <files from --stat that matter>
  in the code now: <file>:<line>
```

Three rules make it usable:

- **Quote, do not summarize.**
  A commit body is already a lossy compression of a conversation.
  Retelling it in your own words is a second layer of loss over the first, and the reader cannot check it without opening the commit anyway.
- **Keep found and inferred visibly apart.**
  This is the one thing that makes the report worth more than a good guess, so it is worth a little structure: "the body says X" and "so probably Y" are different kinds of claim, and a reader who cannot tell which is which has to either re-verify all of it or trust all of it.
  Mark each inference where it appears, and where there are several, close with a short list of what you concluded rather than found.
  A reader who can skip straight to that list and check only those lines is exactly the outcome.
- **An absence is a claim, so give it an address too.**
  "Nothing in the history explains this" is a real and useful answer — it tells the reader the shape is unexplained before they go changing it.
  But a negative claim is exactly as checkable, or as unfounded, as a positive one, and its address is the scope you searched: "no commit chases the root cause — `git log --all -S 'start_timestamp'`, both repos".
  Without that scope you are not reporting that something is absent, only that you did not happen to see it, and stating the first when you have done the second is how a confident false negative gets written.
  It is the *unattached* transcript that has to go: a list of commands hanging off no particular claim is narration, while the same command written next to the claim it supports is that claim's evidence.

## Running it in a subagent

When the question spans more than one snippet or more than one repo, spawn one read-only subagent per target.
The point is coverage, not economy: each one can dig its own target to the bottom in parallel, and you get back addressed quotes instead of having to skim everything yourself and miss things.

Give each subagent the output contract above **verbatim**, and tell it explicitly that its job is to quote, not to conclude.
A subagent left to write a summary will hand back a smooth paragraph with no SHAs, and then nothing in the chain is checkable.

## Traps

- **`git blame` answers a different question.**
  It gives the last commit to touch a line, which is usually a rename, a reformat, or a whitespace pass.
  Use it as a pointer into step 2 (`git blame -w -C -C` ignores whitespace and follows moved lines), never as the answer.
- **Do not stop at the first commit that touched the block.**
  The interesting one is usually the second or third — the first is where the current shape arrived, not why.
- **A merge is not a squash.**
  Only a body with an `Archive:` trailer promises the history is elsewhere.
  Without it, what you see is what there was.
- **Shallow clones lie.**
  `git log` in a shallow or partial clone ends early with no warning.
  `git rev-parse --is-shallow-repository` before concluding that a line has no history.
