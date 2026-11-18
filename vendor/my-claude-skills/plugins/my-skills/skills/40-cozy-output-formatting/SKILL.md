---
name: 40-cozy-output-formatting
description: >
  The format of what a command skill prints to the user: rows of a label line and an
  indented value under it, the shared labels with their emoji, and the one shape of a
  stop. A command
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
So the reply is a list of rows, and nothing else.

- The rows are one `text` block.
  A row is a label on a line of its own,
  and its value on the next line, with four spaces before it:
  the sections of a manual page have this form.
  The rows follow each other with no empty line between them.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  A value of several lines, such as a commit message or the output of a command, keeps its line breaks,
  with the same four spaces before each line;
  an empty line inside the value stays empty.
  The output of a command has the command above it, on a line of its own, with `$ ` before it.
- The skill names its labels and their order.
  Its skeletons show a row as one line, the label and then the value;
  the reply puts the value under the label and adds the emoji.
  Labels and fixed values are in English; the free text of a value is in the language of the session.
- A row prints only when it has a finding.
  A check that found nothing gets no row.
  The exception: a skill whose job is to show an absence ("no session discussed it") gives that absence a row, because there it is the finding.
- Several findings of one kind are several rows with the same label:
  each finding repeats the label line, so two findings never read as one value of two lines.
  The most expensive for the user goes first, unless the skill names its own order, such as commit order.
  Where the rows must fit a limit, the rest of one label folds into one row that counts them and names where the full list is.
- Findings that the user answers one by one carry a number that stays the same in every later reply; `go` names the numbers it acts on.
- A `warn` row holds a fact that changes what the user does or expects; a check that passed is never a `warn`.
- A reply that waits for confirmation ends with the row `🟢 go`, and its value says what `go` does.
  Every choice that `go` makes is a `🔀 pick` row above it, with the value `<question> · default: <choice> · else: <the other choices>`.
  A choice that still waits is a full `pick` row in every reply until it is answered, never "items 2 and 3 are still open".
- A question that the skill asks with no default ("ask the user") is an `open` row: `go` never answers it, so a row never turns an ask into a default.
  A reply where only `open` rows wait ends with `next`: the answer it waits for.
- A reply that waits for nothing ends with the row `👉 next`:
  its value is the exact command or answer for the user, or `nothing`.
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
🛑 stop
    worktree-guard: another live session holds this worktree
📦 state
    nothing changed
🔎 proof
    $ git worktree list
    /wtr/claude-nu  8b1c2d3 [fix-records]
👉 next
    close claude-nu-8b, then say go
```

Why this form: the user quotes the reply of an agent, in a commit message or in a note,
and he copies a value as it stands when only the indent is around it.
The emoji stay because he asked for "emojis with shortened words".

Reuse the labels other skills use for the same meaning: `go`, `pick`, `next`, `warn`, `stop`, `state`, `proof`, `open`, `done`.
A new label is for a new meaning only.

A skill that runs in a fork (`context: fork`) returns its rows as its last message.
Say in the body that the caller shows them as they came; the caller tends to retell them as prose.
