---
name: 40-why-is-this
description: >
  Recover why a piece of code, a convention, or a comment is the way it is — from
  git history (what was tried and dropped, what changed together with it, the
  reasoning the author wrote down at the time) and from the Claude Code session
  transcripts in ~/.claude/projects (what question was actually on the table, what
  the answer covered, what was never asked at all). Use this skill when the user
  asks "why is this like this", "why was it done this way", "what was tried
  before", "did I ask for this", "who decided this", "почему так", "откуда это",
  "я это просил", "откуда эта конвенция", "history of this function", or before
  changing code whose shape looks arbitrary, or before obeying a comment that
  states a rule nothing tests. Also use when a fix keeps regressing — the history
  usually holds the constraint the current attempt is breaking — or when a
  convention keeps being treated as settled and nobody can say where it came from.
version: 0.1.0
---

Code shows WHAT.
It never shows the circumstances.
The alternative that was tried and reverted, the constraint that forced an ugly shape, the question that was asked and quietly never answered — none of that is in the working tree.
And a comment an agent wrote to justify its own choice reads exactly like a comment written from the user's instruction, so once it is in the tree every later agent treats it as law.

This skill recovers the circumstances, so the thing can be looked at again with them intact.

**This is not a hunt for who is at fault.**
An agent deciding on its own is normal and necessary — at the volume this work runs at, an agent that referred every choice upward would not finish anything.
And a decision the user did make can still be worth re-opening: he may have wanted something else, may have read a different question than the one asked, or may have wanted exactly this for a reason that has since expired.
Restoring the circumstances is the whole deliverable.
The verdict is a by-product, and it is never a charge.

The output is not a story either.
It is a set of quotes with addresses: a SHA and a date, or a session and a timestamp, and a `file:line`.
Everything you cannot attribute that way is your inference, and it must be labelled as one.
A confident retelling of history you did not verify is worse than no answer — the user then has to go check it themselves, which is the work you were asked to do.

## Which source, and the trap between them

**git** says when and what changed, and often why — this project mandates the user's reasoning in commit bodies.
**`~/.claude/projects`** says what was actually asked and answered.
Neither alone can tell an instruction from an agent's own choice: a commit body states a rationale in the same voice whether the user supplied it or the agent invented it.

The two paths do not cost the same.
Git is cheap — a `git log -L` is one command, and you want it before changing almost anything.
The transcripts are heavy — a search across every project, in two languages, over logs where roughly seven in eight `type:"user"` rows are not the user.

So start from the question:

- **"why is this the way it is", "was X ever tried", "what else changes with this"** — *From git*, below.
  Stop there when it answers.
- **"did I ask for this", "who decided this", "where did this convention come from"** — both.
  Anchor in git first (step 8), then go to *From the transcripts*.

**The trap is the git path's exit.**
Reading a history to the bottom and finding nothing is a real answer, and this skill requires you to report it with the scope you searched.
But in this workspace a large share of decisions were never argued in a commit at all: an agent chose, the reason went into the session, and from there straight into a comment.
So before writing that the history records nothing, ask whether the question was about a *decision*.
If it was, git's silence is not the answer — it is the reason to open the transcripts.
"Nothing explains this" written while the exchange sits in `~/.claude/projects` is the confident false negative this skill exists to prevent.
Step 7 of the git path is where that hand-off usually becomes visible.

## First: is this repo the right repo

Two workspace habits move the history somewhere other than where the code sits.

**Vendored copies.**
In the `cozy` workspace, modules are rsynced from sibling repos into `cozy/`.
The vendored copy has no shared history with its source: `git log` there shows only `vendor: <repo> — <summary>` bumps.
The commit bodies, the attempts, the `# Why:` reasoning are all in the sibling repo.
Check `cozy/toolkit/vendor.yml` for which paths are copies, and run the search in the source repo.

**Squashed landings.**
A branch lands on the trunk as one commit, by design — the trunk is written for a reader, not as a record of the road.
The road survives in a tag.
So `git log` on the trunk is the wrong place to ask "what was tried", and absence of an attempt there is not evidence it was never tried.
See step 3.

## From git

The steps are ordered, but the question tells you where the answer most likely sits, so start there:

- **"why is this the way it is"** — a shape you are about to change.
  Start at step 1.
- **"was X ever tried"** — an approach you are about to introduce.
  Start at step 4: the code is not in the tree, so line history will never reach it.
- **"what else has to change with this"** — start at step 5.
- **"where did this sentence come from"** — a comment, a README line, a flag whose provenance you are about to check.
  Start at step 8, which is the anchor the transcript path needs.

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
`todo/` notes carry a known-but-unfixed problem and an `origin_session:` UUID — that UUID is a direct address into the transcripts, and following it is the hand-off described above, not an optional extra.
`gi/` holds the canvas discussion.
`todo/` and `gi/` are deliberately kept off the trunk, so they exist only on branches and inside archive tags — reachable through step 3, invisible from `main`.

**8. Anchor a sentence to its birth commit.**
When the target is a line of prose — a comment, a README sentence, a flag description — find the commit that introduced it before going anywhere near the transcripts:

```
git log --all -S '<verbatim fragment of the line>' --oneline
git show -s --format='%h %ad%n%B' <sha>
```

`-S` on a distinctive fragment usually returns exactly one commit.
That date is the key to the whole transcript search below.
If the wording was reworded later, try `-S` on a shorter fragment that survived, or `-G` with a loose regex.

## From the transcripts

Take this path when the question is about a decision: whether it was asked for, by whom, and against what alternatives.

### What you are reconstructing

Four situations.
None of them is a fault, and saying which one it is — with evidence — is the job.

1. **Asked for.**
   The user named it, in these words, with this reason.
2. **Answered next to.**
   The user replied, but the reply covered a neighbouring question and the open one was never re-asked.
   This is the most common way a decision becomes agent-made with nobody noticing.
3. **Asked and never answered.**
   The question was put in writing, the thread moved on, the code shipped.
4. **Never asked.**
   An agent chose and stated the reason to itself.
   Fine at the time — the cost arrives later, when the reason hardens into a comment and stops being visible as a choice.

A worked instance of #2, real: an agent asked three questions before implementing, the second being whether to hash the working copy or the committed state.
The user replied "what columns we have now? add a table with mapping variants", got a table covering **only the column layout**, and said "let's go with A, implement it".
The agent read that as an answer to everything and chose the working copy.
Two months later a comment in the code explained the choice as if it had always been the intent, and two more agents built on it.

And a worked instance of #1, to show what the other outcome looks like: `dotnu/toolkit.nu` carries a comment reading "Not `$nu.is-interactive` because: it reports REPL-ness, not human-ness", which has the shape of an agent justifying its own pick.
The transcript says the opposite — the user proposed `$nu.is-interactive` himself ("research, if we can add automatic check like `$nu.is-interactive`"), the agent researched it, found it inverted, and the comment is its answer to him.
The reconstruction closed the matter instead of re-opening it, which is worth as much.

### Reading the logs

`~/.claude/projects/<slug>/` holds one directory per project, slug = the session's working directory with `/` replaced by `-`.
Inside are `.jsonl` session logs.
Do not parse them by hand: `claude-nu` already does, and the two things it gets right are the two that decide this skill's answer — it reads only what someone actually said, and it knows a subagent log holds no human words.

```
use ~/repos/claude-nu/claude-nu/ *
```

The `*` is what makes the commands below bare; without it every one of them is spelled `claude-nu sessions`, `claude-nu messages`.
In an interactive shell they are already loaded, prefixed.

1. **Go from the artifact to the session, not from the repo name to the session.**
   `sessions --all-projects --columns edited_files,first_timestamp,last_timestamp,session_id,cwd | where ($it.edited_files | any {|f| $f =~ '<basename>'})` names the sessions that touched the file; keep the ones alive around the anchor date from step 8.
   A basename shared across repos (`toolkit.nu`, `mod.nu`) matches everywhere — 92 sessions in one run here — so match on enough of the path to be distinctive, then let the date cut the rest.
   This is exact where a name guess is not.
   A slug is the cwd the session ran in, so work on one repo routinely sits under the workspace root or under a sibling — `ls ~/.claude/projects | grep -i <repo>` is the wrong instrument and it fails silently.
2. **User turns first.**
   `sessions --all-projects | messages '<topic vocabulary>'` returns only what the human typed — tool results, `<command-name>` / `<local-command-*>` wrappers and meta turns are already dropped.
   In both languages: he writes Russian and English, agents answer English.
   About half a minute across every project, and it answers the question that decides all the others.
3. **Print the rows; never read the table.**
   `each {|r| print $"--- ($r.timestamp | format date '%Y-%m-%d %H:%M') ($r.project)"; print $r.message }`.
   The rendered table elides `message` — the one column you came for — and an elided hit looks exactly like no hit.
4. **Read the exchange, not the line.**
   `sessions --session <uuid> | messages --include-responses` gives the dialogue with the tool noise gone; a working session is a few dozen turns, so read it whole.
   Add `--include-thinking` when the question is what an agent decided rather than what it announced.
5. **Then the subagent logs.**
   `sessions --subagents` adds them.
   Read them only for what the *agent* decided: in a subagent log every `type:"user"` row is the parent agent's task prompt, never the human.
6. **Watch for duplicated directories.**
   The same session UUID can sit under two slugs when a repo moved.
   Same UUID means one occasion, not two.

### Reading the exchange

This is where the skill earns its place — a keyword hit is not an answer.

- **Number the questions and number the answers.**
  If an agent asked three and the reply addresses one, the other two stayed open.
  Say so explicitly.
- **An answer to a menu answers that menu.**
  If the alternative was never in the table the user was shown, the reply cannot have chosen against it — whatever the agent concluded next.
- **Scope authorization is not a design choice.**
  "implement it", "fan a team", "go ahead", a slash command that files a todo — these release work.
  They do not select between options that were never put side by side.
- **Disclosure is not consent, and not its opposite.**
  A summary reporting the choice as done ("files get X, directories get Y") means the user *could* have seen it.
  Report that plainly and quote it — he may well remember the moment.
  Silence after it is neither approval nor objection; write it as silence.
- **A todo note or an audit finding written by an agent is not the user's voice**, even under a heading like "Task from user".
  Check who wrote the file before quoting it as his framing.

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
Nobody wants the history for its own sake — they are about to change something, and it is evidence for that decision.
So the first sentences say what to do, or which of the four situations it is and what the decision rests on today: this was already tried and reverted, this shape is load-bearing, the user asked for exactly this, nothing is recorded either way.
Then comes the evidence, which is what makes it a checkable answer instead of an opinion.
A report that makes the reader assemble the conclusion themselves has done half the job.

Report each finding, in the shape that matches its source.
If you used both sources, keep them in separate blocks — do not interleave them.

**From git**, most relevant first:

```
<short sha>  <date>  <subject>
  > verbatim quote from the body — the author's words, not yours
  touched together: <files from --stat that matter>
  in the code now: <file>:<line>
```

**From the transcripts**, oldest first, so the reader watches it happen:

```
<date>  <what happened>
  USER      > verbatim
  ASSISTANT > verbatim
  → what this settled, and what it left open
  in git: <sha> <subject>   in the code now: <file>:<line>
```

Three rules make either usable:

- **Quote, do not summarize.**
  A commit body is already a lossy compression of a conversation; retelling it in your own words is a second layer of loss over the first, and the reader cannot check it without opening the commit anyway.
  For a transcript it is worse — the user is reading his own words, and a paraphrase of them is worthless for the one thing he is doing, which is remembering.
- **Keep found and inferred visibly apart.**
  This is the one thing that makes the report worth more than a good guess, so it is worth a little structure: "the body says X" and "so probably Y" are different kinds of claim, and a reader who cannot tell which is which has to either re-verify all of it or trust all of it.
  Mark each inference where it appears, and where there are several, close with a short list of what you concluded rather than found.
  A reader who can skip straight to that list and check only those lines is exactly the outcome.
- **An absence is a claim, so give it an address too.**
  "Nothing in the history explains this" and "no discussion found" are real and useful answers — they tell the reader the shape is unexplained before they go changing it.
  But a negative claim is exactly as checkable, or as unfounded, as a positive one, and its address is the scope you searched: "no commit chases the root cause — `git log --all -S 'start_timestamp'`, both repos".
  For the transcripts that scope is the terms, both languages, and the two searches that have to have run, `--all-projects` and `--subagents`.
  Without the scope you are not reporting that something is absent, only that you did not happen to see it, and stating the first when you have done the second is how a confident false negative gets written — one that, here, convicts an agent of deciding alone.
  It is the *unattached* transcript that has to go: a list of commands hanging off no particular claim is narration, while the same command written next to the claim it supports is that claim's evidence.

## What to do with it

The point is not the report.
The point is that a decision made invisible becomes re-decidable.

- **Bring it back as one question**, with the alternative named and the cost of each side, at the moment it matters.
  Not as a finding to file — a filed finding is triage the user pays for later, without the context in his head.
- **The decision may well stand.**
  Reconstructed circumstances do not make it wrong.
  Often they make it obviously right and the matter is closed for good, which is worth as much as an overturn.
- **If it stands, record it where it survives**: the commit body, a test that pins it, a line in `CLAUDE.md`.
  A convention living only in a code comment gets re-litigated by the next agent who reads it.
- **Never edit the original comment to say the user decided it.**
  Attribution invented after the fact is the same defect one layer up, and it is unfalsifiable once written.

## Running it in subagents

**On the "do not call the Agent tool unless the user requested it" preamble.** Some sessions carry that instruction from the harness, and it names no exception.
Invoking this skill is that request.
So it does not block the `quote-digger` runs below.

When the question spans more than one snippet, more than one repo, or both sources, spawn one `quote-digger` per target.
The point is coverage, not economy: each one can dig its own target to the bottom in parallel, and you get back addressed quotes instead of having to skim everything yourself and miss things.
Git and transcripts are independent targets, so when the question needs both, run the two in parallel.

That agent already carries the output contract above — quote rather than conclude, keep found and inferred apart, give an absence its search scope, and treat finding nothing as an acceptable result, which is the line that keeps it from assembling a plausible motivation out of whatever it did find.
So give it the three things it cannot know: the target, the question in the words it was asked in, and the steps of the procedure that apply to that target.
The transcript one especially: the `claude-nu` commands above, both languages of the search terms, and the warning that roughly seven in eight `type:"user"` rows are tool results.
An agent left to grep the JSONL raw will quote `cat` output back at you in the user's voice.

Do not fall back to a plain subagent and paste the contract into the prompt.
That is what this used to be, and the contract came out a little different every time; the one left to write a summary hands back a smooth paragraph with no SHAs, and then nothing in the chain is checkable.

## Traps

### In git

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
- **`git log -S` misses a line that was reworded on arrival.**
  Try a shorter fragment before concluding the sentence has no birth commit.
- **The anchor commit is where the shape arrived, not always where it was decided.**
  In one worked example the code was three months older than the commit that unified it.
  In another, the mechanism first appeared a week earlier — inside an agent-written todo note, which is not the user's voice either.

### In the transcripts

- **The failure to fear here is the false negative.**
  A false positive gets argued down the moment the user reads the quote; "you never asked for this" is believed, and it is wrong every time the search was aimed at the wrong slug or its output was elided.
  Before writing that sentence, check that the artifact-to-session step ran and that the rows were printed rather than rendered.
- **A raw grep of the JSONL cannot answer this question.**
  Roughly seven in eight `type:"user"` rows are tool results, and their text is command output and file contents — the topic's exact vocabulary, in nobody's voice.
  A grep that hits one of those shows the user saying what `cat` printed.
  This is why the commands above exist.
- **`<task-notification>` blocks still come back as user messages.**
  The harness files a finished background agent's own summary under `type:"user"`, and `claude-nu` does not yet drop it (389 such rows across the corpus).
  An agent's report in the user's slot is precisely the confusion this skill exists to undo — check the shape of any hit that reads like a status update.
- **A session log records what was said, not what was on screen.**
  The user may have skimmed a long summary and moved on.
  That is a real possibility to name, not a gap to fill with a guess.
