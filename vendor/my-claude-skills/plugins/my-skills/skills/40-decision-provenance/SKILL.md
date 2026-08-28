---
name: 40-decision-provenance
description: >
  Reconstruct the circumstances a design decision was actually made in — what
  question was on the table, what the answer covered, and what got written down
  afterwards — from git history and the Claude Code session transcripts in
  ~/.claude/projects. Use this skill when the user asks "did I ask for this",
  "who decided this", "я это просил", "откуда эта конвенция", "почему у нас так
  сделано", "restore the context of this decision", or before obeying a comment
  that states a rule nothing tests. Also use when a convention keeps being
  treated as settled and nobody can say where it came from.
version: 0.1.0
---

An artifact records WHAT was decided.
It never records the circumstances.
A comment an agent wrote to explain its own choice reads exactly like a comment written from the user's instruction, and once it is in the tree every later agent treats it as law.
This skill recovers the situation the decision was made in, so it can be looked at again with the context intact.

**This is not a hunt for who is at fault.**
An agent deciding on its own is normal and necessary — at the volume this work runs at, an agent that referred every choice upward would not finish anything.
And a decision the user did make can still be worth re-opening: he may have wanted something else, may have read a different question than the one asked, or may have wanted exactly this for a reason that has since expired.
Restoring the circumstances is the whole deliverable.
The verdict is a by-product, and it is never a charge.

## What you are reconstructing

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

## The two sources

**git** says when and what, and sometimes why — this project mandates the user's reasoning in commit bodies.
**`~/.claude/projects`** says what was actually asked and answered.
Neither alone can tell situation 1 from situation 4: a commit body written by an agent states a rationale in the same voice whether the user supplied it or the agent invented it.

### Anchor on the artifact first

Find the commit that introduced the sentence you are standing on — the comment, the README line, the flag:

```
git log --all -S '<verbatim fragment of the line>' --oneline
git show -s --format='%h %ad%n%B' <sha>
```

`-S` on a distinctive fragment usually returns exactly one commit.
That date is the key to everything below.
Read the body and the diff before going anywhere else; if the wording was reworded later, `-S` on a fragment that survived, or `-G` with a loose regex.

For anything deeper in git — what was tried and dropped, what changed together, archived branch history — use the `code-archaeology` skill.
This one does not restate it.

### Then the transcripts

`~/.claude/projects/<slug>/` holds one directory per project, slug = the session's working directory with `/` replaced by `-`.
Inside are `.jsonl` session logs.
Do not parse them by hand: `claude-nu` already does, and the two things it gets right are the two that decide this skill's answer — it reads only what someone actually said, and it knows a subagent log holds no human words.

```
use ~/repos/claude-nu/claude-nu/ *
```

The `*` is what makes the commands below bare; without it every one of them is spelled `claude-nu sessions`, `claude-nu messages`.
In an interactive shell they are already loaded, prefixed.

1. **Go from the artifact to the session, not from the repo name to the session.**
   `sessions --all-projects --columns edited_files,first_timestamp,last_timestamp,session_id,cwd | where ($it.edited_files | any {|f| $f =~ '<basename>'})` names the sessions that touched the file; keep the ones alive around the anchor date.
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

## Reading the exchange

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

## Output

Open with the situation in one or two sentences: which of the four, and what the decision rests on today.
Then the reconstruction, oldest first, so the reader watches it happen:

```
<date>  <what happened>
  USER      > verbatim
  ASSISTANT > verbatim
  → what this settled, and what it left open
  in git: <sha> <subject>   in the code now: <file>:<line>
```

Quote, do not summarize — the user is reading his own words, and a paraphrase of them is worthless for the one thing he is doing, which is remembering.
Keep what you read and what you infer visibly apart, and close with the inferences as a short list.

**"No discussion found" is a real answer** — give it the scope you searched, the way `code-archaeology` requires for any absence: the terms, both languages, and the two searches that have to have run, `--all-projects` and `--subagents`.
Without the scope it is not a finding, only a failure to look — and here that failure is not neutral, it convicts an agent of deciding alone.

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

Two targets, independent, so run them in parallel: one on git, one on the transcripts.
Give each the output contract above verbatim, and tell each that its job is to quote with addresses, not to conclude.
Tell the transcript agent explicitly that finding nothing is an acceptable result — otherwise it will assemble a plausible motivation out of whatever it did find, which is the exact failure this skill exists to correct.

## Traps

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
- **The anchor commit is where the shape arrived, not always where it was decided.**
  In the worked example the code was three months older than the commit that unified it.
  In another, the mechanism first appeared a week earlier — inside an agent-written todo note, which is not the user's voice either.
- **`git log -S` misses a line that was reworded on arrival.**
  Try a shorter fragment before concluding the sentence has no birth commit.
