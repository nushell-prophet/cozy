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

The default mode is locked — all keys pass through to the running application. `ctrl+shift+g` toggles between locked and normal mode (the standard `ctrl+g` is left free for applications like Claude Code).

Shortcuts:

- `ctrl+shift+g` — toggle Zellij locked/normal mode
- `cmd+t` — new tab
- `cmd+n` — new pane within current tab
- `cmd+w` — close the currently selected pane (or a floating window like Helix and Broot, described below)
- `cmd+h/j/k/l` — navigate panes
- `cmd+shift+j/k` — navigate tabs

### Helix editor

Helix is my terminal text editor. It plays nicely with Nushell and is quite newbie-friendly. `cmd+shift+e` opens the current pane's scrollback in Helix for easy copying.

In Helix, `+ s` (custom `+` menu, then `s`) copies the selected lines and wraps them into an XML tag for pasting into AI agents:

```xml
<selected-text file="README.md" lines="43-43">selected content here
</selected-text>
```

### Lazygit

Lazygit is a godsend interface for git that greatly simplifies everyday operations. Integrated into Zellij — `cmd+alt+l` opens it in a floating window for staging files and other git tasks. Uses git-delta for side-by-side diffs.

### Broot

Broot is a file manager with a tree-like structure and fuzzy search. `cmd+shift+b` opens it. `:pbq` quits and copies the selected path (relative to repo root) to the clipboard; `:pbfq` copies the full path instead.

### FZF

I use fzf for navigating Nushell history.

In Nushell there are keybindings:
- `ctrl+f` to spawn fzf with Nushell history; after selecting, the command is inserted into the command line.
- `alt+f` to spawn fzf with `^currently-entered-commandline`; the current command line is replaced with the selection.

In fzf, `tab` and `shift-tab` select multiple commands. On enter, selected commands are joined with `;\n`.

### Wezterm

I use Wezterm for connecting to this environment. The config is vendored at [vendor/dotfiles/wezterm/wezterm.lua](vendor/dotfiles/wezterm/wezterm.lua).

Its killer feature is `ctrl+shift+space` — it highlights paths and Nushell's structured output elements for quick copying.

First, build the image and create a sandbox (run from the repo root):

```sh
docker build -t nushell-ai-sandbox:v1 .
docker sandbox run --name nushell-ai-container --load-local-template -t nushell-ai-sandbox:v1 claude example/ws
```

The last argument is the workspace directory. Files in it are synced bidirectionally between the host and the VM as changes happen. Replace `example/ws` with your own project path. Inside the sandbox, the workspace is symlinked to `~/ws/` for convenience (see `nushell-autoload/module-imports.nu`).

Then connect to the sandbox with Wezterm (`/home/agent/ws` is a symlink to whichever workspace you mounted):

`wezterm --config-file vendor/dotfiles/wezterm/wezterm.lua start -- docker sandbox exec -it -w /home/agent/ws nushell-ai-container nu -l --commands 'print -n $"\e]1337;SetUserVar=SANDBOX_MODE=b24=\e\\"; zellij attach -c sandbox'`

## Nushell modules

### numd

`numd` is a module for literate programming. `numd run <file>` parses Nushell code blocks in an `.md` file, executes them, and updates the file with captured output.

### dotnu

`dotnu embeds` is another module for literate programming. It executes a Nushell script, captures output from `| print $in` lines, and injects the results back into the `.nu` file as `# =>` comments after each corresponding line.

### claude-nu

A Nushell toolbox for working with Claude Code sessions. Main commands:

- `claude-nu messages` — extract user messages from sessions (supports filtering, multi-session search, and assistant responses)
- `claude-nu sessions` — parse session files into structured summaries
- `claude-nu parse-session` — detailed session analysis with selectable columns (file ops, tool stats, agents, etc.)
- `claude-nu export-session` — export session dialogue as markdown
- `claude-nu save-markdown` — save exported sessions to files
- `claude-nu download-documentation` — download Claude Code docs and Nushell docs (from the Nushell book) for offline use

The environment also includes Claude Code skills for building Nushell completions and writing opinionated Nushell code.

### nu-goodies

A personal collection of everyday Nushell commands developed over time. In the AI context, two commands may be especially useful:

- `example` — captures the last pipeline from history, runs it, and formats command + output as a copyable snippet (wraps output in `# =>` comments and the command in `nu -c '...'`)
- `copy-out` — grabs commands with their output from Zellij pane scrollback and copies them to the clipboard (output lines are prefixed with `# =>`)

