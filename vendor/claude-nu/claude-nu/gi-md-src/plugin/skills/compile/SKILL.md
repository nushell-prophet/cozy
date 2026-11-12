---
name: compile
description: Compile a canvas or a spec — read it and its sibling files as one program, bring them to their current state, mark with CriticMarkup what conflicts with what, and say what is still open. Use when the user says "скомпилируй", "скомпилируй канвас", "скомпилируй спек", "compile the canvas", "compile the spec", or asks whether the canvas is ready before the work starts. It does not do the open work; `gi:git-intent` does.
argument-hint: [canvas path, scope or instructions]
allowed-tools: Bash(git *), Bash(rg *), Read, Edit, Write, Grep, Glob, Agent
---

The canvas is a program of a new kind,
and the canvas with its sibling files is the source.
Compile reads the source as one unit,
as a compiler reads every file of a crate:
it brings the files to one current state,
checks that the parts agree,
and reports what is still open.
The result is the canvas in its current state,
plus the diagnostics:
the conflicts as CriticMarkup at their spots,
the open items in one `AA:` entry under the H1,
or in a sibling that the entry names.

Compile does not execute.
An open `!!` is work for `gi:git-intent`;
compile only lists it.
The user asks for a compile to learn whether the canvas is ready ("скомпилируй канвас, все готово?"),
not to start the work.

## The source

- The canvas: `$ARGUMENTS` when it names a path, else `$GI_CANVAS`.
  With neither, stop: the canvas is unknown.
- Its siblings: each path in `related_files`, and each `<canvas stem>-*.md` beside the canvas,
  except `<canvas stem>-open.md`:
  that file is the output of *Open items*,
  which the run rewrites and does not read as source.
- The history: `git log -p -- <canvas> <siblings>`, for the decisions the files no longer show.

Read all of them in full before the first pass.

## Clean tree

Run `git status --porcelain -- <canvas> <siblings>`.
An uncommitted change of `session:` alone is the stamp that `gi open` writes:
commit it first, on its own, as the Canvas style says.
Any other uncommitted line is his draft:
stop, and ask him in `next` to commit it.
Compile rewrites lines,
so a draft would go into its commits,
and every cut must stay recoverable from `git log -p`.

## Pass 1 — links

A link resolves or it does not,
so check it with a command, not by reading:

- a fragment link `path:/fragment/` — `rg --count --fixed-strings -- '<fragment>' <path>` prints `1`;
- a `related_files` entry — the file exists;
- a `<canvas stem>-*.md` sibling — the canvas names it;
- a Change-Id — `git log --all --grep='^Change-Id: <id>'` prints a commit;
- a sha — `git rev-parse --verify --quiet '<sha>^{commit}'` prints it.

A path resolves against the directory of the file that holds it,
as `gf` in Helix does.
A link that does not resolve is a finding for pass 3.

## Pass 2 — current state

Fold what is settled,
in the canvas and in the siblings alike:

- A thread whose point he settled goes to its decision, as the Canvas style says under *Channels*.
  A point is settled when his answer stands under it, or his `%%` states the decision.
- A stale fact in an agent line — a count, a state, a path — gets its current value.
  A count that will go stale again becomes the command that produces it.
- A place that an agent line names with no link — a step, a section — gets its fragment link,
  checked as in pass 1.

What is open stays:
an `!!`,
an unanswered `??`,
a `???` or `!!!` that waits for him,
a CriticMarkup span he has not applied.
Commit this pass alone, `canvas: compile — fold settled threads`.

## Pass 3 — conflicts

The agent of the session knows what the user meant,
so it fills a gap without seeing it.
So give this pass to one subagent with no context from the conversation.
Its prompt holds only the paths of the canvas and its siblings, and this list:

- two lines that cannot both be true, in one file or across files;
- one word in two meanings, or two words for one thing;
- a claim about a file that the file does not match;
- a decision that rests on a question still open;
- a term that no line defines;
- a step the plan needs that no line says.

Tell it to answer from the files alone:
each finding quotes its line and gives its fragment link,
and a finding with no line to point at is not reported.
Its findings are claims, not facts.
Check each one against the files,
and drop the ones the files refute.

Mark each finding that stands, at its spot:

- In his line, a substitution with no comment: `{~~his claim~>the correct claim~~}`.
  He applies it himself, as the Canvas style says.
  The reason goes in the commit body, one line per substitution;
  he asks for more when he needs it.
- When the files do not say which side is right, a question on his words that links the other side: `{==his words==}{>>conflicts with <fragment link><<}`.
- In an agent line — an `AA:` entry, or a sibling the agent wrote, as `git blame` shows — a direct fix of the line.
  A place that the fix names carries its fragment link.

Commit this pass alone, `canvas: compile — mark conflicts`.
A pass that found nothing makes no commit.

## Open items

List what is still open in one `AA:` entry under the H1 of the canvas:
compile is about the whole canvas, not about one point of it.
The entry is one line, `AA: compile: <N> open`,
and under it each open item is one list item on one line:
its fragment link,
what waits,
and who acts — he, or the agent after his `go`.
The gi review of a turn (`gi open --review`) counts only the lines of an entry that are not list items,
so the entry stays within the cap of the Canvas style however long the list is;
it flags a list item with a code span and no fragment link.
Past three items, the list goes to the sibling `<canvas stem>-open.md`, which holds only these one-line items,
the entry line names it (`AA: compile: <N> open, in <canvas stem>-open.md`),
and `related_files` in the frontmatter names it too,
as the Canvas style says for a large answer.
A compile that finds the entry of an earlier compile rewrites it in place,
and moves the list between the entry and the sibling as its length says.
When the list is back in the entry, or nothing is open,
delete the sibling with `git rm` and its line in `related_files`;
with nothing open, the entry goes too.
Count the items in the entry or its sibling,
never from the report of the subagent.
Commit this alone, `canvas: compile — open items`.
A list that did not change makes no commit.

## Replies

Reply in the chat in this shape.
The user reads it as he reads the output of a shell command:
he looks for the same element in the same place every time.

- The reply is a column of rows and nothing else:
  no paragraph before it, no question after it, no blank line between rows.
- Each row is one Markdown line: the emoji of a shared label, the label in backticks, `│`, then one line of value, as `` 🟢 `go` │ <what go does> ``.
  The shared labels and their emoji: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of this skill alone has none.
  The skeletons below show the rows as plain text; the reply adds the emoji, the backticks and the `│`.
- The labels and the fixed values (`yes`, `no`, `nothing`) are in English;
  the free text of a value is in the language of his request.
- A row prints only when it has something to say: a pass that found nothing gets no row.
- At most four rows and 480 bytes:
  in a canvas session the gi Stop hook passes no more, unless he ran the skill as a slash command,
  and the shape is the same either way.
  The open items are in the `AA:` entry of *Open items* or its sibling, so the rows fit.

```text
ready     yes | no · <Change-Id> fold · <Change-Id> conflicts · <Change-Id> open items
open      <N> items · <fragment link of the AA: entry>
go        <the open work that go starts>
```

The first row says whether the canvas is ready, and it always prints;
a pass that made no commit adds no Change-Id.
`open` prints when an item is open:
it counts the items in the `AA:` entry or its sibling, and gives the fragment link of the entry.
The last row is `go` when you can do open work after his go,
`next <the exact action for him>` when only he can act,
or `next nothing` when the canvas is ready.

A stop — an unknown canvas, a draft of his in *Clean tree* — has this shape:

```text
stop      <the section>: <the cause in one line>
state     nothing changed | the session: stamp committed
next      <the exact action for him>
```

## Related

- `/gi:git-intent` — does the open work that compile lists.
- `/gi:git-intent-readback` — reads back the answers of the last N commits and stops; compile reads the whole canvas and its siblings.
- `/gi:canvas-tidy` — the deeper cut of one document, his prose included; compile folds only settled threads and stale agent facts.
