---
status: 'in_progress'
created: '20260528-172203 #yyyyMMdd-hhmmss'
updated: '20260529-221142 #yyyyMMdd-hhmmss'
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

## Scope — two layers, only one is automated here

`zellij action send-keys`/`write` deliver bytes to the **program inside the
pane** (its PTY), *not* to zellij's keybinding layer — that interception happens
at the client's input stream, before actions exist. This splits the surface:

- **Layer 1 — zellij's own keybind chords** (`config.kdl`: `Super e`,
  `Super Alt l`, mode switches). NOT triggerable via `zellij action`; pressing
  them programmatically needs key bytes injected into a *client's* input stream
  (a controlled PTY we own). **Out of scope for this task.** Mainly breaks via
  the `cozy ln` Super->Alt rewrite (`swap-zellij-super.nu`). Cover later with a
  short **manual-testing protocol**.
- **Layer 2 — everything that is a program reading the pane's stdin** (the nu
  helpers and the TUIs' own shortcuts). Drivable via `send-keys`/`write-chars`
  because those write to the pane PTY. **This is where the real logic and bug
  risk live, and it is what we test now.** We invoke the command directly (e.g.
  `zellij action new-pane -- todo-hx`) rather than via its `Super`-chord.

## In-scope targets (Layer 2), prioritized

1. **`create-todo` / `todo-hx`** (`todo.nu:25-63`). Run the command in a pane,
   drive helix via send-keys; assert the new `todo/*.md` is created, then
   deleted-on-unmodified-quit (and the `todo/` folder too if just created), and
   persisted after an edit. Signature flow; the auto-delete is invisible to any
   non-TTY test.
2. **`lstd`** (`todo.nu:4-23`). fzf picker (a pane program -> drivable): type
   query, `ctrl-e`, Enter; assert a `zellij edit` pane spawns for the
   highlighted file + pbcopy OSC52 side effect.
3. **`lazygit-helix.nu`**. Set up a helix pane, run the script; assert the
   Esc-before / `:reload-all`-after pane-targeting (`list-panes`-based logic) is
   correct. Pane-id dependent, fragile.
4. **`broot-paste.nu`**. Tiled + floating panes; drive broot; assert the chosen
   path lands at the originally-focused *tiled* pane's cursor (same tab).
5. **PWD tab auto-rename + `·N` dedup** (`hooks-config.nu:19-48`). Cleanest, no
   TUI: `cd` in a pane, assert via `query-tab-names`/`list-tabs`. Runs on every
   `cd`.
6. **Nushell REPL keybinds** (`Ctrl F`/`Alt F`/`Ctrl T`, `config.nu`) — these
   are *reedline's* keybinds, read from the pane PTY -> `send-keys` triggers
   them. (Distinct from Layer 1: reedline is the pane program, not zellij.)
7. **Helix space-menu nu-pipeline ops**; **lazygit `E` -> `zellij edit`**
   (`lazygit/config.yml:16-23`); **broot `e`/`vd`/`pb*` verbs**
   (`verbs.hjson`) — program-level shortcuts, drivable.

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
