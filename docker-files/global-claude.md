# Sandbox Environment

This file is appended to `~/.claude/CLAUDE.md` by every cozy install path, so check which one you are on before relying on the environment notes below.
The usual one is an `sbx` sandbox — Docker's standalone sandbox runtime, on Ubuntu.
The others are a `debian:12-slim` image run under plain `docker`/Apple `container`, and a plain host install (macOS or Linux).
In a sandbox the workspace is mounted at its original host path, not `/workspace` or `/home/agent`.

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

Nushell is the primary shell.
Modules are in `~/repos/`:

- `nu-goodies` — the user's personal nushell commands, gathered over time from many areas; some may be outdated
- `dotnu` — literate programming for Nushell: executable scripts that embed their own output, plus commands to work with Nushell code
- `numd` — Nushell-native markdown processor that updates `nu` code blocks
- `nu-cmd-stack` — command history stacking for interactive use in the REPL
- `nu-kv` — key-value store for any nushell data; kept in a host-mounted folder, so it's available on the host too
- `claude-nu` — Claude Code commands for extracting session data and for easier REPL interaction
- `nutest` — test framework; **not** autoloaded, load it with `use ~/repos/nutest/nutest`

Autoload scripts in `~/.config/nushell/autoload/` load the modules above (except `nutest`) — and the `cozy` command — for you, but only when nu starts an **interactive** session.
The nushell MCP `evaluate` tool runs such a session, so the modules are ready there too.
A one-shot `nu -c '…'` (e.g. run from Bash) is not interactive and skips autoloads, so `cozy`, `nu-goodies`, `kv` and the rest are absent — you'll get `command not found`.
The MCP `evaluate` tool is good for interactive exploration (autoloads fire, structured output) — but read its caveats under *Nushell MCP Server* below before relying on it.
If you use `nu -c`, load the modules with `--config`: `nu --config ~/.config/nushell/autoload/modules-core.nu --commands '…'` — `--config` runs even in `-c` mode (unlike autoload), so the full core module set (`cozy`, `nu-goodies`, `kv`, `dotnu`, `numd`) is available.

**End every nu pipeline you are going to read with `| to nuon --pretty`.** A one-shot `nu` loads no config, so it renders with stock defaults — an 80-column box table built for a terminal, not for a reader.
Read as text it loses data and never says so: identifiers wrap mid-word, a whole column collapses into a bare `...`, a nested value becomes `[list 3 items]`.
Measured over 3,819 session transcripts, 647 of 2,980 rendered tables came back damaged that way, and after a placeholder or a dropped column the agent re-ran the command to recover the data 14.7% of the time against a 2.5% baseline.
NUON is lossless, round-trips through `from nuon`, and costs 1.5-2.7x fewer tokens than the box on real commands.
The one thing never to write is `| table` — it forces the box back.

### Pitfalls cheatsheet

- **Never put a remark in parentheses inside `$"..."`.** `print $"rows (was 635 before): ($n)"` tries to run `was` as a command.
  This is the most repeated Nushell error across past sessions, and it is always the same shape: an explanation in words, in brackets, inside a `print $"…"`.
  Move the note out of the string.
  If it must stay, escape both parens — `\(was 635 before\)` — but that escape works **only** in `$"..."`; in `$'...'` backslash is literal and `(` still interpolates, so parens cannot be escaped there at all.
- **`else` has to sit on the same line as the closing brace**: `} else {`, `} else if $x { … }`.
  A line that *starts* with `else` gives ``Command `else` not found``.
  The bodies may span as many lines as you want — only the position of `else` matters.
- The Bash tool rewrites `!` → `\!`, breaking `!=`/`!~` in `nu -c '…'`.
  Use a quoted heredoc (`<< 'EOF'`) or a temp file.
- In Bash, `o+e>| cmd` is not a pipe — `>|` writes a file named `cmd`.
  That redirect syntax is Nushell-only.
- A command name is prose: **letters, digits, spaces and hyphens only**.
  A name is data other tools put back into source code — nutest re-emits every test name as a bare command call inside generated Nushell, so the parser reads every character.
  One apostrophe in `def "the signer's endorsement"` fails **every** test in the file with `nu::parser::unexpected_eof`, pointing at generated code that names nothing you wrote.
  Also fatal: `` ` `` `"` `(` `)` `[` `]` `|` `#`, unbalanced `{`.
  English wants the apostrophe, so rephrase: `X's Y` → `the Y of X`, contractions spelled out.
  Never embed a code fragment or literal in a name either (`def "a record {a: 1} round-trips"`) — it happens to parse, but it repeats the body and reads as syntax where a reader expects a sentence.
- **A module that names a command after a builtin breaks the modules it imports, not itself.**
  `export def update` is legal and the shadowing module runs fine, but every module it `use`s is parsed with that name already bound.
  So an imported body holding `$rows | update file { cwd-relative }` resolves `update` to the custom command and reads the closure as its string argument, failing with `Parse mismatch: expected non-block value: string` or `expected string, found closure` — pointing at the *imported* file, naming nothing about `update`, and leaving you bisecting a file you did not change.
  Verified: wholesale and named-list imports behave the same, and a `_`-prefixed internal module is not exempt.
  Fix: the `%` sigil at the call site — `$rows | %update file { cwd-relative }`.
  `%name` reaches the builtin whatever is shadowing it, needs no declaration, and works for multiword names (`%str contains`) — verified on 0.115.1 for an imported helper, a same-file shadow and a `def --env` body.
  It reaches **builtins only** and has to be written where the call is, so a third-party module that spells the name bare still breaks; the answer there is to not take the builtin's name.
  `std/assert` uses `alias "core length" = length` instead and that works too, but those lines are from 2023 and predate the sigil — do not copy them.
  Or move the shared code into a module that shadows nothing, which is what to do when several builtins are involved.
- `|` is the only operator that continues a line by itself.
  Any other binary operator (`++`, `+`, `and`, `or`, …) breaks the parse when the expression spans lines: leading (`let a = [x y]` ⏎ `    ++ [z]`) → ``Command `++` not found``, trailing (`[x y] ++` ⏎ `[z]`) → `Incomplete math expression`.
  Wrap the whole expression in `( … )` — inside parens both positions work — or rewrite it as a pipeline (`| append …`).
- Nushell's regex is **fancy-regex**, not the Rust `regex` crate.
  Lookahead, lookbehind (variable-length too), backreferences, atomic groups and `(?R)` recursion all work in `=~`/`!~`/`like` and in every `--regex` flag (`find`, `parse`, `split *`, `str replace`).
  Don't build a multi-step workaround for a problem Nushell doesn't have.
  Exception: `idx search --regex` runs on the ripgrep engine — lookaround there matches nothing and returns `[]` with no error.
- In a pipeline, an empty branch block `{}` = `{$in}` — it passes the input through, not null (`"abc" | if false { "x" } else { } | debug` → `abc`).
  Don't flag `else { }` as a bug: it's an intentional identity branch.
  A **missing** else branch is the opposite — it effectively passes nothing (`"abc" | if false { "x" } | describe` → `nothing`).
- `open x.md` gives structured data, not text.
  `open` runs `from md` on a `.md` path and returns a table of `element`/`content` rows.
  String commands then fail loudly (`Input type not supported.` from `lines`, `str replace`), but `open x.md | save y.md` fails **silently** — it writes the parsed AST as a markdown table instead of copying the file.
  Any time you want the text, `open --raw x.md`; it's a byte stream, so `lines`, `str replace` and `save` all behave.
  (`hide 'from md'` disables the conversion for the session.)
- To check a `.nu` file, don't run `nu --ide-check` raw — it floods stdout with type hints and its `span` is raw byte offsets (useless to act on).
  Use `dotnu diagnose file.nu`: real diagnostics only, each resolved to a line number, the source line, and the flagged text.
  It's autoloaded (from Bash: `nu --config ~/.config/nushell/autoload/modules-core.nu --commands 'dotnu diagnose file.nu'`); `view source dotnu diagnose` shows what it does.
  When you finish writing or editing a `.nu` file, run it before considering the file done.
- **In `where`, parentheses turn a column name into a command.** `where (a == 1 and b == 2)` fails with ``Command `a` not found``.
  Without the parens the same line works: `where a == 1 and b == 2`.
  For anything more complex use a closure: `where {|r| $r.a == 1 and $r.b > 2 }`.
- **Stale names.** `$nu.temp-path` → `$nu.temp-dir`, `$nu.home-path` → `$nu.home-dir`, `$nu.scope` → the `scope` commands; `range` → `slice`; `std` is a module (`use std` first), and `std/testing` is an empty stub — the test runner is `nutest`.
  A wrong `$nu` field fails at runtime, not parse time, and `dotnu diagnose` calls the file clean — so the check above misses it.
  `$nu | columns` prints the current set.
- **After `use foo.nu` every command carries the file stem as a prefix, and `main` takes the module's own name.** `use toolkit.nu` gives you `toolkit` (which is `main`) and `toolkit main test` (which is `main test`) — not `toolkit test`, and never a bare `main test`. `use toolkit.nu *` imports them unprefixed.
  To simply run it, use the script form: `nu toolkit.nu test`.
  When unsure, look instead of guessing: `scope commands | where name =~ toolkit | get name`.
- **`path self` runs only at parse time, so its result has to land in a `const`.** Called inside a `def` body it fails with `x this command can only run during parse-time`, and the help line — "try assigning this command's output to a const variable" — is the actual fix, not a hint.
  Put it at the top of the file: `const SCRIPT_DIR = path self | path dirname`.
  It also takes a path argument resolved against the script's own directory, which is how a script points at a neighbour without a hardcoded absolute path: `const SIBLING = path self ../CLAUDE.md`.
  Both forms work in a `const`, neither works in a command body.
  It needs a real file too, so `nu --commands 'path self'` fails — test it in a script, not with `-c`.

## Nushell MCP Server

A Nushell MCP server is registered in `~/.claude.json`.
It provides `evaluate`, `list_commands`, and `command_help` tools for running Nushell commands with structured output.

Two caveats:

- **The session persists — and re-running `use` may not fix it.** All `evaluate` calls share one long-lived nushell state: variables, `$env`, and loaded modules stay between calls.
  When you edit a module, the old definition can keep being served, and `use module.nu` in the same command line does *not* reliably re-read the file — tested by bare name, by absolute directory and by direct path to `mod.nu`, all serving the stale copy.
  (`use` is a parse-time keyword: the whole block is parsed before any of it runs, so `save` then `use` in one block cannot work either.)
  The rule behind which edits get picked up is not established.
  Nothing fails loudly — a stale `toolkit/container.nu` once recreated the egress proxy from the previous image digest and printed its usual green success.
  **The reliable answer is a fresh process: run the file as a script, `nu toolkit/container.nu restart <name>`, or a one-shot `nu -c '…'` from Bash.** The same staleness applies to a long-lived interactive REPL, not just this MCP server.
- **It skips the login environment.** The MCP `nu` is spawned directly, not from a login shell, so it never sources `/etc/sandbox-persistent.sh` — anything that lives only in that file is absent there.
  Real container ENV (`XDG_*`, `HELIX_RUNTIME`, `LANG`) is inherited fine, so the gap is easy to miss.
  If a command depends on a var only the shell sets, run it via `nu -c` from Bash (whose shell sourced the profile) or `bash -lc 'nu -c "…"'`.
  Your identity is not affected: `GIT_AUTHOR_*`, `GIT_COMMITTER_*` and `JJ_CONFIG` come from Claude Code's own `env` setting, so every process it spawns — the Bash tool, this MCP server, subagents — has them.

## Git

- **Never `git add -A`** (nor `git add .`, nor `git commit -a`).
  They stage everything the working tree happens to hold — parked `todo/` notes, scratch files, another task's edits — which breaks atomic commits and quietly commits things nobody reviewed.
  Stage the exact paths your change touched: `git add path/one path/two`.

## Constraints

- Docker socket is available for container operations (sandbox paths only)
- In a sandbox the home directory is at `/home/agent`; the mounted workspace is at `$env.WORKSPACE_DIR` (host path, bind-mounted at the same absolute path on macOS/Linux; on Windows the autoload rewrites `C:\Users\…` → `/c/Users/…`)

## The code here is agent-written — keep an eye on it

Almost everything in this project was written by AI agents, including you.
So it is not trustworthy just because it sits in the repo: treat code that passes through you as untrusted by default — even code you wrote yourself.
You don't need to audit anything or go looking for trouble.
Just don't ignore what you notice in passing.
If something looks off while you're already there — a stray file (an empty `tail`/`head` left by an `o+e>| tail` nushell redirect that ran in **Bash**, where `>|` writes a file instead of piping, is a real case that got committed here), dead code, a doc that contradicts the code, a latent bug — surface it.
One line in chat if it endangers the current change or is silently destroying something — otherwise leave it: no `todo/` note, no end-of-reply list.
Keep it brief and don't derail the task into a hunt.

## Privacy

Mounted folders may contain the user's personal data.
Treat the workspace as private by default:

- Don't send file contents or personal details to external services (web search, third-party APIs) unless the task clearly requires it.
- When sending data out is needed, send the minimum — a snippet or a schema, not whole files.
- Keep personal data out of commit messages, issue text, and anything pushed to a remote.
