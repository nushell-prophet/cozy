# Cozy (Docker-based convenient terminal environment)

I spent a huge amount of time tuning my terminal setup to make it convenient and powerful. I believe terminal newbies can use the setup that I publish as an inspiration or as a tool that works out of the box (though I really encourage everybody to build their own setup by themselves - as I believe it is the only way to mastery).

## Preamble

This is a work-in-progress educational project with video demos on the way.

## Quick start

First, install Docker Desktop https://www.docker.com/products/docker-desktop/

```sh
# Clone the repo, cd into it
git clone https://github.com/nushell-prophet/cozy
cd cozy

# Build the image (execute the command from the root of this repo)
docker build -t cozy:latest .

# create local container. Base images for the agents are provided by Docker.
docker sandbox create --name cozy-test -t cozy:latest shell example-workspace
#                                        ^^image      ^^agent ^^workspace

# connect to the container
docker sandbox exec -it cozy-test nu -l --execute 'zellij attach -c cozy-test'
```

## Technologies

### Docker sandbox

Cozy is based on [docker sandbox](https://docs.docker.com/ai/sandboxes/), so it is:
- macOS and Windows* (experimental) compatible — the image provides both `arm64` and `amd64` architectures
- isolated
- with built-in AI agent (I personally tested it with `claude code`)

**\* Windows support**

I develop and use `cozy` on macOS, but I expect some of my students to use Windows. After brief testing, the main issue turned out to be the keyboard layout: Windows doesn't have a Cmd key, and its Win key combinations are reserved by the OS — so simply replacing Cmd with Win isn't possible. The best option I've found so far is to replace Cmd with Alt.

To apply this automatically, run inside the cozy sandbox: `cozy platform apply windows`.

### Nushell

A modern shell for the AI era: Nushell with sensible settings that I've chosen over 3 years of Nushell experience.

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

### Git attribution

Git environment variables (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`) are set in `CLAUDE_ENV_FILE` (`/etc/sandbox-persistent.sh`), which is sourced only by Claude Code's bash tool. Commits made by Claude are attributed to `claude@anthropic.com`. These variables do not affect the user's interactive Nushell shell — if you configure your own git identity (via `git config user.name` / `git config user.email`), commands you run directly from the shell use your credentials.

### Lazygit

Lazygit is a godsend interface for git that greatly simplifies everyday operations. Integrated into Zellij — `cmd+alt+l` opens it in a floating window for staging files and other git tasks. Uses git-delta for side-by-side diffs.

### Broot

Broot is a file manager with a tree-like structure and fuzzy search. `cmd+shift+b` opens it, and `alt+enter` to paste back to active pane the selected path.

### FZF

I use fzf for navigating Nushell history.

In Nushell there are keybindings:
- `ctrl+f` to spawn fzf with Nushell history; after selecting, the command is inserted into the command line.
- `alt+f` to spawn fzf with `^currently-entered-commandline`; the current command line is replaced with the selection.

In fzf, `tab` and `shift-tab` select multiple commands. On enter, selected commands are joined with `;\n`.

### Wezterm

I use Wezterm for connecting to this environment. The config is vendored at [vendor/dotfiles/wezterm/wezterm.lua](vendor/dotfiles/wezterm/wezterm.lua).
Brew users can install it via `brew install wezterm --cask`.

Its killer feature is `ctrl+shift+space` — it highlights paths and Nushell's structured output elements for quick copying.

Changes from WezTerm defaults:

- **Shell**: launches Nushell with Zellij instead of the system default shell
- **Keybindings**: all defaults disabled; CMD+SHIFT+letter sends kitty-protocol escape sequences so Zellij and apps behind it can distinguish them
- **QuickSelect patterns**: custom regexes for jj change IDs, Nushell error paths (`╭─[file:line:col]`), Nushell table headers/values, and filesystem paths
- **Dynamic modes**: `ZEN_MODE` / `SANDBOX_MODE` user variables adjust font size and background at runtime


To connect to the sandbox with Wezterm (`/home/agent/workspace/mounted` is a symlink to whichever workspace you mounted) you can use the next command:

```
wezterm --config-file vendor/dotfiles/wezterm/wezterm.lua start -- docker sandbox exec -it cozy-test nu -l --execute 'print -n $"\e]1337;SetUserVar=SANDBOX_MODE=b24=\e\\"; zellij attach -c cozy-test'
```

## Nushell modules loaded by default

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

### nutest

[nutest](https://github.com/vyadh/nutest) is a Nushell test framework by [vyadh](https://github.com/vyadh). Licensed under MIT.

### nu-goodies

A personal collection of everyday Nushell commands developed over time. In the AI context, two commands may be especially useful:

- `example` — captures the last pipeline from history, runs it, and formats command + output as a copyable snippet (wraps output in `# =>` comments and the command in `nu -c '...'`)
- `copy-out` — grabs commands with their output from Zellij pane scrollback and copies them to the clipboard (output lines are prefixed with `# =>`)

