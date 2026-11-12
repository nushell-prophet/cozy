---
name: 40-skill-authoring
description: >
  Conventions for writing or revising a Claude Code skill so that its replies read
  like shell output — the same rows in the same place on every run — and so that it
  works for a reader who has none of the author's setup. Use this skill when the user
  asks to "write a skill", "make a skill for cozy", "add a Replies section", "make the
  skill output deterministic", "the skill answers differently every time", "смастери
  скилл", "напиши скилл", "сделай вывод скилла стабильным", or when a SKILL.md is
  created or reviewed. It adds to the stock skill-creator; it does not replace it.
version: 0.1.0
---

A skill is read twice: by the agent that runs it, and by the user who reads what the run prints.
The stock `skill-creator` covers the first reader.
This skill covers the second one, and a few rules that keep a public skill honest for a stranger.

## Two kinds of skill

- **A reference skill** guides how the agent works and prints nothing of its own: a style guide, a command reference.
  It gets no `## Replies` section.
- **A procedure skill** shows the user a plan, a stop, a report or a handoff.
  It gets a `## Replies` section, and its steps point at it ("report in the shape of *Replies*").

A skill that mostly guides but ends each run with a report is a procedure skill for that report.

## Replies

The user reads a skill reply as he reads the output of a shell command: he looks for the same element in the same place every time.
So the reply is a column of rows, and nothing else.

- The rows are one `text` block, and each line of it is one row, `│ <label> │ <value>`, `│ land │ branch → main`, with the labels padded to one width.
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

Reuse the labels other skills use for the same meaning: `go`, `pick`, `next`, `warn`, `stop`, `state`, `proof`, `open`, `done`.
A new label is for a new meaning only.

A skill that runs in a fork (`context: fork`) returns its rows as its last message.
Say in the body that the caller shows them as they came; the caller tends to retell them as prose.

## Where the labels come from

Do not invent the shape at the desk, and do not change the behaviour while you shape the reply.
A row describes what the skill already does: a `go` row where the skill never waited, or a `pick` row for a choice no step makes, is a new gate in the costume of a format.
After the edit, compare the old and the new text and list every instruction, check and stop that moved or vanished.

When the skill has run before, read its real replies and take the shape that recurs.
In a cozy sandbox the `claude-nu` module reads the transcripts: `claude-nu projects | claude-nu tool-calls --tool Skill '<name>'` finds the runs, and `claude-nu timeline` gives the replies in order.
Look for what the user asked right after a reply: "what next?", "what are those items?", "did you run the tests?" each mark a row that was missing.
A skill with no runs takes its rows from its own steps: one row per decision a step makes, one per artifact it leaves.

## A public skill stands alone

A skill in a published plugin is read by people who have none of the author's setup.

- It carries its own copy of the rules above, shortened to what it needs; a pointer to a private instruction file leads nowhere.
- No machine paths, no names of an environment, no claims about "this machine".
  A setup-specific hint is one short aside: "in cozy, …; elsewhere, …".
- A number goes stale: write the command that produces it, or date it and name its source.
- The `description` drives triggering.
  Write it in the third person, quote the phrases the user really says, in each language they say them in.
  An edit to it changes when the skill fires, so make it on purpose, not as a side effect of other work.

## Prose

- One sentence per line, so a reworded sentence is a one-line diff.
- No Markdown tables: the reader often sees the file in a terminal.
- Straight quotes only.
- `SKILL.md` is the entry point; long detail goes to `references/*.md`, each named in one line.
- A trap is named by its symptom, the exact error text the agent will see.
