---
name: 40-park-todo
description: Park a thing this session found — a research result, a bug seen in passing, an idea — as a note in a `todo/` folder, written and committed by a fork, with the context that a later session needs, and do not act on it now. Use only when the user asks for it — "park this", "park-todo", "leave a todo for later", "запаркуй", "отложи в todo", "запиши в todo". An agent never parks on its own initiative.
argument-hint: [what to park] [where]
allowed-tools: Agent, Bash(git *), Bash(mkdir *), Bash(printenv *), Read, Write
---

The user parks a thing that he does not want done now.
Write it down for a later session, which has none of this context,
and do not start the work.

## Replies

The user reads the report as he reads the output of a shell command:
the same element in the same place every time.
So the report of step 4 is one `parked` row:

```text
parked    <path of the note> · <commit> · on <branch>
```

- The row is a `text` block of two lines:
  the label `parked` on a line of its own,
  and the value on the next line, with four spaces before it.
  The label is in English;
  the free text of a value is in the language of the session.
- `<commit>` is the `Change-Id` trailer of the commit when the repo stamps one,
  its short sha otherwise.
- The row does not repeat what the note says.
- When the skill runs inside another task,
  this row goes into the reply of that task,
  and that reply ends as its own rules say.
  When the park is the whole reply, the row `👉 next` with the value `nothing` follows it.
- The question of step 1 and a fork that returned `parked: not parked: <cause>` are stops, and the reply ends there,
  in rows of the same form, with `🛑`, `📦` and `👉` before the shared labels:

  ```text
  stop      1: two readings of what to park
  state     nothing changed
  next      answer which one to park: <one reading> | <the other reading>
  ```

## Procedure

1. **What and where.** The thing in `$ARGUMENTS`;
   with no arguments, the last finding the user pointed at.
   If two readings remain, ask which one, as a stop.
   The folder is the `todo/` that the user names;
   without one, `todo/` in the directory where the session started,
   not in the repo root.

2. **Start one fork**: the Agent tool with `subagent_type: "fork"`.
   Its prompt holds the words of the user about the park verbatim, the thing of step 1 in one line, the `todo/` folder as an absolute path, and this sentence:
   "Read `<base directory>/references/procedure.md` and follow it."
   `<base directory>` is the absolute path in the "Base directory for this skill" line that came with this text.
   Do not read that file yourself.
   Why a fork and not another agent type: a fork inherits this conversation,
   so it sees the finding and the words of the user about it.
   Why a fork at all: the procedure stays out of this context, and the main task goes on.
   When the Agent tool or the fork type is absent, read `references/procedure.md` and follow it here.

3. **Go on with the task.**
   Do not start the parked work.
   The fork commits on the current branch while the task goes on,
   so until its notification arrives, do not run `commit --amend`, `reset` or `rebase`:
   they would take the `todo:` commit along.

4. **Report** the result of the fork in the `parked` row of *Replies*.
   The fork runs in the background: write the row only after its notification arrives,
   from the line it returned with the prefix `parked:`.
