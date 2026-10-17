---
name: 40-gi-canvas
description: Turn the current chat into a gi canvas, or open an existing one. Use when the user says "gi canvas", "start a canvas", "переведи в канвас", "продолжим в канвасе", "open the canvas", or asks to move this conversation into a canvas document.
argument-hint: [canvas path] [--last-exchange] [--distill] [--no-commit]
allowed-tools: Bash(nu -c *), Bash(grep *), Bash(git *), Read, Edit
---

The user wants a canvas session but is inside a chat session, where typing nushell into Bash is awkward.
Run the module command for them and hand back one line to paste into a terminal.

A canvas session cannot be started from within a session: the gi plugin (the Canvas style, the gi skills, and the hooks that name the canvas to the agent, hold the Stop-hook floor and refuse a commit on the trunk) and `$env.GI_CANVAS`, which those hooks read, all arrive with `claude` at launch.
So this skill always ends the same way — the user runs one command themselves, in their terminal, and that new session is the canvas one.

## How to call the module

`claude-nu` is a nushell module command, not a program on PATH: it is loaded in the user's interactive REPL, and a one-shot `nu -c` does not load it.
So every command **you** run has to import it first:

```nushell
nu -c 'use ~/repos/claude-nu/claude-nu/; claude-nu gi | to nuon --pretty'
```

End it with `| to nuon --pretty`: a one-shot `nu` renders a list inside a record as `[list 2 items]`, and `canvases` is the list you need.

That path is the common one, not a guarantee.
When it is missing, don't guess a second one — read where the REPL itself imports from: `grep -h claude-nu ~/.config/nushell/autoload/*.nu`.
The `use` line there names the real directory on this machine.

The commands **the user** runs go into their REPL, where the module is already loaded — hand those over bare: `claude-nu gi open <doc>`.

## Which case

First check you are not already there.
`gi` on its own reports whether the asking session is bound to a canvas; a non-null `canvas` means this **is** a canvas session — say so and stop, there is nothing to launch.
Doing this first matters because the alternative is importing a session that is already a canvas into a second file, which splits one conversation across two documents.
The same call answers the rest: `canvases` lists the canvases already here, and `folder` names where a new one lands.
Do not list the canvas folders yourself — a repo rarely has all of them, and `ls` exits non-zero on any missing one, so the call reads as a failure.

Then read `$ARGUMENTS` and the conversation:

- **No canvas yet, and this chat is worth keeping** (the usual case) → import this session.
- **No canvas yet, nothing here worth keeping** → a new canvas.
- **A canvas path is given, or `canvases` is not empty** → open it.

A canvas keeps one session for life, and `gi open` handles both halves of that: a canvas with no `session:` in its frontmatter gets one minted and written in, one that has it is resumed.
You do not have to tell them apart.

## Import this session

```nushell
nu -c 'use ~/repos/claude-nu/claude-nu/; claude-nu gi import canvas-naming'         # → <folder>/<date>-canvas-naming.md
nu -c 'use ~/repos/claude-nu/claude-nu/; claude-nu gi import canvas-naming --tools' # ...keeping tool calls, each input rendered whole
```

The slug is required: two to four lowercase words, joined by hyphens, that say what this chat is about.
You have just read the whole conversation, so name it for its subject, not for the session.

Named with no session, `gi import` takes the one it runs inside — which is this one, since you are running it.
The second positional names another session, and only the user needs that (they get a completer for it in the REPL).

It refuses to overwrite an existing doc — that is deliberate, do not delete the old one to get past it; pick another slug instead.

Nothing has to be in the repo beforehand: the style and the skills ride the launch as a plugin, so there is no seeding step and nothing the import can find missing.

### Flags

`$ARGUMENTS` may carry these flags; they apply to the import only.

- `--last-exchange` → pass it to `gi import`: the canvas gets only the user's last question and the answer to it.
- `--no-commit` → do not pass `--commit`.
  Without it, always pass `--commit`: the import is committed by default.
- `--distill` → after the import, distill the canvas (see *Distill* below).

Before a committed import, run `git branch --show-current`.
If it is `main` or `master`, run `git switch --create <slug>` first, with the slug of the import.
A plain chat has no gi commit guard, so this is the only thing that keeps the import off the trunk.

### Distill

The gi plugin is not loaded in this chat, so `gi:git-intent-distill` cannot be called as a skill.
Read `distill.md` next to this file and follow it on the imported canvas.

- With commits: the import commit is the pre-distill version.
  Scope the clean-tree check of `distill.md` to the canvas, `git status --porcelain -- <doc>`: other untracked notes in the repo do not touch its history.
  Commit the distilled canvas as a second commit.
- With `--no-commit`: distill the untracked file in place and commit nothing.
  Skip the clean-tree check: the full dialogue stays in the session log, at the `.jsonl` path the import note names.

Then tell the user, in one line: exit this session and run `claude-nu gi open <doc>`.
The import wrote this session's id into the canvas, so that reopens **this same session** (same id, full context) with the canvas bound, and the missing tail — the turns after the import, which the session log cannot contain yet — is still in context and can be appended there.

## A new canvas, or an existing one

`gi new` and `gi open` launch Claude Code themselves, so the user runs them — not you.
Hand over one of these, as is:

```nushell
claude-nu gi new <slug>            # <folder>/<date>-<slug>.md, opened in $EDITOR for the task, then launch; leaves main/master first
claude-nu gi open <doc>            # an existing canvas; resumed if it holds a session
claude-nu gi open <doc> --fork     # a copy, <doc>_1.md, on a session of its own
claude-nu gi open <doc> --no-hook  # no Stop-hook floor; the commit guard stays
```

For `gi new`, pick the slug as for an import: two to four words on what the canvas is for.

## What to report

One line with the exact command to run.
No explanation of the protocol, no summary of what the canvas is; the style file does that once the session starts.
