# Nushell-prophet's ai-sandbox (Docker-based convenient terminal environment)

I spent a huge amount of time tuning my terminal setup to make it convenient and powerful. I believe terminal newbies can use it as an inspiration or as a tool that works out of the box.

## Preamble

This is a work-in-progress educational project with video demos on the way.

## Technologies

### Docker sandbox

My ai-sandbox is based on `docker sandbox`, so it is:
- macOS and Windows compatible
- isolated
- convenient
- with built-in AI agents (I personally tested it with `claude code`)

### Nushell

A modern shell for the AI era: Nushell 0.110.0 with sensible settings that I've chosen over 3 years of Nushell experience.

Nushell has built-in MCP functionality that allows AI agents to use all of its rich functionality. The MCP server is activated for `claude code` out of the box.

### Zellij

Zellij is an extremely convenient and powerful terminal multiplexer.

A new tab can be spawned via `cmd+t` and a new pane within the current tab via `cmd+n`.

Shortcuts:

- `cmd+t` — new tab
- `cmd+n` — new pane within current tab
- `cmd+w` — close the currently selected pane (or a floating window like Helix and Broot, described below)
- `cmd+h/j/k/l` — navigate panes
- `cmd+shift+j/k` — navigate tabs

### Helix editor

Helix is my terminal text editor. It plays nicely with Nushell and is quite newbie-friendly. In my environment, hitting `cmd+shift+e` opens the current pane's scrollback for editing in Helix, making it a breeze to copy contents.

### Lazygit

Lazygit is a godsend interface for git. It greatly simplifies my everyday git operations, and I would like to demo it. Lazygit is integrated into Zellij, so wherever user hits `cmd+alt+l`, Lazygit will jump in a floating window to stage files and do other git stuff.

### Broot

Broot is a file manager with a tree-like structure and fuzzy search. It can be called with `cmd+shift+b`. It can be quit with a copied path relative to the git repo root using `:pbq`, or a full path using `:pbfq`. The path will be copied into the clipboard and can be pasted anywhere.

### FZF

I use fzf for navigating Nushell history.

In Nushell there are keybindings:
- `ctrl+f` to spawn fzf with Nushell history; after selecting, the command is inserted into the command line.
- `alt+f` to spawn fzf with `^currently-entered-commandline`; the current command line is replaced with the selection.

In fzf, `tab` and `shift-tab` select multiple commands. When multiple commands are selected, after hitting enter they will be placed delimited by `;\n`.

### Wezterm

I use Wezterm for connecting to this environment. The settings can be found here.

The killer feature of Wezterm is the `ctrl+shift+space` shortcut to highlight paths and Nushell's structured output elements for quick copying.

I spawn Wezterm with this command:

`wezterm start -- docker sandbox exec -it -w /Users/user/git/container nushell-ai-container nu -l --commands 'print -n $"\e]1337;SetUserVar=SANDBOX_MODE=b24=\e\\"; zellij attach -c sandbox'`

## Nushell modules

### numd

`numd` is a module for literate programming. It parses .md files with Nushell code blocks, executes them, captures the output, and updates the .md files.

### dotnu

`dotnu embeds` is another tool for literate programming. It parses Nushell scripts for `| print $in` lines, executes the whole script, captures the output, and pastes the results back into the `.nu` file with results commented as `# =>` just after the line that outputted them to the console.

### claude-nu

A Nushell toolbox for working with Claude Code sessions. Main commands:

- `claude-nu messages` — extract user messages from sessions (supports filtering, multi-session search, and assistant responses)
- `claude-nu sessions` — parse session files into structured summaries
- `claude-nu parse-session` — detailed session analysis with selectable columns (file ops, tool stats, agents, etc.)
- `claude-nu export-session` — export session dialogue as markdown
- `claude-nu save-markdown` — save exported sessions to files
- `claude-nu download-documentation` — download Claude Code docs and Nushell docs (from the Nushell book) for offline use

The environment also includes Claude Code skills for building Nushell completions and writing opinionated Nushell code.
