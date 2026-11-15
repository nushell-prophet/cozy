---
name: 40-park-todo
description: Park a thing this session found — a research result, a bug seen in passing, an idea — as a note in a `todo/` folder with the context that a later session needs, and do not act on it now. Use only when the user asks for it — "park this", "park-todo", "leave a todo for later", "запаркуй", "отложи в todo", "запиши в todo". An agent never parks on its own initiative.
argument-hint: [what to park] [where]
allowed-tools: Bash(git *), Bash(mkdir *), Bash(printenv *), Write
---

The user parks a thing that he does not want done now.
Write it down for a later session, which has none of this context,
and do not start the work.

## Replies

The user reads the report as he reads the output of a shell command:
the same element in the same place every time.
So the report of step 6 is one `parked` row:

```text
parked    <path of the note> · <commit> · on <branch>
```

- The row is one line of a `text` block, `│ parked │ <value>`, as Nushell prints a table.
  The label is in English;
  the free text of a value is in the language of the session.
- `<commit>` is the `Change-Id` trailer of the commit when the repo stamps one,
  its short sha otherwise.
- The row does not repeat what the note says.
- When the skill runs inside another task,
  this row goes into the reply of that task,
  and that reply ends as its own rules say.
  When the park is the whole reply, `│ 👉 next │ nothing` follows the row.
- The question of step 1 is a stop, and the reply ends there,
  in the same `│` rows, with `🛑`, `📦` and `👉` before the shared labels:

  ```text
  stop      1: two readings of what to park
  state     nothing changed
  next      answer which one to park: <one reading> | <the other reading>
  ```

## Procedure

1. **What.** The thing in `$ARGUMENTS`;
   with no arguments, the last finding the user pointed at.
   If two readings remain, ask which one.

2. **Where.** The `todo/` folder that the user names;
   without one, `todo/` in the directory where the session started,
   not in the repo root.
   `mkdir todo` when it is absent.
   The file is `<yyyyMMdd>-<slug>.md`.
   The date is today.
   The slug is a few English words, lowercase, with `-` between them.
   If the file exists, add `-1`, `-2`, … to the name.

3. **Frontmatter:**
   the template of `gi new` and `create-todo`,
   plus the session id from `printenv CLAUDE_CODE_SESSION_ID`.

   ```yaml
   ---
   status: draft #draft | accepted | in_progress | completed | rejected
   agents-mode: co-editing #read-only | grammar-fixes | co-editing
   updated: '<yyyyMMdd>' #yyyyMMdd
   origin_session: <session id>
   ---
   ```

   The key is `origin_session`, not `session`:
   `gi` reads a `todo/` note with `session:` as a canvas,
   and `gi open` would then resume this session, which belongs to another task.
   `origin_session` is the address that `40-why-is-this` follows into the transcripts.

   `status: draft` marks a note with no decision yet.
   `status: accepted` marks an idea that the user checked and decided to implement,
   when the implementation must wait:
   for example, it needs much testing and can break the workflow if it lands in one go.
   The body says why it waits.
   `accepted` is the word of PEP and RFC processes for "decided, not implemented".

4. **Body:** `# <title>`, then what a reader needs to act without this session:
   - what was found, and how it showed: the command and its real output, in `# =>` lines;
   - where: a change-id link (`cozy git link <file>`, in cozy) or a path with a quote, never a bare sha;
   - the words of the user about it, verbatim;
   - why it waits, and the first step when someone picks it up.

   Keep it short.

5. **Commit** only the note, on the current branch of the repo that holds it:
   `git -C <todo folder> add <path>`, subject `todo: add <slug>`.

6. **Report** the path in the `parked` row of *Replies*.
