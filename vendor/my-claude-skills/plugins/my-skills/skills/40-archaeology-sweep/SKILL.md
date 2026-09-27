---
name: 40-archaeology-sweep
description: >
  Find and cut prose that explains the code by contrasting it with a design the
  tree no longer holds — comments and markdown written for whoever watched the
  change, and unreadable for whoever arrives after it.
  Use this skill when the user says "archaeology sweep", "find outdated
  explanations", "strip the we-used-to-do-X framing", "these comments only make
  sense if you know the history", "clean the docs for a new reader",
  "почисти комментарии от истории", or after several branches have landed in a
  repo. For one branch about to land, `40-land-branch` step 7c is the gate;
  this is the sweep over a repo as it already stands. Requires subagents.
version: 0.1.0
---

# Archaeology Sweep

The rule is `CLAUDE.md`'s **The reader never saw the previous version**, and that bullet is where it is stated: a comment or a `.md` may not explain the code by naming a state the tree does not hold.
Stated there, it binds the agent writing a change.
This skill is the other half — the reading that finds the lines already written, and the standard for cutting them out.

An agent finishes a change with the old design still in its head, and writes the new one down as a contrast: "a gone proxy no longer forces a rebuild".
Every word of that is true and useful — to the three people who saw the old state.
A reader who meets the code today carries a paragraph about something that is not there, and cannot tell which half of the sentence describes the code in front of them.

Removing it loses nothing, as long as what it carried lives somewhere else — step 5 is where that gets checked.
The commit that made the change carries what moved and why; the tree carries what is, and the constraint that makes it right.
Those are two channels, and this skill only stops one from doing the other's job.

## The defect

One defect, named exactly: **a sentence a reader can only follow by knowing a state the tree does not hold.**

The test is the reader, not the verb.
Past tense is how the defect usually sounds, which is why the scan looks for it — but a past-tense sentence about something still in the tree is not the defect, and a present-tense sentence about something gone is.
"A substring test also accepted a leftover `cozy-caged-old`" names a test anyone can still write today: the reader loses nothing to the tense, so there is nothing here to clean, and swapping in "matches" is not a cut.
"The check used to sit below ensure-egress" names an ordering only git holds: that reader is carrying a paragraph for nothing.

Four lines that look like the defect and are not:

- "A container created before the exit moved to a name carries a fixed address instead." A condition the runtime can still be in — such a container may exist on the user's machine — and the sentence says inside itself how it came about. Cutting "created before" leaves the reader unable to tell which containers are affected.
- "A proxy that started and immediately died still let the agent up." A hypothetical about a stock option; there is no history in it, and "starts and immediately dies would let" is a tense swap, not a cut.
- "Puts a launch line into the REPL prompt instead of spawning it." Spawning is a concept every reader has, not a state of this repo they missed. The sentence answers the question a reader asks first, and it does so without any history — whether this repo once spawned does not enter into it.
- "Before staging, that reported success while leaving the old binary in place; with staging, it would move a copy cut short over a working binary." Two cases of one hazard, both stated in the sentence, both followable. Cutting the first loses information and gains nothing.

The common thread: the reader can follow every one of them cold.
That is the whole test, and it is not "was this ever the code" — `git log -S` answers a different question.

**A scan hit is a place to look, not a thing to fix.**
Most hits are KEEP, and a KEEP is a finished answer rather than a failure to act.
A run that rewrites every hit it was handed has found nothing — it has retyped the repo.

## Not archaeology

Read this before the first grep.
The scans below hit far more innocent prose than guilty prose, and every class here is innocent by *purpose*, not by file extension:

- **A document whose subject is change.** A CHANGELOG, a migration or upgrade guide, release notes, a `design/` decision record. These exist to tell you what moved; the rule does not reach them. In a CHANGELOG the contrast belongs under `Removed` — an `Added` entry still describes the new thing on its own.
- **The user's own working material.** `todo/` notes, `gi-canvas/` and `gi/` canvases. Not yours to rewrite.
- **Captured text.** A test fixture holding a recorded session, an exported transcript, a saved API response. It quotes what someone said, so the words are theirs and the rule does not reach them; editing one also breaks the test that asserts on it.
- **A vendored copy of another repo.** The fix belongs upstream; editing the copy is thrown away at the next vendor run. Skip the whole directory.
- **An external product's old name.** "`sbx`, formerly `docker sandbox`" helps a reader who will meet both names in the wild. That name is outside this tree, so the rule does not apply to it.
- **A live alternative in a `# Not <alternative> because:` line.** The discriminator is whether a newcomer could propose that alternative today. "Not a copy per snapshot because…" is live — someone will suggest exactly that. "Not the flat `global-claude-<stamp>.md` files" is retired, and only a reader who knew them understands the line.
- **A general rule that happens to use the words.** "If the *why* no longer matches the code, fix the prose" describes a condition, not a past.
- **A present-tense contrast between two live options.** "Selected by name rather than by IP", "fails loud rather than silently re-bloating the context". Both sides exist today; this is the most common innocent hit by a wide margin.

**The live-alternative slot is not somewhere to move the history.**
`CLAUDE.md` says so where it defines the slot: "Not the implementation this change retired: putting that in the slot meant for a design choice is history again, this time wearing the form of a rule."
The bullet above exempts a line already written as a live alternative; it does not license rewriting a retired one into that shape.
What decides is the reader, not the repo's history: "Not `unless-stopped` because it would loop and hide the cause" reads cold, while "`unless-stopped` was here, and it looped" does not — and moving the second into the shape of the first is a rewrite that keeps the history, not a cut.
When the reasoning is worth keeping, step 5 puts it in the commit body, which is the channel that already holds it.

Getting this list wrong is how the sweep wastes a run: it rewrites documents whose whole purpose is the transition, and those commits come straight back out.
Choose the list yourself; do not wait for the user to confirm it.

## Step 1 — Scope

One repo per run.
Tracked files only.
Do not crawl sibling repos, even when a comment points at one.

**The branch is the only stop in this skill.** Run `git branch --show-current` before the first grep.
On `main` or `master`, stop: propose `git switch --create archaeology-sweep` and wait — do not create it yourself.
On any other branch, the run goes through to the commits without asking again — step 5 is why that is safe.

List the exempt paths for this repo from the classes above — typically `CHANGELOG.md`, `design/`, `todo/`, `gi-canvas/`, `gi/`, `vendor/`, any `*/migration.md`.

## Step 2 — The past-state scan

This is the scan that pays, and the default run is this one alone.

```sh
git grep -niE 'used to|no longer|formerly|previously|originally|moved (here|to|from)|restored here' -- . |
  grep -viE '(^|[^a-z])(is|are|was|were|be|been|being) used to' |
  grep -vE '^(vendor/|design/|todo/|gi-canvas/|gi/|CHANGELOG\.md)'
```

The second filter drops the passive "the flag is used to pick the trunk", which carries no sense of time.
The `(^|[^a-z])` in front of it is a word boundary: without it "th**is** used to" matches the passive and every "this used to" line — the plainest shape the defect takes — is dropped before anyone reads it.
The third is the exempt list from step 1 — edit it per repo, never assume these five.

The markers fall into two groups, and both name a *past state*, which is what the rule is about — precise enough to read by hand.
The first four are tense words: the line says outright that something was once otherwise.
The last three are relocation words, and they catch the shape the tense words miss entirely — "moved here from Dockerfile", "Originally set in X, restored here since Y moved to Z".
A relocation line explains where the code sits by naming where it sat, so it fails the rule for the same reason, and it can do so without a single past-tense verb about the code itself.

Calibration, measured on 2026-09-21 on one mixed code-and-docs repo of 248 tracked files: the four tense words returned 21 hits, of which about half named a retired state of its own code; the three relocation words returned 9 more, of which 8 did.
The relocation group is the better-yielding half and the cheaper one to read — a move is nearly always this repo's own history, where a tense word is often a general rule or an outside product's old name.
Seven single-module repos, scanned whole with no exempt list, returned 0 to 6 tense-word hits each and 0 to 2 relocation hits — except one carrying captured session transcripts as test fixtures, which returned 51, half of them inside those fixtures.
A sweep is a sitting's work, not a project; a repo that stores captured text is the exception, and step 1 exempts that directory.

## Step 3 — The wide scan

Only when the user asks for it, and say the ratio before you run it.

```sh
git grep -niE 'instead of|rather than|unlike the|not as a' -- . |
  grep -vE '^(vendor/|design/|todo/|gi-canvas/|gi/|CHANGELOG\.md)'
```

The exempt filter is step 2's third one, and it is what makes the count below reachable: without it the same repo returns 396.
There is no passive filter here — none of these four markers has a tenseless twin the way "used to" does.

On the same mixed repo, with the same exempt list, this returned 96 hits against step 2's 30, and nearly all of them were the present-tense design contrasts named above.
It is worth running when a repo has just been through a large redesign, because that is when a contrast is likeliest to be temporal rather than logical.
It is not worth running as a habit: the reading cost falls on the user, and the yield is low.

Note that both scans hit this file and any document about them.
That is not a bug to filter — a document naming the markers must contain them.

## Step 4 — Fan out

**On the "do not call the Agent tool unless it was asked for" preamble.** Some sessions carry that instruction from the harness, and it names a skill as one of the things that can ask.
This skill asks: its description says it requires subagents.
A hit is judged by reading the file around it and the code it names, which is a file's worth of context per hit, and holding thirty of those in one thread is what the fan-out exists to avoid.

**One agent per file**, not per hit — a file's hits share a context, and one agent reading it once answers all of them.
Batch the small files: an agent handles several files when their hits together stay under a dozen.

Give each agent: the rule as `CLAUDE.md` states it, *The defect* and *Not archaeology* above verbatim — both of them, since the first says what to act on and the second what to leave — and its files with line numbers.
Ask it to read each whole file and to resolve every name the flagged line mentions — `git grep` for the symbol, the path, the command — because the question is always the same one: **does the thing this sentence names exist in the tree?**

**The agent edits flagged lines only.**
Reading the whole file shows it other lines it would cut; those come back as CANDIDATE, with the line number and one sentence, and nothing in the file changes for them.
An agent handed a file and a mandate to cut finds more to cut, and a line no scan named has had no reader but that agent — so the user decides on it from the report, not from a diff.

The agent edits its own files, and the standard it writes to is this: **cut the defect and change nothing else.**
Touch only the words carrying the reference to the gone state; leave the rest of the sentence, its wording and its length alone.
If the paragraph answered a question, the answer stays — only the part the reader cannot resolve goes.
What survives is what the code does now and the constraint that makes it right, and it is usually shorter than what it replaced, because the contrast was the longer half.
The commit body is where that contrast lands, and step 5 puts it there, so the tree needs nothing in its place.

Two things the agent does not do.
It adds no claim the flagged sentence did not already carry — a sweep is not the occasion to explain the code better.
And it does not keep the paragraph at its old length: an edit that swaps the verbs and holds the line count has removed nothing, whatever it says it did.

**The agent runs no git.** It edits and reports; the main session does every commit.
Agents run in parallel and would race each other on `.git/index.lock`, and per-file commits have to come out of one thread anyway to stay one file each.

Each hit comes back as one of:

- **KEEP** — left alone, with the class from *Not archaeology* that covers it, in three words.
- **CUT** — done, with the words it removed, what is left standing, and the reason in one line. That reason becomes the file's commit body.
- **ASSUMED** — it could not settle whether the named thing exists, so it changed nothing. Say what would settle it. Never cut on a name you could not resolve.
- **CANDIDATE** — an unflagged line it would have cut, with the line number and why, left untouched.

## Step 5 — Commit, one file per commit

The agents have already written to the tree.
Walk the changed files and commit each one on its own, even where a single agent handled several.

That granularity is the whole review mechanism.
The user reads the branch as a diff against the trunk and drops the commits they disagree with, so a commit holding two files forces them to take both or neither.
This is why the run needs no approval before it writes: the approval happens after, on a diff, where they see the cut in its file instead of reading a proposed line twice — once in a list and once in the diff.

Each body: the rule, and the agent's one-line reason for that file.
Where a deleted contrast carried real reasoning the repo holds nowhere else — a constraint discovered the hard way, an alternative that failed for a nameable reason — that reasoning goes into the body rather than out of the repo.
It stops being a burden on every future reader and stays one `git log -S` away from whoever needs it.

Commit nothing for an ASSUMED hit.
Nothing was changed there, and a name the agent could not resolve is the one case where a cut takes out something true.

## Step 6 — Report

One message, after the commits exist:

- The commits made, one line each — file and what moved.
- The KEEPs per class as bare `file:line` addresses, not their text. The scan was noisy and the user does not need to re-read innocent prose, but a count with no list behind it cannot be checked.
- Every ASSUMED in full, with what would settle it.
- Every CANDIDATE, one line each; the user says which, if any, a second pass takes.
- The exempt list step 1 used, so a wrong entry is visible as a choice rather than as silence.
- `git diff --shortstat <base>..HEAD`, quoted. Removal shrinks a file, so a run that lands near net zero rewrote where it should have cut, and it failed whatever its commit bodies claim. Say that in the report rather than leaving the user to measure it.

Re-run step 2 afterwards and report what is still there, by class.
A sweep that ends with hits remaining is the normal case — the KEEPs are supposed to remain.

## Related

- `40-land-branch` step 7c — the same rule as a gate, on the lines one branch adds, before it lands. That one gates one branch as it lands; this one sweeps a repo whole, over every line already in it.
- `40-manpage-quality` — what a reference document owes its reader once the archaeology is out of it.
