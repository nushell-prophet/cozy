---
name: nu-cmd-stack
description: This skill should be used when you are about to hand the user commands to run in their interactive Nushell shell — instead of a code block for them to copy, write the commands as a cmd-stack file that the user loads with `cmd-stack load`, and later read whether they ran and with what exit status. Relevant when a command needs the user's own REPL, their eyes, or their hands; when you give the user a sequence of commands; when the user says "put it in cmd-stack", "положи в стек", "дай команды"; or when the user says "done", "ran it", "выполнил" about commands you handed over.
---

# Hand commands to the user as a cmd-stack file

The user runs commands in an interactive Nushell shell, often in another zellij pane.
A command copied from the chat breaks on wrapped lines and indents,
and `!` in Claude Code runs bash, not Nushell.
So write the commands to a stack file:
the user loads it with `cmd-stack load <Tab>` when ready,
or the newest one with `cmd-stack load --last-stack`.
The load puts the first command into the command line,
and the user runs it with Enter and gets each next one with `ctrl+alt+k`.

Use it where the user has [nu-cmd-stack](https://github.com/nushell-prophet/nu-cmd-stack) with `cmd-stack load`;
cozy loads it in every interactive nu out of the box, from `~/repos/nu-cmd-stack/cmd-stack`.
A command for another machine — for example, the host of a container — does not go in a stack file: the folder of the stacks and the history that `cmd-stack runs` reads are on this machine.
Write it as a [dotnu](https://github.com/nushell-prophet/dotnu) embeds script in a folder that both machines see; in cozy, that is the workspace.
The user runs `dotnu embeds-update <file>` there, and the output lands in the file as `# =>` lines for you to read.

## Replies

The user reads the handoff and the outcome as he reads the output of a shell command:
he looks for the same element in the same place every time.

- The part of the reply that this skill writes is a list of rows.
  The rows are one `text` block.
  A row is a label on a line of its own,
  and its value on the next line, with four spaces before it:
  `👉 next`, and under it `cmd-stack load 20261104-1530-check-the-branch`.
  No empty line stands between the rows.
  The shared labels carry an emoji before the word: `🛑 stop`, `📦 state`, `🔎 proof`, `🔀 pick`, `❓ open`, `🟡 warn`, `🟢 go`, `👉 next`, `✅ done`; a label of one skill has none.
  The skeletons below show a row as one line, the label and then the value;
  the reply puts the value under the label and adds the emoji.
  The labels are in English; the free text of a value is in the language of the session.
- A row prints only when it has a finding.
  A check that passed gets no row: a file that parses is the normal case.
- Several findings of one kind are several rows with the same label, the most expensive for the user first.
- `warn` is a fact that changes what the user does or expects,
  for example a step inside the stack that only the user can do.
- When the stack comes at the end of a longer reply,
  its rows are the last rows of that reply,
  and the reply has one `next` row only.

The handoff:

```text
stack   <file name> · <N> commands · <what the stack does, in a few words>
warn    <a manual step inside the stack, or a side effect of running it from the user's shell>
next    cmd-stack load <file name>, then say "done"
```

The outcome, after the user says the commands ran:

```text
ran      <N> of <M> commands · <exit 0 | which command failed, was edited, or did not run>
warn     <the history holds no runs of the stack: the commands ran outside it>
result   <what the runs show the commands changed>
next     <the exact next action for the user> | nothing
```

The `warn` about no runs replaces `ran`: with no runs there is nothing to count.
`result` prints only when the runs or the dumped screen show it; `next` always prints.

## Write the file

The folder is `$env.CMD_STACK_DIR`, or `~/.local/share/nushell/cmd-stacks/` when it is not set.
Name the file by time and topic, `20261104-1530-check-the-branch.nu`:
completion shows the newest file first.

The file is a Nushell script:

- The first block, of only comments, describes the stack; completion shows its first line.
- Then one block per command, and one empty line between blocks.
- A `# ...` line on top of a command says what it does: the user sees it in the prompt.
- No empty line inside a command: it splits the command in two.
- Complete commands, with no placeholders: each runs as written.

```nu
# check the branch before landing

# what is not committed
git status --short

# the last three commits
git log -3 --format="%h %s"
```

Write it with the Write tool, so that no quote needs an escape.
Check that it parses, in cozy with
`nu --config ~/.config/nushell/autoload/modules-core.nu --commands 'dotnu diagnose <file> | to nuon'`:
an empty list means no errors.
Then give the user the command to load it, in the handoff of *Replies*: `cmd-stack load 20261104-1530-check-the-branch`.

## Read the outcome

When the user says the commands ran:

```bash
nu --commands 'use ~/repos/nu-cmd-stack/cmd-stack; cmd-stack runs 20261104-1530-check-the-branch | to nuon --pretty'
```

`~/repos/nu-cmd-stack/cmd-stack` is the path in cozy; elsewhere, use the `cmd-stack/` directory of the user's clone of nu-cmd-stack.

- There is one row for each command that a shell showed; `index` counts the commands, not the description.
- `ran` is the history row that the shell ran after it showed the command.
  When `ran` differs from `command`, the user edited the command or ran a different one.
- `ran: null` means the shell showed the command, but ran nothing after it yet.
- `exit_status` and `duration` come from the history; the output does not.
  For the output, read the screen of the pane where it ran:
  `zellij action dump-screen --pane-id <pane> --full`.
  The dump holds only the lines that the pane still keeps.

Report the outcome as *Replies* shows.
