# cozy zellij e2e harness

End-to-end tests that drive **real zellij panes** to exercise cozy's interactive
command flows — the ones no plain script can verify because they need a TTY and a
live render (helix auto-delete, fzf pickers, the PWD tab-rename hook).

This is test infrastructure: not vendored, not shipped in the image.

Full design rationale (the #4508 constraint, the verified zellij 0.44.3 surface,
the prioritized target list) lives in
`../../todo/20260528-172203-zellij-interactive.md`. Read it before extending.

## Run

```sh
nu toolkit.nu test                  # whole suite (serial — see below)
nu toolkit.nu test --suite lstd     # one suite by file-stem regex
nu toolkit.nu test --match basename # by test-name regex
nu toolkit.nu test --fail           # exit non-zero on failure (CI)
```

`toolkit.nu` forces **serial execution** (`--strategy { threads: 1 }`). Each test
drives a real zellij session with a PTY client and live TUIs; running them
concurrently makes sessions contend for CPU, slowing renders past the poll
timeouts — a nondeterministic flake. Serial is the correct model here. If you
invoke `nutest run-tests` directly, pass `--strategy { threads: 1 }` yourself.

Tests are written with nutest's **description-tag** attributes (`# [test]`,
`# [before-each]`, `# [after-each]`, `# [ignore]`) rather than `@test`: the
vendored nutest predates nu 0.113's `attr`-command requirement, so `@test` fails
to parse but the `[tag]` form discovers correctly.

## The #4508 PTY-client requirement

zellij 0.44.3 renders **nothing** into a pane's grid and applies **no input**
unless a real PTY client is attached to the session (zellij-org/zellij#4508; the
official docs claim otherwise — wrong for 0.44.3). A `--create-background`
session tracks command exit codes headlessly, but `dump-screen` returns empty and
keystrokes never render until a client attaches.

`harness.nu start` therefore: creates the background session, then
`job spawn { ^script -qec "stty rows R cols C; zellij attach NAME" /dev/null }`
to attach a sized throwaway PTY client, then polls `list-clients` until the client
lands before returning. `stop` kills that job and deletes the session. Terminal
size is pinned via `stty` so renders are deterministic (headless default 50x49 is
not). Every test owns a uniquely-named session and never touches the user's live
session.

## Harness verbs (`harness.nu`)

| verb | channel | purpose |
|---|---|---|
| `start NAME` / `stop CTX` | — | session + PTY-client lifecycle (returns/takes `{session, job}`) |
| `run-cmd CTX ...cmd` / `run-nu CTX` | — | spawn a pane; `run-nu` waits for the nu prompt |
| `type` / `key` / `focus` | input | `write-chars` / `send-keys` / `focus-pane-id` (optional `--pane`) |
| `screen` / `wait-text` | **rendered** | `dump-screen` (needs the PTY client); `wait-text` polls until a regex matches |
| `panes` / `wait-exit` / `wait-pane-command` | **clientless state** | `list-panes --json`; poll a pane until exited / its `pane_command` matches |
| `tab-names` / `wait-tab` / `new-tab` | clientless state | `query-tab-names`; poll until a tab name appears; open a tab |

Two assertion channels, per #4508: clientless state (`list-panes --json`,
`query-tab-names`) works without rendering and is the most robust; rendered text
(`dump-screen`) needs the attached client and is for TUI assertions.

**TUI readiness gotcha:** gate input on a TUI's *rendered* signal, not on
`pane_command`. `pane_command` flips to e.g. `hx` the instant the process spawns,
before it has entered raw mode and drawn its UI, so early keystrokes get dropped.
The create-todo suite waits for helix's `NOR` status line before sending `:q`.

## Layer 1 vs Layer 2 (what is and isn't testable here)

`zellij action send-keys`/`write` deliver bytes to the **program inside the pane**
(its PTY), not to zellij's keybinding layer — that interception happens at the
client's input stream, before actions exist.

- **Layer 2** (tested here): everything that is a program reading the pane's stdin
  — the nu helpers and the TUIs' own shortcuts. We invoke the command directly
  (e.g. spawn a pane running `create-todo`), never via its `Super`-chord.
- **Layer 1** (out of scope): zellij's own keybind chords (`Super e`, mode
  switches). Not triggerable via `zellij action`; needs key bytes injected into a
  client's input stream. Cover later with a manual-testing protocol.

See the todo for the full split.

## Current targets

| target | suite | status |
|---|---|---|
| #1 create-todo / todo-hx | `suites/create-todo_test.nu` | passing |
| #2 lstd (fzf picker) | `suites/lstd_test.nu` | passing (+1 ignored bug, +OSC-52 limit) |
| #5 PWD tab-rename + ·N dedup | `suites/tab-rename_test.nu` | passing |

### Known limitations / findings

- **lstd status filter is broken on nu 0.113.** `lstd` does `open $i.name` on a
  `.md` file, but nu now parses markdown into a *table*, so the `split row` errors
  on every row, `try {...} | default "draft"` swallows it, and the
  completed/rejected filter never hides anything (fzf items even become nu error
  strings). The intended-contract test is `# [ignore]`-marked in
  `lstd_test.nu` and documents the fix (`open --raw`). Not fixed here — it is the
  command under test, not harness code.
- **OSC-52 clipboard is not observable.** `pbcopy` emits an OSC-52 escape to
  `/dev/tty`; zellij consumes it, it never renders and leaves no filesystem trace.
  The lstd test asserts the selection/edit-pane path instead.
