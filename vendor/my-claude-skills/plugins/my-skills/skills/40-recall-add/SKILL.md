---
name: 40-recall-add
description: Add one record to the user's recall list — a key, a command or a flag that this session built or explained, written as "situation → action" so that the user can train it later and an agent can look it up. Use only when the user asks for it — "recall-add", "add this to recall", "remember this key for me", "запиши в recall", "добавь в recall", "запиши момент", "запиши, чтобы я потренировал". An agent never adds a record on its own initiative.
argument-hint: [what to record] [path of the list]
allowed-tools: Bash(git *), Read, Edit
---

The user asks agents for many keys, commands and flags, and forgets the ones he does not use soon.
The recall list keeps each of them as one line: the situation he is in, then the action that answers it.
He remembers the situation and not the key, so the situation comes first.

## Replies

The user reads the report as he reads the output of a shell command:
the same element in the same place every time.
So the report of step 5 is one `added` row:

```text
added     <the record as written> · <commit>
```

- The row is one line of a `text` block, `│ added │ <value>`, as Nushell prints a table.
  The label is in English;
  the record is in the language of the list.
- When step 3 changed an old record, the row is `│ changed │ <the record as written> · <commit>`.
- `<commit>` is the `Change-Id` trailer of the commit when the repo stamps one,
  its short sha otherwise.
- When the skill runs inside another task,
  this row goes into the reply of that task,
  and that reply ends as its own rules say.
  When the record is the whole reply, `│ 👉 next │ nothing` follows the row.
- A question of step 1 or step 2 is a stop, and the reply ends there,
  in the same `│` rows, with `🛑`, `📦`, `❓` and `👉` before the shared labels:

  ```text
  stop      2: no instruction names the recall list
  state     nothing changed
  open      which file holds the recall list?
  next      give the path, or name the list in your instructions
  ```

## Procedure

1. **What.** The thing in `$ARGUMENTS`;
   with no arguments, the last key, command or flag that the session built or explained.
   One record holds one situation.
   If two readings remain, ask which one.

2. **Where.** The path in `$ARGUMENTS`;
   without one, the file that the instructions of the user name as the recall list.
   If nothing names it, ask: never make a list in a place that you chose.
   Read the file, and read the `CLAUDE.md` next to it when there is one:
   it can state the language of the records and the branch for the commit.

3. **The record** is one line at the end of the file:

   ```text
   - <tool>: <situation> → <action>
   ```

   - `<tool>` is the name of the program, in lowercase: `visidata`, `git`, `helix`.
   - `<situation>` says where the user is and what he wants, in his words, with no name of a key or a command in it:
     a reader who sees only this part must be able to answer from memory.
   - `<action>` is the exact keys or the exact command, in backticks.
   - The line holds ` → ` exactly once:
     a reader splits the question from the answer there.
   - Record only an action that this session ran, or read in the config that the machine uses.
     A guess is not a record: check it first, or say that you cannot.
   - If a line for the same situation is in the file, change that line and do not add a second one.

   The line carries no date and no source:
   `git log` and `git blame` of the list give both.

4. **Commit** only the list, on the current branch of the repo that holds it:
   `git -C <folder of the list> add <file>`, subject `recall: add <tool> <a few words of the situation>`,
   or `recall: change <tool> <a few words of the situation>` when step 3 changed an old record.
   The body is one line: where the action is defined, as a path, or as a change-id link for a file in another repo.

5. **Report** the record in the `added` row of *Replies*.
