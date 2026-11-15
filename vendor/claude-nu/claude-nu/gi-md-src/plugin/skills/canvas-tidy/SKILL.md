---
name: canvas-tidy
description: Reduce a canvas or working document to its current-state meaning, letting spent markers, resolved readbacks, answer ladders, and dead rejected paths fall into git history (every cut recoverable via `git log -p -- <doc>`), and reshape a chat imported as turns into points with their answers. Use this whenever a working document has grown heavy with process material and the user wants it readable again, and right after a chat is imported as a canvas — "tidy", "distill", "причеши канвас", "отпроцесси канвас", "reduce the canvas", "почисти канвас", "сократи документ", "убери отработанное", "this doc got bloated", "trim it down", "clean up the resolved markers" — even when they never name the skill. Prefer it over trimming the file by hand: hand-deleting loses the reasoning, this keeps it recoverable.
argument-hint: [scope or instructions]
allowed-tools: Bash(git *), Read, Edit, Write, Grep, Glob
---

Tidy compresses the *document*, not the history.
`gi:git-intent` writes the loop;
`gi:git-intent-squash-archive` collapses the commit stream;
neither decides what text the canvas should still carry.
Over a session the canvas accumulates rejected-path sections, resolved markers, and superseded caveats
— the human wants to read current state, not the whole working record.
Tidy removes that accumulation *into history*:
the doc converges to its meaning, every cut stays recoverable.

This is a forward commit, not a rewrite — lighter than squash-archive: no tag, no reset.
The pre-tidy version is `git show HEAD^:<doc>`.
Run it whenever the canvas has drifted from lean, not only at finalization.

## Invariant

**Remove only what history already holds.**
Every cut must be recoverable from `git log -p -- <doc>`,
so the precondition is a clean tree
— all work committed —
or the parent commit won't hold the full pre-tidy version and the removed content is gone, not archived.
Run `git status --porcelain`;
if non-empty, stop and ask the user to commit first (same guard as the sibling skills).
Scope of the guarantee: `git log -p -- <doc>` on the working branch;
after `gi:git-intent-squash-archive` the recovery path becomes the `archive/<branch>` tag.

## What to cut, what to keep — the judgment

This is the skill; the mechanics below are secondary.
Tidy is **not** "delete every rejected path."
A rejected section can be *dead* (its reasoning is spent) or *protective* (it stands in the doc to stop a future agent re-proposing the bad idea).
Cutting protective text to history only helps a reader who checks `git log` before proposing
— real discipline, not a guarantee.
So weigh each candidate rather than sweeping.

**Cut — dead process material:**

- Resolved `!!` / `!!!`, `??` / `???`, `%%` / `%%%` markers and the scaffolding around them.
- A spent `AA:` entry
  — one that reported a change or answered a point the user has since read and moved past.
  The git-intent loop leaves it standing when the marker closes so the answer is visible under his line;
  once read, it is process material like a `## Readback` section.
- A `## Readback` section (from `/gi:git-intent-readback`) once the work it confirmed has started
  — its job ended at the confirmation.
- Working-list numbering gaps and half-formed notes the final state superseded.
- Deliberation a later decision made moot — the settled outcome stays, the weighing goes.
- A rejected path whose only value was recording *that* it was rejected
  — the deletion commit body carries that.

**Keep — live constraints:**

- `## Open decisions` and anything still unresolved: live, not dead.
- An `AA:` entry that still carries meaning:
  the one naming the sibling file with the long answer (cut it and the file loses its only link from the canvas),
  or a summary that is the current state of the point.
- Protective why-nots
  — a rejected path documented to prevent re-litigation —
  stay inline unless the user says otherwise.
  A long one may be cut down to one line plus a pointer at the commit that holds the reasoning
  — the why-not stays visible, the weighing goes to history.
  The pointer is the commit's short `Change-Id` (the first 8 characters) where it carries one, by sha only where the repo stamps none:
  `git log --all --grep='^Change-Id: <id>'` still resolves it through the `archive/<branch>` tag after squash-archive,
  while a working-branch sha dies at the first rebase.
- Current-state contracts and any caveat that still binds behavior.

**Reshape — his text, where it reads as a chat:**

He thinks as he writes,
so his prompts arrive in that order:
a decision comes last,
a later and wider one cancels an earlier one,
one line answers many points (`1. yes 2. ok 3. explain`).
A canvas imported from a chat holds exactly that, as `## User` / `## Assistant` turns.
The canvas is a screen of the current state, not a log of turns,
so tidy rewrites his text too:

- Each answer goes under the point it answers; an emptied turn header goes.
- A ladder of question, answer and follow-up whose answer he accepted becomes the settled answer.
- Decisions go first in their list; a decision a later one cancelled goes.
- His prompts are paraphrased closely, in his language:
  his words and his claims stay,
  only the order and the split change.

This is the one pass that paraphrases his prose,
and the parent commit keeps his original words.
Where a paraphrase would change what he claims,
keep his words and place a `???`.

When a cut is judgment-heavy, do less:
leaving a live constraint in costs a few lines;
cutting one into archaeology costs a re-litigated decision.
When you genuinely can't tell dead from protective, keep it and place a `???` asking the user.

## User instructions

`$ARGUMENTS` steers the operation and overrides the default taxonomy.
It may set scope ("only the transport section"), aggressiveness ("keep all why-nots", "cut hard"), or name specific content to keep or drop.
`!!` markers in the doc do the same in place.
With no instruction, apply the taxonomy above conservatively.

## Replies

The user reads this reply as he reads the output of a shell command:
he looks for the same element in the same place every time.
The substance is in the canvas and in git;
the chat gets only these rows, which point at it.

- The reply is a column of rows and nothing else:
  no paragraph before it, no question after it, no blank line between rows.
- Each row is one Markdown line:
  the emoji of a shared label, the label in backticks, `│`, then one line of value, as `` 🟢 `go` │ <what go does> ``.
  The shared labels and their emoji: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`;
  a label of this skill alone has none.
  The skeletons below show the rows as plain text;
  the reply adds the emoji, the backticks and the `│`.
- The labels and the fixed values (`nothing to cut`, `nothing changed`, `nothing`) are in English;
  the free text of a value is in the language of the session.
- A row prints only when it has something to say:
  a check that found nothing gets no row,
  and what you kept gets none.
- At most four rows and 480 bytes:
  in a canvas session the gi Stop hook passes no more, unless he ran the skill as a slash command,
  and the shape is the same either way.
  A value is a path or a fragment link, a Change-Id and a few words;
  the reasons go to the commit body.
  When the rows do not fit, fold the `open` rows into one that counts the `???` and `!!!` of the document
  and names the command that lists them, `rg --line-number '^\s*(- )?(\?\?\?|!!!)' <doc>`.
- Rows of one label go in order of what they cost him, the most expensive first.
- A choice is a `???` with its default at its spot in the document, not a row:
  his `go` accepts every default.
- When another skill runs this one, print no rows: the caller reports.

A run has this shape:

```text
done      <doc> · <Change-Id> · <sibling> · <Change-Id> | nothing to cut · <doc>
warn      not requested: <a choice you made to fill a gap, such as a sibling tidied too>
open      <fragment link> · <what waits> · <you | me after your go>
go        <the open work that go starts>; each open ??? takes its default
next      <the exact action for him> | nothing
```

`done` always prints.
The last row is `go` when an `open` row waits for his go, else `next`.
`done` names each document the run committed, with its Change-Id.
`open` is a `???` this run placed, or a `!!!` that already waits for him.

A stop
— a dirty tree in step 1, an unknown document in step 2 —
has this shape:

```text
stop      step <n>: <the cause in one line>
state     nothing changed
next      <the exact action for him>
```

## Procedure

1. **Clean-tree check** — `git status --porcelain`.
   Non-empty → stop, name the files in `stop`, and ask in `next` to commit or stash:
   this pass rewrites the whole file,
   so his uncommitted lines would be lost in it.
   (The sibling skills accept a dirty tree; this one cannot.)
2. **Read the canvas in full** — a session launched by `gi open` was told its canvas path in its own instructions;
   if you were given no such path, stop, and ask in `next` which document.
3. **Classify** — mark each section cut/keep per the taxonomy and any `$ARGUMENTS` / `!!` instructions.
   Anything genuinely ambiguous between dead and protective: keep it, add a `???`.
4. **Edit** — remove the cut material;
   repair what the cuts leave dangling (broken sentences, stale cross-references, list numbering).
   Never leave the doc mid-broken.
5. **Commit** — the canvas change as its own commit.
   Body is thin:
   the diff *is* the archive,
   so name what was tidied in one line, not what each removed section said.
6. **Reply** in the shape of *Replies*.

## Related

- `/gi:git-intent` — the write-loop that produced the material being tidied.
- `/gi:git-intent-squash-archive` — finalization:
  collapse the branch (tidy commits included) into one clean commit for `main`, full history preserved in a tag.
