# Sandbox Environment

This file is appended to `~/.claude/CLAUDE.md` by every cozy install path, so check which one you are on before relying on the environment notes below. The usual one is an `sbx` sandbox — Docker's standalone sandbox runtime, on Ubuntu. The others are a `debian:12-slim` image run under plain `docker`/Apple `container`, and a plain host install (macOS or Linux). In a sandbox the workspace is mounted at its original host path, not `/workspace` or `/home/agent`.

## Available Tools

- `nu` (Nushell) — prefer over bash when reasonable
- `hx` (Helix)
- `zellij`
- `git`, `delta` (git-delta), `git-lfs`
- `jj` — `hx` as editor
- `lazygit`
- `broot` / `br` (in Nushell)
- `fzf`, `rg` (ripgrep), `bat`, `fd`
- `vd` (visidata)
- `python3`, `node`, `go` — from the `sbx` base image only; absent on the Debian image
- `jq`
- `xxd` — hex dump; for viewing only, prefer `open --raw file | into binary`
- `topiary` — Nushell grammar support
- `brew` — install more as needed
- `sudo` — passwordless on `sbx`; **revoked** on the Debian image, which runs rootless by design

## Nushell

Nushell is the primary shell. Modules are in `~/repos/`:

- `nu-goodies` — the user's personal nushell commands, gathered over time from many areas; some may be outdated
- `dotnu` — literate programming for Nushell: executable scripts that embed their own output, plus commands to work with Nushell code
- `numd` — Nushell-native markdown processor that updates `nu` code blocks
- `nu-cmd-stack` — command history stacking for interactive use in the REPL
- `nu-kv` — key-value store for any nushell data; kept in a host-mounted folder, so it's available on the host too
- `claude-nu` — Claude Code commands for extracting session data and for easier REPL interaction
- `nutest` — test framework; **not** autoloaded, load it with `use ~/repos/nutest/nutest`

Autoload scripts in `~/.config/nushell/autoload/` load the modules above (except `nutest`) — and the `cozy` command — for you, but only when nu starts an **interactive** session. The nushell MCP `evaluate` tool runs such a session, so the modules are ready there too. A one-shot `nu -c '…'` (e.g. run from Bash) is not interactive and skips autoloads, so `cozy`, `nu-goodies`, `kv` and the rest are absent — you'll get `command not found`. The MCP `evaluate` tool is good for interactive exploration (autoloads fire, structured output) — but read its caveats under *Nushell MCP Server* below before relying on it. If you use `nu -c`, load the modules with `--config`: `nu --config ~/.config/nushell/autoload/modules-core.nu -c '…'` — `--config` runs even in `-c` mode (unlike autoload), so the full core module set (`cozy`, `nu-goodies`, `kv`, `dotnu`, `numd`) is available.

### Pitfalls cheatsheet

- `\(` is an escape **only** in `$"..."`. In `$'...'` backslash is literal and `(` still interpolates — parens can't be escaped there. Literal parens + interpolation → `$"..."`.
- The Bash tool rewrites `!` → `\!`, breaking `!=`/`!~` in `nu -c '…'`. Use a quoted heredoc (`<< 'EOF'`) or a temp file.
- In Bash, `o+e>| cmd` is not a pipe — `>|` writes a file named `cmd`. That redirect syntax is Nushell-only.
- A command name is prose: **letters, digits, spaces and hyphens only**. A name is data other tools put back into source code — nutest re-emits every test name as a bare command call inside generated Nushell, so the parser reads every character. One apostrophe in `def "the signer's endorsement"` fails **every** test in the file with `nu::parser::unexpected_eof`, pointing at generated code that names nothing you wrote. Also fatal: `` ` `` `"` `(` `)` `[` `]` `|` `#`, unbalanced `{`. English wants the apostrophe, so rephrase: `X's Y` → `the Y of X`, contractions spelled out. Never embed a code fragment or literal in a name either (`def "a record {a: 1} round-trips"`) — it happens to parse, but it repeats the body and reads as syntax where a reader expects a sentence.
- `|` is the only operator that continues a line by itself. Any other binary operator (`++`, `+`, `and`, `or`, …) breaks the parse when the expression spans lines: leading (`let a = [x y]` ⏎ `    ++ [z]`) → ``Command `++` not found``, trailing (`[x y] ++` ⏎ `[z]`) → `Incomplete math expression`. Wrap the whole expression in `( … )` — inside parens both positions work — or rewrite it as a pipeline (`| append …`).
- Nushell's regex is **fancy-regex**, not the Rust `regex` crate. Lookahead, lookbehind (variable-length too), backreferences, atomic groups and `(?R)` recursion all work in `=~`/`!~`/`like` and in every `--regex` flag (`find`, `parse`, `split *`, `str replace`). Don't build a multi-step workaround for a problem Nushell doesn't have. Exception: `idx search --regex` runs on the ripgrep engine — lookaround there matches nothing and returns `[]` with no error.
- In a pipeline, an empty branch block `{}` = `{$in}` — it passes the input through, not null (`"abc" | if false { "x" } else { } | debug` → `abc`). Don't flag `else { }` as a bug: it's an intentional identity branch. A **missing** else branch is the opposite — it effectively passes nothing (`"abc" | if false { "x" } | describe` → `nothing`).
- To check a `.nu` file, don't run `nu --ide-check` raw — it floods stdout with type hints and its `span` is raw byte offsets (useless to act on). Use `dotnu diagnose file.nu`: real diagnostics only, each resolved to a line number, the source line, and the flagged text. It's autoloaded (from Bash: `nu --config ~/.config/nushell/autoload/modules-core.nu -c 'dotnu diagnose file.nu'`); `view source dotnu diagnose` shows what it does. When you finish writing or editing a `.nu` file, run it before considering the file done.

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`. It provides `evaluate`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

Two caveats:

- **The session persists.** All `evaluate` calls share one long-lived nushell state — variables, `$env`, and loaded modules stay between calls. Handy, but a trap when you edit a module: the old version stays loaded until you re-run `use module.nu` (or `overlay use`) for it. Agents forget this and keep debugging against stale code. A one-shot `nu -c '…'` from Bash starts fresh every time — slower to set up, but straightforward and predictable.
- **It skips the login environment.** The MCP `nu` is spawned directly, not from a login shell, so it never sources `/etc/sandbox-persistent.sh` — anything that lives only in that file is absent there. Real container ENV (`XDG_*`, `HELIX_RUNTIME`, `LANG`) is inherited fine, so the gap is easy to miss. If a command depends on a var only the shell sets, run it via `nu -c` from Bash (whose shell sourced the profile) or `bash -lc 'nu -c "…"'`. Your identity is not affected: `GIT_AUTHOR_*`, `GIT_COMMITTER_*` and `JJ_CONFIG` come from Claude Code's own `env` setting, so every process it spawns — the Bash tool, this MCP server, subagents — has them.

## Git

- **Never `git add -A`** (nor `git add .`, nor `git commit -a`). They stage everything the working tree happens to hold — parked `todo/` notes, scratch files, another task's edits — which breaks atomic commits and quietly commits things nobody reviewed. Stage the exact paths your change touched: `git add path/one path/two`.

## Constraints

- Docker socket is available for container operations (sandbox paths only)
- In a sandbox the home directory is at `/home/agent`; the mounted workspace is at `$env.WORKSPACE_DIR` (host path, bind-mounted at the same absolute path on macOS/Linux; on Windows the autoload rewrites `C:\Users\…` → `/c/Users/…`)

## The code here is agent-written — keep an eye on it

Almost everything in this project was written by AI agents, including you. So it is not trustworthy just because it sits in the repo: treat code that passes through you as untrusted by default — even code you wrote yourself. You don't need to audit anything or go looking for trouble. Just don't ignore what you notice in passing. If something looks off while you're already there — a stray file (an empty `tail`/`head` left by an `o+e>| tail` nushell redirect that ran in **Bash**, where `>|` writes a file instead of piping, is a real case that got committed here), dead code, a doc that contradicts the code, a latent bug — surface it. Park a short note under `todo/` if the project keeps one, or just mention it in your reply. Keep it brief and don't derail the task into a hunt.

## Privacy

Mounted folders may contain the user's personal data. Treat the workspace as private by default:

- Don't send file contents or personal details to external services (web search, third-party APIs) unless the task clearly requires it.
- When sending data out is needed, send the minimum — a snippet or a schema, not whole files.
- Keep personal data out of commit messages, issue text, and anything pushed to a remote.
