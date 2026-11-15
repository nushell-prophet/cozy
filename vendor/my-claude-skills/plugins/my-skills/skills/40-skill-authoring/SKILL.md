---
name: 40-skill-authoring
description: >
  Conventions for writing or revising a Claude Code skill so that the replies of a
  command skill read like shell output — the same rows in the same place on every run — and so that it
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

## Three kinds of skill

- **A reference skill** guides how the agent works and prints nothing of its own: a style guide, a command reference.
  It gets no `## Replies` section.
- **An analysis skill** reads, judges and reports findings: an audit, a review, a history search.
  It gets no `## Replies` section: its report is structured Markdown, with headings, lists and code blocks where the findings need them.
- **A command skill** is one the user runs again and again to do the same job: land a branch, export, cut a release.
  It shows a plan, a stop, a report or a handoff, so it gets a `## Replies` section, and its steps point at it ("report in the shape of *Replies*").

Why: the user reads the output of a command skill as he reads the output of a shell command, and looks for the same row in the same place on every run.
A finding of an analysis has a shape of its own — a quote, a diff, an argument — and a table cell breaks it.

The format of the rows is in the skill `40-cozy-output-formatting`.
The `## Replies` section of a command skill names only its own rows and their order.
It also tells the agent to load that skill with the Skill tool before the first reply.

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

- It carries its own copy of the rules of `40-cozy-output-formatting`, shortened to what it needs; a pointer to a private instruction file leads nowhere.
- No machine paths, no names of an environment, no claims about "this machine".
  A setup-specific hint is one short aside: "in cozy, …; elsewhere, …".
  The rule is for the body: a name can carry the main reader of the skill, as `40-cozy-output-formatting` does.
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
