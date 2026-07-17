<p align="center"><img src="https://github.com/user-attachments/assets/96b23749-53c4-48dd-a80c-6e0d5567257a" height="40"></p>

A convenient terminal environment for AI sandboxes (and macOS hosts). 

I tune my terminal setup full time. Now it's packaged so others can pick it up as inspiration or as a working starting point. I still encourage everyone to roll their own eventually — it's the only path to mastery.

This is a work-in-progress educational project; video demos are on the way.

## Quick start

Cozy's primary target is `sbx` (Docker's standalone sandbox runtime, formerly `docker sandbox`), so the quick start uses the `sbx` kit. Other targets — plain Docker, Apple `container`, a macOS host — run the same installer and land on the same toolset: see [Install elsewhere](#install-elsewhere) and [Debian image](#debian-image-in-testing) below.

First, install the `sbx` CLI: https://docs.docker.com/ai/sandboxes/#get-started

```sh
# Clone the repo, cd into it
git clone https://github.com/nushell-prophet/cozy
cd cozy

# Launch a sandbox with the cozy kit. `shell` is the agent; `--kit sbx-kit/`
# layers cozy on top — it clones this repo in-sandbox and runs the shared
# bootstrap.nu installer (no image build needed). The last argument is the
# folder to mount as your workspace. Here `.` is the cozy repo you just cloned,
# so you land in something to explore — point it at your own project (e.g.
# `~/my-project`) once you're set up.
sbx run shell --kit sbx-kit/ .

# connect to the sandbox and start the Zellij session (NAME from `sbx ls`)
sbx exec -it NAME nu --login --execute 'zellij attach -c NAME'
```

Note: the kit installs cozy from GitHub — the latest commit on the default branch — not from your local checkout. Push your changes before `sbx run`, or pin a tag via `--branch` in [sbx-kit/spec.yaml](sbx-kit/spec.yaml) if you need reproducible installs.

## Technologies

**Installed**: [Nushell](#nushell), [Helix](#helix-editor), [Zellij](#zellij), [Lazygit](#lazygit), [Broot](#broot), [FZF](#fzf), git-delta, [VisiData](#visidata), bat, topiary, fd, jj, git-lfs, Claude Code, procps, file, gcc, libc6-dev (base image adds git, curl, Python, Node.js, Go, ripgrep, jq, gh)

**Optional** (`cozy install`): Rust, nu_plugin_polars, nu-plugin-image, Claude Code (reinstall)

**Rebuild from source** (`cozy install`): Nushell, Zellij (without web sharing), topiary

### sbx

Cozy is based on [Docker's sandbox runtime](https://docs.docker.com/ai/sandboxes/) (`sbx`), so it is:
- macOS and Windows* (experimental) compatible — the image provides both `arm64` and `amd64` architectures
- isolated
- with built-in AI agent (I personally tested it with `claude code`)

**\* Windows support**

I develop and use `cozy` on macOS, but I expect some of my students to use Windows. After brief testing, the main issue turned out to be the keyboard layout: Windows doesn't have a Cmd key, and its Win key combinations are reserved by the OS — so simply replacing Cmd with Win isn't possible. The best option I've found so far is to replace Cmd with Alt.

To apply this automatically, run `cozy swap-zellij-super` inside the sandbox.

### Nushell

A modern shell for the AI era: Nushell with sensible settings that I've chosen over 3 years of Nushell experience.

Nushell has built-in MCP functionality that lets AI agents use all of its rich capabilities with persistent session state: variables an agent sets survive across calls. The MCP server is activated for `claude code` out of the box.

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
- `cmd+shift+h/l` — navigate tabs

### Helix editor

Helix is my terminal text editor. It plays nicely with Nushell and is quite newbie-friendly. `cmd+shift+e` opens the current pane's visible screen in Helix for easy copying (`cmd+alt+e` opens the full scrollback).

In Helix, `+ s` (custom `+` menu, then `s`) copies the selected lines and wraps them into an XML tag for pasting into AI agents:

```xml
<selected-text file="README.md" lines="43-43">selected content here
</selected-text>
```

### Git attribution

Git environment variables (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`) are exported from `/etc/sandbox-persistent.sh`, which the sandbox sources before every bash invocation — including Claude Code's bash tool, so commits made by Claude are attributed to `claude@anthropic.com`. Interactive Nushell does not source bash profiles, so these variables never reach your `nu` session: commands you run there use your own git identity (`git config user.name` / `git config user.email`). Note the flip side: in a bash shell the exported variables override `git config`, so commits made from bash are attributed to Claude too.

### Lazygit

Lazygit is a godsend interface for git that greatly simplifies everyday operations. Integrated into Zellij — `cmd+alt+l` opens it in a floating window for staging files and other git tasks. Uses git-delta for side-by-side diffs.

### Broot

Broot is a file manager with a tree-like structure and fuzzy search. `cmd+alt+b` opens it, and `alt+enter` pastes the selected path back to the active pane.

### FZF

I use fzf for navigating Nushell history.

In Nushell there are keybindings:
- `ctrl+f` to spawn fzf with Nushell history; after selecting, the command is inserted into the command line.
- `alt+f` to spawn fzf with `^currently-entered-commandline`; the current command line is replaced with the selection.

In fzf, `tab` and `shift-tab` select multiple commands. On enter, selected commands are joined with `;\n` and are pasted back into the command line.

### VisiData

VisiData is a tabular viewer and data multitool by Saul Pwanson — years of hands-on data work distilled into one terminal app. Nushell's built-in `explore` is great and I use it too, but for deeper digging `vd` remains my go-to. In cozy, `in-vd` pipes any structured data into VisiData (format auto-detected), and `hist` queries Nushell's SQLite history with filters and opens the result in `vd`.

### Wezterm

I use Wezterm to connect to this environment on my Mac (on Windows, see the note at the end of this section). The config is vendored at [vendor/dotfiles/wezterm/wezterm.lua](vendor/dotfiles/wezterm/wezterm.lua); install Wezterm with `brew install wezterm --cask`.

Changes from WezTerm defaults:

- **QuickSelect** (the killer feature): `ctrl+shift+space` highlights matches on screen for quick copying. Custom regexes extend it to paths, jj change IDs, Nushell error locations (`╭─[file:line:col]`), and Nushell table headers and values.
- **Keybindings**: all defaults disabled; CMD+SHIFT+letter sends kitty-protocol escape sequences so Zellij and apps behind it can distinguish them
- **Dynamic modes**: the `ZEN_MODE` user variable adjusts font size at runtime; the sandbox background is set at window creation via `--config` (see the launch command below)

The launch command below targets `sbx`, the entry point I test against:

```
# NAME = your sandbox name (from `sbx ls`) — replace both
# on another runtime, swap the `sbx exec -it NAME` part (Apple container, …)
wezterm --config-file vendor/dotfiles/wezterm/wezterm.lua --config 'colors={background="#000000"}' start -- sbx exec -it NAME nu --login --execute 'zellij attach -c NAME'
```

**On Windows I'd use the standard terminal instead.** I use Wezterm on Mac because it lets me disable the default shortcuts that would otherwise clash with Zellij's bindings. On Windows: I've heard Wezterm is flakier, and since `cozy swap-zellij-super` already remaps those bindings from Super to Alt, few conflicts are expected anyway. There are also likely more caveats I haven't tested.

## Nushell modules loaded by default

### nu-goodies

A personal collection of everyday Nushell commands developed over time. In the AI context, two commands may be especially useful:

- `example` — captures the last pipeline from history, runs it, and formats command + output as a copyable snippet (wraps output in `# =>` comments and the command in `nu -c '...'`)
- `copy-out` — grabs commands with their output from Zellij pane scrollback and copies them to the clipboard (output lines are prefixed with `# =>`)

### nu-kv

A key-value store for Nushell. Autoloaded with the `kv` prefix.

### nu-cmd-stack

Command history stacking module.

### numd

`numd` is a module for literate programming. `numd run <file>` parses Nushell code blocks in an `.md` file, executes them, and updates the file with captured output.

### dotnu

`dotnu embeds` is another module for literate programming. It executes a Nushell script, captures output from `| print $in` lines, and injects the results back into the `.nu` file as `# =>` comments after each corresponding line.

### claude-nu

A Nushell toolbox for working with Claude Code sessions. Main commands:

- `claude-nu -f 'regex'` — search user messages across sessions (add `--all-projects` to widen); with no `--find` it points at the subcommands
- `claude-nu projects` — list projects under `~/.claude/projects`, most recent first
- `claude-nu messages` — extract user messages from sessions (supports filtering, multi-session search, and assistant responses)
- `claude-nu sessions` — parse session files into structured summaries, with selectable columns (`--columns`/`--all-columns`: file ops, tool stats, agents, etc.)
- `claude-nu export-session` — export session dialogue as markdown
- `claude-nu save-markdown` — save exported sessions to files
- `claude-nu gi-hook enable/disable/status` — manage the git-intent Stop hook in the current repo

The environment also includes Claude Code skills for building Nushell completions, writing opinionated Nushell code, and inspecting or rewriting the Nushell user REPL command history.

### nutest

[nutest](https://github.com/vyadh/nutest) is a Nushell test framework by [vyadh](https://github.com/vyadh). Licensed under MIT. Not autoloaded — use `use ~/repos/nutest/nutest` to load.

## Install elsewhere

`cozy-module/install/run-install.sh` is the same boot tail the Dockerfile and the sbx kit run — one script, so the install paths can't drift apart. It deploys the full environment (nushell, modules, dotfiles, configs) into virtually any Ubuntu-based sandbox or directly onto a macOS host — for example `sbx` with a pure `shell` agent, an Apple container running Ubuntu, or a plain macOS install. Container targets additionally get the system-level setup (apt build deps, the `/etc/sandbox-persistent.sh` env exports) that a host install leaves to the machine. For *why* it's built this way — the build order and why each tool is compiled from source, vendored, or shipped — see `design/`.

**Prerequisite:** Homebrew (https://brew.sh). On a Linux host with passwordless sudo the script installs it for you; on macOS install it first — the script exits early with the copy-paste command, so your sudo password never goes through a script. On a Linux host, `gcc` and `libc6-dev` must also be present (the topiary grammar compiles at install time) — the installer fails fast if they're missing.

```sh
git clone https://github.com/nushell-prophet/cozy
cd cozy
cozy-module/install/run-install.sh             # install
cozy-module/install/run-install.sh --force     # reinstall over existing user configs
```

## Debian image (in testing)

Alongside the standard `sbx` path, the [Dockerfile](Dockerfile) builds a lean `debian:12-slim` image for plain `docker run` and Apple `container`. The agent gets passwordless sudo only during the build and loses it in the final layer, so the running container is rootless — no standing privilege, which suits working with valuable data. It passes the full `cozy verify` suite.

**Apple `container` on Apple Silicon:** the first `container build` can fail with `Rosetta is not installed`. The builder VM defaults to `[build] rosetta = true`, so it wants Rosetta even for a native `arm64` build. Fix it without installing Rosetta — put `rosetta = false` under `[build]` in `~/.config/container/config.toml`, then `container builder stop && container builder start`. An `arm64` build never runs x86, so Rosetta stays unused either way.

