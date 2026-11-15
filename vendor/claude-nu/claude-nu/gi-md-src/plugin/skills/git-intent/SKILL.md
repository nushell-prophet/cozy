---
name: git-intent
description: Process commits as instructions — execute the user's inline markers (`!!`, `??`, `%%`) and `gi: <text>` commit-subject instructions, then propagate the resulting choices through the codebase. Use this whenever the user has put the instructions in the repo rather than in the chat: "git-intent", "process commits", "apply intent", "выполни коммиты", "разбери маркеры", a pasted `git log` carrying markers or `gi:` subjects, or a plain "I committed my edits, go" after they edited files themselves. Reach for it even when they never name the skill — an edit the user committed is a decision to honor and propagate, not a diff to read past.
argument-hint: <N>
allowed-tools: Bash(git *), Read, Edit, Write, Grep, Glob
---

Git is the instruction interface between human and agent.
The human delivers intent through inline markers in any file type, commit messages, direct edits, and the `#` comment on a git command he pastes.
The agent reads the diff, executes the instructions, and commits the results.
Every change is reviewable in git history.

## Why

Chat is awkward for two things:
instructions targeting many scattered points in a file (the user can't easily attach a comment at each), and reviewing large agent responses (no fast way to give feedback per section).
Move both into a file and let git carry the loop
— the user sees a diff, can revert individual hunks, and can leave `!!` markers right where a change should land.
The agent should commit promptly so each step is a stable rollback point.
If the agent's reply would be large,
write it to a sibling file next to the document (per *Markers* below), not the chat.

It's a REPL cycle: user instructs, sees the diff, judges, instructs again.
Git adds what a plain REPL lacks — per-step rollback and a history you can return to.
That history is the workflow's main artifact:
an auditable record of decisions, their motivations, and the paths that were considered and rejected.
The iterative history is preserved on archival (see `/gi:git-intent-squash-archive`)
precisely so the rejected paths aren't lost.

## Instruction channels

Four channels carry user intent:

- **User markers** in any file — pinpoint instructions next to the target:
  `!!` do this, `??` a question, `%%` a remark.
- **Commit message** — explanation/context for the committed edit, optionally prefixed `gi:` (git intent).
  If the message reads as an imperative ("rename foo to bar", "expand this section"),
  treat it as actionable.
- **Direct edit** — the user's edit itself, with no marker and no commit-message text, is also an instruction.
  The edit *is* the decision; the agent's job is to honor and propagate it.
  A commit whose author reads `<his name> (verbatim via Claude)`, with `+claude@` in the address, is not his edit:
  it is his chat prompt, which an agent carried into the file to answer it there.
  Its added lines are his prompt, verbatim;
  the commit is the agent's,
  and the point stays open until an `AA:` under it answers it.
- **The `#` comment on a pasted git command** — the user hands you a commit or a diff as `git log -p -1 # propagate`, `git show -p X # is all answered?`, `git diff # is it sound?`.
  It combines with the markers:
  the instructions sit in the canvas,
  and the comment adds the last one or two at the moment he runs the command,
  so you read the paste and the comment together.
  A paste with no comment asks for the default pipeline below.

## Commit patterns

A commit message
— with or without the `gi:` prefix —
defaults to **explanation** of what the user already committed;
the edit itself is the decision,
and the agent honors and propagates it without re-executing the text.
If the message reads as an **imperative**,
treat it as actionable and apply it to the commit's files.
When the role is unclear, ask.
The pipeline is uniform:
apply any user markers, apply any imperative commit message, propagate the resulting decision to stale references elsewhere.
Empty steps are no-ops.

The subject prefix is `gi:` (quiet — the commit *is* the unit, no surrounding noise to fight)
while inline markers are `!!` / `??` / `%%` (loud — they must stand out against surrounding code).

## Markers

- Native single-line comment of the file, prefixed with the marker.
  Examples: `# !! ...` (Python/Nu/Shell/YAML), `// ?? ...` (JS/Rust/Go/C), `-- %% ...` (SQL), `/* !! ... */` (CSS), `<!-- !! ... -->` (HTML/Markdown).
  In Markdown prose the marker starts its own line, so `rg '^(!!|\?\?|%%)'` lists every open one.
- Place on the line above or beside the target code
- **Marker length says who wrote it: two characters — the user, you act; three — you, the user acts.**
  So `!!` do it, `??` answer it, `%%` a remark to take into account
  — "nothing to change" is a valid outcome.
  His marker is a hint,
  and the mark that ends his point outranks it:
  a `!!` point that ends in `?` is a question,
  and an order under `??` or `%%` is still an order.
  Leave your own `!!!` / `???` / `%%%` standing until the user clears them, or until his `go` accepts the default a `???` carries;
  then fold it in the same commit as the work.
- Removed after processing
  — in code, fold the result into the surrounding text and remove the whole comment, including any closing delimiters (`*/`, `-->`), not just the marker token.
  In a document the user writes in — a canvas, a note of his — the text is his:
  reply under the marker as one `AA:` entry
  — your summary, prefixed so a reader and `git blame` both see whose line it is —
  and once the point is settled, reduce the thread to its decision in a commit of its own:
  delete the marker lines and leave the entry standing under his prose, which stays as written.
  A large answer goes in a sibling file, `<doc stem>-<mnemonic>.md`, and the `AA:` entry names it.
  When answering a `??` needs the user back, leave a `???` in its place instead.
- Comments with no marker are persistent context — leave alone

## Reading user edits

- **User's committed edit > prior markers** — if the user edited code a marker targets, the edit *is* the decision;
  remove the marker without re-applying it
- **Clean up broken surroundings** — if the user's edit left a dangling sentence, stale list numbering, or broken syntax, fix it.
  Never re-add content the user removed
- **Surface contradictions** — when markers/edits conflict or scope is unclear,
  name the conflict in the commit body if you can resolve it, ask the user if you can't
- **The user's prose is his** — in a document he writes in, rewrite his lines only when he asks for it,
  to fix grammar, or to sync a copy of a fact his newer edit changed,
  as the Canvas style says.
  The grammar fix marks the changed English words in *italics*,
  fixes Russian and punctuation unmarked,
  leaves a lowercase sentence start as it is,
  and breaks a new line of his over 100 characters into semantic-feed lines.
  The sync is a commit of its own;
  when his edit looks like a mistake, or shows that his model and the canvas are far apart, a `???` asks first.
  A line of his that is wrong against the code or the facts gets a CriticMarkup fix or a `???`, not a silent rewrite

## Replies

The answers live in the document and in git;
the chat gets only these rows, which point at them.
The user reads them as he reads the output of a shell command:
he looks for the same element in the same place every time.

- The reply is a column of rows and nothing else:
  no paragraph before it, no question after it, no blank line between rows.
- Each row is one Markdown line:
  the emoji of a shared label, the label in backticks, `│`, then one line of value, as `` 🟢 `go` │ <what go does> ``.
  The shared labels and their emoji: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`;
  a label of this skill alone has none.
  The skeleton below shows the rows as plain text;
  the reply adds the emoji, the backticks and the `│`.
- The labels and the fixed values (`nothing to do`, `nothing`) are in English;
  the free text of a value is in the language of the text it answers.
- A row prints only when it has something to say:
  a check that found nothing gets no row.
- At most four rows and 480 bytes:
  in a canvas session the gi Stop hook passes no more, unless he ran the skill as a slash command,
  and the shape is the same either way.
  When the rows do not fit, fold the `open` rows into one that counts the markers of the document, his and yours,
  and names the command that lists them, `rg --line-number '^\s*(- )?(\?\?\??|!!!?)' <doc>`;
  the list also holds a marker already answered under it, until its thread is collapsed.
- Rows of one label go in order of what they cost him, the most expensive first.
- A choice is a `???` with its default at its spot in the document, not a row:
  his `go` accepts every default.

```text
done      <the file of the answer, or a fragment link to it> · <Change-Id> · <Change-Id> | nothing to do
open      <fragment link> · <what waits> · <you | me after your go>
left      <path> uncommitted · your draft | my answer to your pasted diff
go        <what go does>; each open ??? takes its default
```

`done` always prints, and names each commit by its short `Change-Id` (by sha only where the repo stamps none).
`open` is a `???` or `!!!` that this run placed, or a marker of his that it did not process.
The last row is `go` when the run left work that waits for his go, else `next <the exact action for him> | nothing`.
An action only he can take, such as a command you did not run because it pushes to a remote, is that `next` row, with the command.

## Procedure

1. **Tree check** — run `git status --porcelain`.
   Uncommitted lines are the user's draft, lighter than what he commits:
   read them when he points at them (a pasted `git diff`, a `<selected-text>`),
   never write over them,
   and never sweep them into a commit of yours.
   A pasted `git diff` is answered in kind:
   write the answer, leave it uncommitted;
   commit only when he asks.
   A dirty tree stops nothing else
   — the `left` row of *Replies* says what you left uncommitted and whose it is.

2. **Get the diff** — run `git log -p -N --reverse` where `N = $ARGUMENTS`,
   or `1` when `$ARGUMENTS` is empty or is not a positive integer.
   If the patch is very large (>500 lines),
   prefer `git log -N --stat` plus targeted `git show` per file to avoid filling context.

3. **Read files in scope** in full.
   Skip files you've already read or edited in this session, and skip binary files.

4. **For each commit, run the pipeline:**
   - **Apply markers** — for each user marker (`!!`, `??`, `%%`) added in the diff,
     read the text, act on it and remove the marker per *Markers* above (the whole comment in code and in files you wrote; in his document the marker line, leaving the `AA:` entry).
   - **Apply imperative commit message** — if the message (with or without `gi:`) reads as a command,
     apply it to the commit's files.
     If it reads as explanation, skip — the edit itself is the decision.
   - **Propagate the decision** — scan each file in the commit scope for references that contradict the resulting state (stale branches, removed APIs, old behavior descriptions, obsolete rationale).
     If the decision names a symbol, path, API, or config key, also `grep` the broader repo.
     Clean up broken surroundings left by user edits, per *Reading user edits* above.

   Empty markers, empty global instruction, and no propagation needed are all valid no-ops
   — the pipeline runs unconditionally.

5. **Commit each logical change** — one commit per decision.
   When scope is unclear, name your interpretation in the commit body if you can resolve it;
   ask the user if you can't (per *Reading user edits*).
   Body is mandatory and follows this template:

   ```
   <subject>

   Decision: <one sentence>
   Why: <non-obvious reasoning, 1–2 sentences>
   Rejected: <alternative considered and dropped, with the reason — omit if none>
   Propagated: <other places touched — omit this line if none>
   ```

   - **Record rejected paths.**
     If the user considered an alternative and dropped it (in chat, via a `!!` marker that was later removed, or by reverting a prior hunk),
     capture it as `Rejected: <alt> — <why>`.
     The dead end is part of the decision graph and would otherwise be lost.
   - **Don't list conflicts you looked for and didn't find.**
     "Nothing else changed" is noise; absence is the default.
   - **Don't restate the diff.**
     If the body is longer than the diff, the body is wrong unless the reasoning is genuinely complex.
   - **Name a commit by its short `Change-Id`**
     — the first 8 characters of the trailer —
     wherever a body, an `AA:` entry, or a `Rejected:` line cites one;
     by sha only where the repo stamps none.
     A sha changes under rebase, which these branches see constantly;
     the id travels with the commit.
   - **Skip binary files** in the diff.
   - A decision visible in git history is binding — do not override without explicit instruction.

   If there is genuinely nothing to do (no markers, no propagation, no cleanup),
   reply with the rows `done nothing to do` and `next nothing`,
   and exit without creating an empty commit.

6. **Reply** in the shape of *Replies*.

## Related

- `/gi:git-intent-readback` — when the commits to process are the user's answers to your questions, run this first:
  restate them and stop, instead of executing a reading nobody confirmed
- `/gi:canvas-tidy` — when the document has filled up with spent markers and superseded deliberation,
  cut it back to current state before the next loop
- `/gi:compile` — before a loop on a canvas that grew over many turns:
  fold it with its siblings to the current state, mark the conflicts, and list what is open
- `/gi:git-intent-squash-archive` — when done iterating, squash the branch into one clean commit preserved as a git tag
