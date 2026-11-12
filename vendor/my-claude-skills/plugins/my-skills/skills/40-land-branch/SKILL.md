---
name: 40-land-branch
description: Land a finished branch on the trunk as a coherent commit — fold the rollback commits into the work they correct, carry the branch's reasoning into the message, archive the old history in a tag, keep `todo/` and `gi-canvas/` off the trunk, then merge. Use when the user says "land the branch", "land this", "merge to main", "finish this branch", or "squash and merge".
argument-hint: [--grouped] [--no-confirm]
allowed-tools: Bash(git *), Read, Write, Edit
---

A working branch carries rollback points: a bug review found and the atomic commit that fixed it, an attempt and the commit that reverts it, a typo caught two commits later.
These are not sloppy — an agent-authored fix is usually just as clean and atomic as the commit it corrects.
What makes a commit a rollback point is its subject, not its tone: it exists only to correct or complete something an earlier commit in the same branch already claimed.
The moment the branch lands none of that may survive — not as its own commit, not as a line in a message.
A later agent reading `git log` on the trunk should find the coherent story the branch tells, not the back-and-forth it took to arrive there.

So the branch lands as the smallest sequence of commits that story actually has — usually **one**, squashed; a genuine few when the branch bundles more than one (see `references/grouped.md`).
Either way its full history survives in a tag, and the working material (`todo/` and `gi-canvas/`) never reaches the trunk at all.

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

`--no-confirm` gives that confirmation in advance:
the agent does not wait at step 8,
and the report of step 14 carries the rows of the plan.
The advisor call of step 8 still runs.
The flag answers one question: "run this plan?".
A decision the plan cannot make stays with the user,
so the agent still stops before step 9 when:

- step 5a finds a content fork-point, because dropped commits do not show in a diff;
- step 8 finds a chapter of another feature;
- `references/grouped.md` needs a whole-hunk patch, or merges two chapters that share one hunk, because the user takes on that risk;
- the advisor finds a problem that needs the decision of the user.

A contrast line from step 7c is cut at step 11b and named in the report, because the diff shows the cut.
A branch from step 13b is not re-based and the report names it as declined, because that rewrite is work the user did not name.
A conflict in the rebase of step 13 stops the landing after step 9 too:
the agent does not resolve it,
and the archive tag holds the old tip.

Two things stay off-limits even here: **never push**, and never run this on the trunk itself.

## Repo snapshot

The block below runs once, before any of this reaches Claude — steps 1, 3, 4 and 5 start with the answer already in hand instead of each costing its own tool call and turn.
It looks for a local `main` and a local `master` and reports what it found: one name, both, or none.

```!
branch=$(git branch --show-current)
echo "current-branch: ${branch:-<detached HEAD>}"
candidates=""
for t in main master; do
  git show-ref --verify --quiet "refs/heads/$t" && candidates="$candidates $t"
done
candidates=${candidates# }
echo "trunk-candidates: ${candidates:-<none>}"
for trunk in $candidates; do
  base=$(git merge-base "$trunk" HEAD 2>/dev/null)
  echo "[$trunk] merge-base: $base"
  echo "[$trunk] trunk-head: $(git rev-parse "$trunk")"
  echo "[$trunk] trunk-moved: $([ "$(git rev-parse "$trunk")" = "$base" ] && echo no || echo yes)"
  echo "[$trunk] commits base..HEAD:"
  git log --oneline "$base"..HEAD 2>/dev/null
done
```

## Replies

The user reads these replies as he reads the output of a shell command:
he looks for the same element in the same place every time.
So the plan of step 8, the report of step 14 and every stop have a fixed shape.

- The reply is a column of rows and nothing else: no paragraph before it, no question after it.
- The rows are one `text` block, and each line of it is one row, `│ <label> │ <value>`, `│ land │ branch → main`, with the labels padded to one width.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  A value of several lines, such as a commit message or the output of a command, goes on the next lines, each with both `│` and spaces in the label cell.
  The skeletons below show the rows as plain text; the reply adds the borders, the padding and the emoji.
  The labels, their order and the fixed values (`land as shown`, `nothing changed`, `none`) are always in English.
  The free text of a value is in the language of the session.
- A row prints only when it has something to say.
  A check that found nothing gets no row: no "no hits", no "nothing to re-base".
  The rows that always print are named under each shape.
- Several findings of one kind are several rows with the same label.
- `warn` is the one row with no step behind it: a fact that changes what the user does or expects.
  A check that passed is never a `warn`.
- A commit message is always in full, never a path to a file.
- An `ASSUMED:` list, which the global rules ask for an unchecked claim, goes after the rows: it is the one other text.
- The last row of a plan is `│ 🟢 go │ land as shown`, word for word.
  Every choice that `go` makes is a `pick` row above it, with its default.

A stop — a guard of steps 1 and 2, a branch of only working material at step 11, a conflict, a hook that blocks a command, a decision that `--no-confirm` leaves to the user (see *Authorization*) — has this shape:

```text
stop      <step number, or the name of the hook>: <the cause in one line>
state     nothing changed | <what changed; archive/<branch> keeps the old tip>
proof     <one line, or the output of a command on the next lines>
pick      <question> · default: <choice> · else: <the other choices>
go        <what go does: the defaults above>
next      <the exact action for the user>
```

`stop`, `state` and one of `go` and `next` always print.
`go` is there only when the agent can go on with a default.
When only the user can act, `next` ends the reply instead.

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
   `trunk-candidates` from the snapshot names it.
   One name: that is the trunk, and every `<trunk>` below means it.
   Two names or `<none>`: stop and ask the user which branch is the trunk — a repo can carry a stale `master` beside `main`, and only the user knows which one is live.
   If the branch the user names is `current-branch`, stop as step 1 would have.
   If it is one the snapshot did not print, run the block's per-candidate lines against it, so steps 4 and 5 have their numbers.
   Do not probe for the trunk yourself with `git rev-parse` or `git branch`, and never assume `main`: the snapshot already looked, and in past sessions agents ran `git merge-base main HEAD` in `master` repos and failed.

4. **Find the base.**
   The snapshot's `[<trunk>] merge-base` and `[<trunk>] commits base..HEAD` answer this.
   Read the lines of the trunk step 3 settled.
   An empty commit list means "nothing to land" — report that and exit.

5. **Has the trunk moved?**
   The snapshot's `[<trunk>] trunk-moved` answers this.
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
   This is the part that must not be lost: why this approach, why an alternative was rejected, why the user wanted it.
   Drop only the mechanics — not just `wip` or a typo fix, but any commit whose whole job is correcting or completing an earlier commit's own subject, however cleanly that correction itself is written: a bug review found and its atomic fix, an attempt and the commit that reverts it.
   None of these earns a line, even a summarized one; the message describes the approach that survived, not the road to it.
   When the folded bodies give one reason per file,
   merge them into that one reason:
   a line per file retells the diff.
   If the branch has a canvas in `gi-canvas/` or the current session holds reasoning that never reached a commit body, pull it in here — the tag preserves the old bodies, but only this commit is read on the trunk.

   **Strip every `Change-Id:` trailer from what you fold in.**
   The `commit-msg` hook adds an id only to a message that has none, so a trailer copied out of a folded body becomes the landing commit's own id — the same id as a commit the archive tag keeps, a duplicate the skill itself manufactured.
   The landing commit gets a fresh id from the hook by carrying none into `git commit`.

   **No run status in the body.**
   Lines like `235 tests passed`, `all checks green`, `verified with nutest` do not belong in the commit message.
   They were true at one moment on one tree; on the trunk they are unverifiable and often already false.
   Report them in the chat reply, where the user reads them while they still mean something.
   The body carries *why*, not *it worked*.

   **No hash of a commit inside `base..HEAD` either — and no short `Change-Id` of one.**
   The commit you are writing is the only address those changes will have on the trunk; every hash in the branch's own bodies names a commit the landing is about to rewrite, and so does the id of one: the archive tag keeps that commit, but the trunk will not have it.
   When a body you are folding cites one, the citation goes with the rest of the correction.
   A message is worse than a file here: a file can be repointed afterwards, a body cannot without rewriting the trunk — so this is the only moment.
   Two exceptions: a message whose subject *is* the rewrite — then name `archive/<branch>` beside the hash, so the reader has something that resolves — and the `Archive:` trailer of step 12, which names the archived tip by its id on purpose.

   **The body leaves this repo — write it for whoever receives it.**
   The trunk is not the last stop.
   A published repo gets cloned, and a clone keeps the message as it is: a repair after that rewrites the trunk that others already hold.
   This is the only moment, and the test is one question: can a reader who has nothing but a clone of the trunk follow every pointer in this body?
   These shapes fail it:

   - **A `todo/` or `gi-canvas/` path.**
     In a published repo step 11 drops those files from the trunk, so the pointer is dead in every clone, by design.
     A note is not a reference, it is the source you are copying from: what the commit took from it goes into the body itself.
   - **A local path.**
     An absolute `/Users/...` path, or a relative one that leaves the repo (`../sibling/...`), resolves on this machine and on no other.
   - **Session shorthand.**
     "task 4", "the audit", "the survey", a branch name nobody kept, a slash command.
     Each was clear to the session that wrote it and to nobody after; say what it meant.
   - **A bare sha.**
     The rule above bans the hashes of `base..HEAD`; this one bans the rest.
     A sha dies with every rewrite of a branch that has not landed, and it names nothing for a reader without the object; a `Change-Id` travels inside the message.
     Name the commit by its short `Change-Id` where the repo stamps one, and where it stamps none, say what that commit did instead of pointing at it.
   - **A quoted command.**
     A repo may keep the user's commands verbatim in branch bodies, for an audit — "ok go ahead", "fix point 3".
     Each one answered a question the reader of the trunk never saw.
     Carry the reason the command gave into the body; the archive tag keeps the words.

7. **Find the working material.**
   `git diff --name-status <base>..HEAD -- todo/ gi-canvas/`.
   Keep the status letters; they decide what the working tree looks like afterwards (step 11).

   **First: does this repo publish them?**
   Read the repo's root `CLAUDE.md`.
   If it says the repo is personal, internal, or never sent upstream, then `todo/` and `gi-canvas/` are ordinary content there — they land with everything else, and steps 7, 11 and 11a have nothing to do.
   Say so once, in one `drop` row of the step 8 plan, instead of listing paths to drop.
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

   A repo that stamps `Change-Id` trailers cites commits by the short id as well, so the same scan runs a second time for ids — 8 or 32 letters `k` to `z`, resolved through the trailer before the ancestor tests, because English words match that alphabet too (`tomorrow` does):

   ```sh
   git diff <base>..HEAD | grep '^+' | grep -v '^+++' | grep -oE '\b[k-z]{8}\b|\b[k-z]{32}\b' | sort -u |
   while read -r id; do
     for h in $(git log --all --format=%H --grep="^Change-Id: $id"); do
       git merge-base --is-ancestor "$h" HEAD 2>/dev/null || continue
       git merge-base --is-ancestor "$h" <base> 2>/dev/null && continue
       echo "$id $h"
     done
   done
   ```

   A word that resolves to nothing is not an id and falls out by itself; an id that resolves to a commit this landing rewrites is settled at step 11a exactly like a hash.

   7c. **Find prose that explains the change instead of the result.**
   A comment or a `.md` line written during the branch tends to define the new design by contrasting it with the one it replaces — "not as a pile of timestamped files", "instead of writing a flat copy", "`restore` used to overwrite it whole".
   Step 6 asks for exactly that contrast in the *body*, where it is the point.
   In the tree it fails the same outside-reader test: whoever arrives after this lands never saw the old design, so the contrast costs them a paragraph and tells them nothing, while git history holds it for anyone who goes looking.
   The rule is `CLAUDE.md`'s **The reader never saw the previous version**, together with the bullet under it on `# Not <alternative> because:` — a live alternative, never the implementation this change retired — both are stated there, and this step is only where they get enforced.

   Scan the added lines for contrast framing.
   Same input as 7a, a different test:

   ```sh
   git diff --unified=0 <base>..HEAD | awk '
     /^\+\+\+ b\// { f = substr(\$0, 7); next }
     /^\+/ && !/^\+\+\+/ {
       line = substr(\$0, 2)
       if (tolower(line) ~ /instead of|no longer|previously|used to|formerly|rather than|unlike the|not as a/ &&
           tolower(line) !~ /(^|[^a-z])(is|are|was|were|be|been|being) used to/)
         print f ": " line
     }'
   ```

   The second condition drops the passive "the flag is used to pick the trunk", which has nothing to do with time; nothing filters the rest.
   The `(^|[^a-z])` is a word boundary — without it "this used to" matches the passive and is dropped.
   All eight markers run in one pass here, where `40-archaeology-sweep` splits them and holds four back: that skill reads a whole repo, where the noisy four return several times the hits of the rest, and this one reads only the lines one branch added, where they cost a few.
   A hit is a candidate, never a verdict — "say what that commit did instead of pointing at it" is the same words doing honest work.
   Read each one and ask whether a reader who never saw the old state needs that sentence.
   `40-archaeology-sweep`'s *The defect* names the one thing a hit is guilty of — a sentence a reader can only follow by knowing a state the tree does not hold — and its *Not archaeology* list names the classes a hit can be innocent by: a CHANGELOG entry under `Removed`, a present-tense contrast between two live options, captured text, five more.
   Judge against those two rather than re-deriving them here.
   Calibration: on the code commit that produced the three examples above, the scan named those three lines and nothing else.
   On a branch that is only prose — a skill, a design doc — expect a handful of innocent hits, the heading of this step among them.
   Propose the cut at step 8 and let the user confirm it — the edit happens at 11b.

8. **Judgement, then STOP.**
   First call the advisor, when the tool is available, on the branch and the plan below, and address what it finds; the plan or the report says what it changed.
   Why: the user asked for "advisor, then land" by hand again and again.
   Two calls to make first:
   - Already one clean commit whose body passes step 6's outside-reader test?
     Then there is nothing to rewrite — skip straight to the merge (step 13).
     A body that quotes the user's commands fails that test, so it takes the squash path, and the tag keeps the quotes.
     No `reset --soft`, no new commit, no `Archive:` trailer, and **no archive tag**.
   - Otherwise, read the history from step 6 as a story, not a diff.
     The commits step 6 drops as corrections are not chapters either — the same test decides both, and it folds each one into whatever it corrects.
     A commit that opens a subject of its own — a second feature the user asked for on the same branch, say — is a chapter in its own right; two such subjects never fold together just because they share a branch.
     What is left after folding is the branch's real chapter count: usually one, occasionally a genuine few when the branch bundles more than one subject.
     Build exactly that many commits — never split further just because a correction happened along the way, never merge two subjects into one just because they happen to share a file (`references/grouped.md` decides that case).
     Say so plainly whenever the count comes out above one, whether or not `--grouped` was passed — the shape is the branch's own; `--grouped` only lets the user skip straight to it.
     A chapter can also belong to another feature:
     the branch was made from another branch that has not landed,
     or it carries the work of another session.
     Judge by subject, not by author
     — agents often continue the work of another session.
     Mark such a chapter in the plan, and let the user choose:
     land it as its own commit,
     or leave it out.
     To leave it out, move its commits to a branch of their own after the tag of step 9,
     and drop them from this branch with `git rebase --onto`;
     when they are not all at the bottom of the branch, say that this rebase can conflict.

   Show the plan in this shape, under the rules of *Replies*:

   ```text
   land      <branch> → <trunk> · <N> → <K> commits · squash | as is
   commit 1  <subject> ← <short ids of the commits folded into it>
             <the full message, on the next lines>
   pick      <question> · default: <choice> · else: <the other choices>
   drop      <todo/ or gi-canvas/ path> | none: <the line of CLAUDE.md that keeps them>
   edit      <file> drop "<cited hash or id>" | cut "<contrast words>"
   split     <file> between commits <k> and <m> · <mechanism>
   fork      <n> commits already on <trunk> as "<trunk subject>" · <the blob check>
   rebase    <trunk> moved <n> commits → rebase after the squash; a conflict stops the landing
   tag       archive/<branch> | archive/<branch> exists → overwrite
   merge     git switch <trunk> · git merge --ff-only <branch>
   delete    git branch -D <branch> | git branch -d <branch>
   advisor   <what it changed in this plan>
   warn      <a fact that changes what the user does or expects>
   go        land as shown
   ```

   The rows and their steps:
   - `commit`: one row per chapter, step 8; `--grouped` and the chapter count do not change the shape.
   - `pick`: a branch of step 13b ("re-base <branch>? · default: no"), a chapter of another feature, a step 7c line the agent is not sure about — each with the default that `go` takes.
   - `drop`: step 7, one row per path; one `none` row when the repo keeps its working material.
   - `edit`: step 7a hits (11a) and step 7c cuts (11b), one row each.
   - `split`: a file that `references/grouped.md` splits.
   - `fork`: step 5a, with its evidence.
   - `rebase`: step 5.
   - `tag`: step 9, on the squash path only; the overwrite when `git tag -l` already finds the name.
   - `merge`, `delete`: steps 13 and 13a.

   `land`, `commit`, `merge`, `delete` and `go` always print.

   **Wait for confirmation**, unless `--no-confirm` was passed (see *Authorization*).

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

    This is the whole `todo/`/`gi-canvas/` mechanism — no filtering, no history rewrite, one command at the one moment it is natural.
    What it leaves behind depends on the status letter, and you must **report** the leftovers rather than claim a clean tree:
    - `A` (added on the branch) → the file becomes untracked.
      This is the normal case, and exactly where a parked note belongs.
    - `M` (modified) → the change stays in the working tree, unstaged.
    - `D` (deleted) → the file is missing from disk while the index holds it back; shows as an unstaged deletion.

    A note this branch **finished** is not parked any more — it is done.
    Step 14 gives its `rm` in a `next` row, instead of leaving it in the working tree where the next session reads it as open work.
    Same for a `gi-canvas/` canvas whose thread closed with this branch.
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

    11b. **Cut the prose** — the step 7c hits the user confirmed at step 8, or after `--no-confirm` the hits the agent judged a defect — in the working tree, then `git add` each file you touched.
    Cut the defect and change nothing else: take out the words that name the gone state and leave the rest of the sentence as it stands, so what survives says what the code does now and the constraint that makes it right.
    An edit that swaps the tense and keeps the line's length has removed nothing.
    The contrast you are deleting is not lost:
    its reason goes into the body this landing writes,
    if the diff cannot show that reason.
    The deleted words stay in the diff, so the body does not retell them.
    Skip a file dropped at step 11, exactly as 11a does.

12. **Commit** with the message from step 6, plus an `Archive:` trailer naming the archived tip.
    Its value is the tip's `Change-Id`, read with `git log -1 --format='%(trailers:key=Change-Id,valueonly)' archive/<branch>`, because the id travels inside the message, so it still names that commit if the tag is renamed or deleted; when that prints nothing — the repo stamps no ids, or the tip predates the hook — the value is the tag name, `archive/<branch>`.
    The tag from step 9 is written either way: an id keeps nothing alive, only a ref does.
    This trailer is the deliberate exception to step 6's outside-reader rule — the archive it names exists only here, and that is accepted, not repaired.
    Run the drafted body through both of step 7a's loops first — before the `Archive:` trailer is appended, since that trailer names the tip by design — with the message text in place of the diff and `archive/<branch>` in place of `HEAD`: after step 10 `HEAD` is `<base>`, and against it the ancestor tests flag nothing.
    A hash or an id reaching the body is usually one copied out of a folded commit, and after the commit exists there is no fixing it.

13. **Merge.**
    `git switch <trunk>` then `git merge --ff-only <branch>`.
    With the rebase from step 5 if the trunk moved.

    13a. **Delete the branch.**
    Safe only because of the tag from step 9, the dropped `todo/`/`gi-canvas/` commits included.
    On the squash path, `git reset --soft` produced a new commit object that differs from the branch tip, so git won't recognize it as merged: use `git branch -D <branch>`.
    When step 8 sent you straight to the merge (already one clean commit, no squash, no tag), the branch tip *is* the trunk tip now, so the plain `git branch -d <branch>` works.

    13b. **Re-base the branches built on this one.**
    They are long-routed now: their history holds commits the trunk no longer has, so a later merge or rebase there re-applies or conflicts with work that is already in.
    Find them with the tag from step 9, which is the old branch tip itself — use the trunk tip instead when step 8 skipped the squash:
    The plan of step 8 needs them before that tag exists, so there the test runs with `HEAD` in place of `archive/<branch>`.

    ```sh
    git branch --format='%(refname:short)' | while read -r b; do
      [ "$b" = "<trunk>" ] && continue                # contains itself on the no-squash path
      git merge-base --is-ancestor archive/<branch> "$b" 2>/dev/null && echo "$b"
    done
    ```

    For each one: run step 5a's fork-point against the new trunk, tag the tip (`git tag archive/<other>-prerebase <other>` — a rebase orphans the originals exactly as `reset --soft` does), then `git rebase --onto <trunk> <its fork-point> <other>`.
    The branch keeps its own commits and loses the duplicated ones.
    The plan asks it in a `pick` row whose default is no, so a bare `go` leaves the branch alone: this rewrites work the user did not name, and `git worktree list` may show one of these branches checked out elsewhere, where a rebase moves that worktree's files under whoever is working in it.
    The test catches a branch that contains the whole landed branch; one forked from its middle is caught by step 5a when its own turn comes.

14. **Report** in this shape, under the rules of *Replies*:

    ```text
    landed    <branch> → <trunk> · <short Change-Id, or sha, of each new commit> · squash | as is | <K> commits
    branch    you are on <trunk> · <branch> deleted
    history   git log archive/<branch>
    rebased   <branch> · archive/<other>-prerebase
    declined  <branch> stays long-routed
    left      <path> · <untracked | modified | deleted> · still open
    tests     <command> → <result>
    changed   <a change against the plan: an advisor finding, a cut, a deviation>
    problem   <a defect the landing left> · fix: <command> · needs your go
    warn      <a fact that changes what the user does or expects>
    next      <the exact command or answer for the user> | nothing
    ```

    The rows and their steps:
    - `branch`: the user now stands on `<trunk>`, and the next edit would land there, so the row says it plainly.
    - `history`: step 9, on the squash path only.
    - `rebased`, `declined`: step 13b, one row per branch; a declined branch is the next session's conflict, so it also gets a `next` row with the answer that re-bases it.
    - `left`: step 11, one row per note this branch did not finish.
    - `tests`: the run status that step 6 keeps out of the body, `nutest run` → `57 passed`.
    - `next`: one row per action — the `rm` of each note or canvas this branch finished (`allowed-tools` here is git only, so the user runs it).

    `landed`, `branch` and `next` always print, and `next` is the last row.
    After `--no-confirm` the report opens with the rows of the plan from `commit` to `warn`, because the user saw no plan.
    Do not push.

## Landing as more than one commit

`references/grouped.md` holds that path: how the chapters are found, how a file shared by two of them is split, and which of steps 10–13 change.
Read it at step 8, once the chapter count comes out above one — or straight away when `--grouped` was passed.

## Related

- `/git-intent-squash-archive` — the same shape, but inside the gi loop: it squashes and archives a canvas branch and stops there, without merging.
  Reach for it when the branch is gi working material; reach for `land-branch` for ordinary development.
