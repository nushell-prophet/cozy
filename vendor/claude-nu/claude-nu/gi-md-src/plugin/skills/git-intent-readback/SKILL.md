---
name: git-intent-readback
description: Before acting on a block of answers the user just committed, restate each one in your own words, name what is ambiguous, unanswered, or contradictory, and stop. Use when the user says "readback", "check my answers", "проверь мои ответы", "не бросайся выполнять", "я ответил на вопросы", or has just committed answers to questions you asked.
argument-hint: [N commits, or scope]
allowed-tools: Bash(git *), Read, Edit, Grep, Glob
---

You asked, the user answered in the document and committed.
The default reflex is to start working at once — and that reflex is the failure.
An answer can skip a question, carry two readings where you silently picked one, or contradict something already decided.
Work built on a wrong reading is expensive to undo, and the user learns about it only after the code exists.

The fix is a **readback** (an aviation term: the pilot repeats the clearance back before flying it).
You write what you understood — in your own words — into the document; the user reads the diff and repairs a wrong reading with one edit.
Copying their words back proves nothing; only a paraphrase can expose a misread.
That is the point of this skill: it catches not the ambiguity you noticed, but the one you didn't.

## The pass

Every question you asked lands in exactly one bucket.
Nothing is dropped silently — a question you forgot you asked is the same failure as an answer you misread.

- **Clear** — one reading only.
  Write that reading back, plus the consequence: what you will *do* because of it.
  The consequence is where the misread usually shows, not the sentence.
- **Ambiguous** — two or more readings.
  Don't pick.
  Enumerate them (A / B), recommend one, and place a `???` at the spot.
  A closed question is far cheaper for the user to answer than an open one.
- **Unanswered** — the user answered four of six.
  Say which two, at the spot they belong.
- **Conflicting** — the answer collides with another answer, with the document, or with a decision already in git history or in the code.
  Name the collision; never reconcile it on your own.
  A decision in git history is named by its commit's short `Change-Id` (the first 8 characters) where it carries one, by sha only where the repo stamps none — the id survives the rebases the sha does not.

Completeness runs both ways.
An answer can open a decision nobody asked about yet, and your plan for the work can need a choice no answer covers.
Walk the work you are about to do and ask what is still undecided — those gaps go in as `???` too.

Judgment: doubt is cheap here and silence is not.
If you hesitate between *clear* and *ambiguous*, it is ambiguous.

## Replies

The readback is in the document; the chat gets only these rows, which point at it.
The user reads them as he reads the output of a shell command: he looks for the same element in the same place every time.

- The reply is a column of rows and nothing else: no paragraph before it, no question after it, no blank line between rows.
- Each row is one Markdown line: the emoji of a shared label, the label in backticks, `│`, then one line of value, as `` 🟢 `go` │ <what go does> ``.
  The shared labels and their emoji: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of this skill alone has none.
  The skeleton below shows the rows as plain text; the reply adds the emoji, the backticks and the `│`.
- The labels, the bucket names and the fixed values are in English; the free text of a value is in the language of his answers.
- A row prints only when it has something to say, and a bucket with zero answers is left out of the count.
- At most four rows and 480 bytes: in a canvas session the gi Stop hook passes no more, unless he ran the skill as a slash command, and the shape is the same either way.
  When the rows do not fit, shorten the path in `left` to the file name first.
- Each choice is a `???` with its default at its spot, not a row: his `go` accepts every default.

```text
done      readback in <doc> · <N> clear · <N> ambiguous · <N> unanswered · <N> conflicting · <N> gaps · <Change-Id>
held      <N> more wait for the next round
left      <doc> uncommitted · the readback of your uncommitted answers
go        do the work as read back (gi:git-intent); each open ??? takes its default
```

Outside a stop, `done` and `go` always print.
`done` counts the four buckets of *The pass*, then the gaps that its completeness check found, in that order.
`held` prints when the cap of three `???` held some back.
It counts them only: they are written nowhere until the next round.
Outside a stop, `go` always ends the reply: the readback waits for his confirmation, even when nothing is ambiguous.

A stop — no canvas path in step 3 — has this shape:

```text
stop      step 3: no canvas path
state     nothing changed
next      name the document
```

## Procedure

1. **Tree check** — `git status --porcelain`.
   Uncommitted answers are a draft he is still writing: read them back if he pasted them as a `git diff`, and leave your readback uncommitted too; never write over his lines or sweep them into your commit.
   (Same rule as `/gi:git-intent`; `/gi:canvas-tidy` alone still requires a clean tree, because it rewrites the whole file.)
2. **Get the answers** — `git log -p -N -- <doc>` with `N = $ARGUMENTS` (default `1`); `$ARGUMENTS` may instead name a scope or file.
   `git show HEAD~N:<doc>` gives the pre-answer version — that is where your original questions still stand.
   A pasted `git diff` is the same input, uncommitted: the answers are in the paste, and the pre-answer version is `HEAD:<doc>`.
3. **Read the canvas in full** — a session launched by `gi open` was told its canvas path in its own instructions; if you were given no such path, stop and ask which document, in the stop shape of *Replies*.
4. **Sort and write.**
   Ambiguous, unanswered, and conflicting go in as `???` next to the relevant spot, per the Canvas protocol.
   At most three `???` per pass, the ones blocking the most work first; the rest wait for the next round (the Canvas cap).
   Clear ones go into one `## Readback` section — one line each — so the user reviews the whole set as a single diff instead of hunting through the file.
5. **Commit** the document alone.
   Subject names the pass; body stays thin — the diff is the content.
6. **Stop.
   Do not start the work.**
   Reply in the shape of *Replies*.

Stop even when nothing is ambiguous.
Confirmation costs the user one word, and it is the only thing standing between a silent misread and a day of wrong work.

## After

The user edits, answers the `???`, commits — then `/gi:git-intent` executes.
The `## Readback` section is spent process material once the work starts: `/gi:canvas-tidy` cuts it into history.

## Related

- `/gi:git-intent` — the execute loop this pass deliberately delays.
- `/gi:canvas-tidy` — removes the spent readback section afterwards.
- `/gi:compile` — the same check over the whole canvas and its siblings, not only over the answers of the last commits.
