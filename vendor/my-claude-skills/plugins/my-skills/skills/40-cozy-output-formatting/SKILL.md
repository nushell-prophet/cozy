---
name: 40-cozy-output-formatting
description: >
  The format of what a command skill prints to the user: a column of `│ label │ value`
  rows, the shared labels with their emoji, and the one shape of a stop. A command
  skill names this skill and loads it before its first reply, so that its plan, its
  stops and its report have the same rows in the same place on every run. Also use it
  when a `## Replies` section of a SKILL.md is written or reviewed. Not for an ordinary
  reply, and not for the report of an analysis: this skill formats only the replies of
  a skill that names it.
version: 0.1.0
---

This skill holds the format, and a command skill holds only its own rows.
So a command skill loads this one before its first reply.
Every other reply follows the instructions of the session: this skill does not change it.

The name carries `cozy` because the skills of the cozy sandbox are the main readers.
Nothing in the format needs cozy.

## Replies

The user reads a skill reply as he reads the output of a shell command: he looks for the same element in the same place every time.
So the reply is a column of rows, and nothing else.

- The rows are one `text` block, and each line of it is one row, `│ <label> │ <value>`, `│ land │ branch → main`, as Nushell prints a table.
  Pad each label with spaces to the longest label of the reply, so that all values start in one column; an emoji counts as two columns.
  The block has no right border and no top or bottom line, so a long value wraps with no broken frame.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  Each of these emoji is one codepoint that a terminal draws two columns wide; one with the selector `U+FE0F`, such as `⚠️`, has no fixed width.
  A value of several lines, such as a commit message or the output of a command, goes on the next lines, each with both `│` and spaces in the label cell.
- The skill names its labels and their order.
  Its skeletons show the rows as plain text; the reply adds the borders, the padding and the emoji.
  Labels and fixed values are in English; the free text of a value is in the language of the session.
- A row prints only when it has a finding.
  A check that found nothing gets no row.
  The exception: a skill whose job is to show an absence ("no session discussed it") gives that absence a row, because there it is the finding.
- Several findings of one kind are several rows with the same label, the most expensive for the user first, unless the skill names its own order, such as commit order.
  Where the rows must fit a limit, the rest of one label folds into one row that counts them and names where the full list is.
- Findings that the user answers one by one carry a number that stays the same in every later reply; `go` names the numbers it acts on.
- A `warn` row holds a fact that changes what the user does or expects; a check that passed is never a `warn`.
- A reply that waits for confirmation ends with `│ 🟢 go │ <what go does>`.
  Every choice that `go` makes is a `pick` row above it: `│ 🔀 pick │ <question> · default: <choice> · else: <the other choices>`.
  A choice that still waits is a full `pick` row in every reply until it is answered, never "items 2 and 3 are still open".
- A question that the skill asks with no default ("ask the user") is an `open` row: `go` never answers it, so a row never turns an ask into a default.
  A reply where only `open` rows wait ends with `next`: the answer it waits for.
- A reply that waits for nothing ends with `│ 👉 next │ <the exact command or answer for the user>`, or `nothing`.
- A commit is named by its `Change-Id` where the repo has one, by sha otherwise.

A stop has one shape:

```text
stop      <step, or the name of the hook>: <the cause in one line>
state     nothing changed | <what changed, and what keeps the old state>
proof     <one line, or the output of a command on the next lines>
pick      <question> · default: <choice> · else: <the other choices>
open      <a question with no default>
go        <what go does: the defaults above>
next      <the exact action for the user>
```

`stop`, `state` and one of `go` and `next` always print.
`go` is there only when the agent can go on with a default; when only the user can act, `next` ends the reply.
The same stop as the user sees it:

```text
│ 🛑 stop  │ worktree-guard: another live session holds this worktree
│ 📦 state │ nothing changed
│ 👉 next  │ close claude-nu-8b, then say go
```

Why a table: the user asked for rows "more like nushell's tables", with "visible distinct separators, and emojis with shortened words", and chose values in one column over labels in color.

Reuse the labels other skills use for the same meaning: `go`, `pick`, `next`, `warn`, `stop`, `state`, `proof`, `open`, `done`.
A new label is for a new meaning only.

A skill that runs in a fork (`context: fork`) returns its rows as its last message.
Say in the body that the caller shows them as they came; the caller tends to retell them as prose.
