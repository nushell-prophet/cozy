---
status: 'in_progress'
created: '20260528-172203 #yyyyMMdd-hhmmss'
updated: '20260529-220157 #yyyyMMdd-hhmmss'
related_files:
  - vendor/dotfiles/zellij/config.kdl
  - vendor/dotfiles/zellij/todo-nu/todo.nu
  - vendor/dotfiles/zellij/lazygit-helix.nu
  - vendor/dotfiles/zellij/broot-paste.nu
  - vendor/dotfiles/nushell/autoload/hooks-config.nu
---

# Goal

Set up a CLI for interacting with panes via zellij, so cozy's interactive
keybinding-driven flows (which no plain script can exercise) can be tested
end-to-end without a human at the keyboard.

# Research (20260529)

Two delegated research passes: (1) what interactive surface cozy has that needs
a TTY/render to verify; (2) how zellij 0.44.3 can be driven programmatically.

## The blocker that shapes the whole design

Zellij **0.44.3 renders nothing into a pane's grid unless a real PTY client is
attached to the session.** A `--create-background` session accepts
`write`/`send-keys` and tracks command-process exit codes, but
`dump-screen`/`subscribe` return *empty*, and input sent while no client is
attached **never renders** — you cannot "send now, read later". Open issue
zellij-org/zellij#4508 (the official docs claim the opposite; wrong for 0.44.3).
Related: #4535.

Workaround (verified working in-sandbox): attach a throwaway PTY client for the
test's lifetime —
```nu
job spawn { ^script -qec "stty rows 40 cols 120; zellij attach NAME" /dev/null }
```

Two consequences:
- **Two assertion channels.** Command-pane exit codes work *headlessly*
  (`list-panes --json` -> `exited`/`exit_status`, or `--block-until-exit-success`).
  Rendered-text assertions need the attached client + `dump-screen`.
- **Pin terminal size** with `stty` in the attaching PTY (default headless pane
  is 50x49 — otherwise nondeterministic).

## Zellij capabilities (0.44.3, verified live in-sandbox)

- **Input:** `write-chars "text"` (literal, no submit) + `send-keys "Enter"` to
  submit; `send-keys "Esc"/"Ctrl c"/"Up"/"F1"/"Alt Shift b"` for named keys;
  raw decimal bytes via `write 13` (Enter), `write 27` (Esc), `write 3` (Ctrl-C).
  All accept `--pane-id terminal_N`.
- **Read:** `dump-screen [-p ID] [--full] [--ansi] [--path FILE]` — STDOUT if no
  `--path`. Default = viewport; `--full` adds scrollback; `--ansi` keeps color.
  **Only dumps a *visible* pane** — `focus-pane-id` the target first.
- **State (clientless):** `list-panes --json` (id, title, `pane_command`,
  floating flag, focus, `exited`, `exit_status`) — primary assertion source.
  Also `list-tabs --json`, `current-tab-info --json`, `query-tab-names`,
  `list-clients`.
- **Run:** `zellij run -- cmd` / `action new-pane -- cmd` returns `terminal_N`
  on stdout. `--floating`, `--cwd`, `--name`, `--close-on-exit`,
  `--start-suspended`. `--block-until-exit-success` blocks *without a client*.
  `zellij edit -f -l LINE FILE` for editor panes.
- **Setup:** KDL layouts via `zellij -l layout.kdl` (or
  `attach --create-background NAME options --default-layout PATH`) give a fixed,
  known pane topology per test — preferred over scripting panes one at a time.
- **Lifecycle:** `attach --create-background NAME` (headless, returns
  immediately, no PTY needed) / `kill-session` / `delete-session` /
  `list-sessions`.
- **No native wait-until-text / wait-until-idle** — build a poll loop
  (`dump-screen | <match>` with sleep + timeout).
- **Prior art:** [zjctl](https://github.com/mrshu/zjctl) — CLI + WASM plugin over
  `zellij pipe`, adds pane selectors (`title:/regex/`, `cmd:substr`, `focused`),
  `capture`, and `wait-idle`. Sidesteps the client hack via the plugin transport.
  Evaluate before committing to the raw `script`-PTY approach.

## Gotchas

- Default zellij mode is **`locked`** (`config.kdl:415`); harness must
  `Ctrl Shift g` into normal mode (or use binds in `shared_among "normal"
  "locked"`) before most binds fire.
- `dump-screen --pane-id` ignores hidden/closed panes — don't `--close-on-exit`
  a pane whose final output you still need; `focus-pane-id` it then dump.
- Input->render->result is async — poll, don't sleep-and-hope. TUIs
  (helix/fzf/lazygit/broot) need extra settle time.
- `subscribe` streams render updates but still needs a client for *new* input to
  render — not a workaround for #4508.

## cozy's interactive surface — prioritized targets

1. **`Super e` -> todo-hx -> create-todo** (`config.kdl:89-94`, `todo.nu:25-63`).
   Signature flow. Quitting helix *unmodified* deletes the new file (and the
   `todo/` folder if just created). Invisible to any non-TTY test.
2. **`lstd`** (`todo.nu:4-23`). fzf picker + `ctrl-e` (spawns `zellij edit`) +
   pbcopy OSC52. Three interactive layers.
3. **`Super Alt l` lazygit-helix round-trip** (`lazygit-helix.nu`). Sends `Esc`
   to the focused helix pane before lazygit, `:reload-all` after. Pane-id
   dependent, fragile.
4. **`Super Alt b` broot-paste** (`broot-paste.nu`). Injects the selected path
   into the originally-focused *tiled* pane in the same tab.
5. **PWD tab auto-rename + `·N` dedup** (`hooks-config.nu:19-48`). Runs on every
   `cd` inside a zellij session.
6. **`Super Shift e` DumpScreen -> floating helix** (`config.kdl:50-60`).
7. Nushell REPL fzf/broot keybinds (`Ctrl F`/`Alt F`/`Ctrl T`, `config.nu`).
8. lazygit `E` -> `zellij edit` (`lazygit/config.yml:16-23`); broot
   `e`/`vd`/`pb*` verbs (`verbs.hjson`).

## Side finding (out of scope, worth a test assertion)

cozy's `docker-files/nushell-autoload/hooks-config.nu` is overwritten at
bootstrap Step 4 by the dotfiles version, so the docker-files copy's PWD hook is
dead code. A test should assert the dotfiles version is the one in effect.

# Proposed harness shape (Nushell)

Playwright-for-terminals. Verbs: `e2e start` (create background session +
attach sized PTY client), `e2e type`/`key`/`run-cmd` (input), `e2e screen`/
`wait-text` (rendered assertions), `e2e panes`/`wait-exit` (clientless state
assertions), `e2e stop` (kill client + session). Full sketch captured in the
research; decide zjctl-vs-`script` first.

# Next

- [ ] Decide: adopt/embed zjctl, or build the `script`-PTY harness from scratch.
- [ ] Build the harness CLI and pick where it lives (sibling module? in dotfiles?).
- [ ] Write the first e2e test against target #1 (create-todo delete-on-unmodified).
