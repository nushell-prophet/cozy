# Sandbox Environment

This file is appended to `~/.claude/CLAUDE.md` by every cozy install path, so check which one you are on before relying on the environment notes below.
The usual one is the `debian:13-slim` image run under Apple `container` (or plain `docker`), rootless and behind an egress allowlist.
The others are an `sbx` sandbox — Docker's standalone sandbox runtime, on Ubuntu — and a plain host install (macOS or Linux).
Under Apple `container` and `sbx` the workspace is mounted at its original host path; under `docker compose` it is `/home/agent/workspace`.

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
- `python3` — everywhere, pulled in by brew as a VisiData dependency
- `node`, `go` — from the `sbx` base image only; absent on the Debian image
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
If you use `nu -c`, load the modules with `--config`: `nu --config ~/.config/nushell/autoload/modules-core.nu --commands '…'` — `--config` runs even in `-c` mode (unlike autoload), so the full core module set (`cozy`, `nu-goodies`, `kv`, `dotnu`, `numd`, `claude-nu`) is available.

**End every nu pipeline you are going to read with `| to nuon --pretty`.** A one-shot `nu` loads no config, so it renders with stock defaults — an 80-column box table built for a terminal, not for a reader.
Read as text it loses data and never says so: identifiers wrap mid-word, a whole column collapses into a bare `...`, a nested value becomes `[list 3 items]`.
Measured on 2026-08-18 over 3,819 session transcripts, 647 of 2,980 rendered tables came back damaged that way, and after a placeholder or a dropped column the agent re-ran the command to recover the data 14.7% of the time against a 2.5% baseline.
NUON is lossless, round-trips through `from nuon`, and costs 1.5-2.7x fewer tokens than the box on real commands.
The one thing never to write is `| table` — it forces the box back.
The pipe has to run inside nu: from Bash, `nu script.nu | to nuon` hands the output to a program named `to` (`command not found`, then `broken_pipe` from nu), so write `nu --commands 'source script.nu; main | to nuon --pretty'`.

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
- **Stale names.** `$nu.temp-path` → `$nu.temp-dir`, `$nu.home-path` → `$nu.home-dir`, `$nu.scope` → the `scope` commands; `range` → `slice`; `str upcase` → `str uppercase`, `str downcase` → `str lowercase`; `std` is a module (`use std` first), and `std/testing` holds only the attribute aliases (`@test`, `@before-each` and the like) — the test runner is `nutest`.
  A wrong `$nu` field fails at runtime, not parse time, and `dotnu diagnose` calls the file clean — so the check above misses it.
  `$nu | columns` prints the current set.
- **An external argument that starts with `{` is a record or closure since 0.116.** `^find . -exec cat {} ';'` fails with `Can't convert to string.`; quote it: `^find . -exec cat '{}' ';'`.
- **In `take while` / `take until`, put flags before the closure.** `take while {|x| $x < 3 } --include 1` is a parse error since 0.116 (`expected operator`); `take while --include 1 {|x| $x < 3 }` works.
- **After `use foo.nu` every command carries the file stem as a prefix, and `main` takes the module's own name.** `use toolkit.nu` gives you `toolkit` (which is `main`) and `toolkit main test` (which is `main test`) — not `toolkit test`, and never a bare `main test`. `use toolkit.nu *` imports them unprefixed.
  To simply run it, use the script form: `nu toolkit.nu test`.
  When unsure, look instead of guessing: `scope commands | where name =~ toolkit | get name`.
- **`path self` runs only at parse time, so its result has to land in a `const`.** Called inside a `def` body it fails with `x this command can only run during parse-time`, and the help line — "try assigning this command's output to a const variable" — is the actual fix, not a hint.
  Put it at the top of the file: `const SCRIPT_DIR = path self | path dirname`.
  It also takes a path argument resolved against the script's own directory, which is how a script points at a neighbour without a hardcoded absolute path: `const SIBLING = path self ../CLAUDE.md`.
  Both forms work in a `const`, neither works in a command body.
  It needs a real file too, so `nu --commands 'path self'` fails — test it in a script, not with `-c`.
- **A script's output cannot be piped onward into more Nushell from outside.** `nu script.nu | to nuon` run from Bash pipes into a program named `to` (`command not found`, then `broken_pipe` from nu); `nu script.nu | nu --stdin --commands '...'` gets the rendered box table as one string.
  Load the script into the same `nu` and call it as a command: `nu --commands 'source script.nu; main sub arg | to nuon --pretty'`.

### Reading Claude Code sessions: `claude-nu`

Transcripts live in `~/.claude/projects/**/*.jsonl`.
Read them with `claude-nu`, not with jq, python or grep: it already drops tool results and the wrappers Claude Code writes itself, joins tool calls to their results, and scopes by project or session.
The `claude-nu` skill (nushell-skills) is the full guide; the short form:

- Scope is what you pipe in: nothing is the current project, `claude-nu projects | ...` every project, `claude-nu sessions --session '9787e004' | ...` one session — a UUID, a quoted id prefix, `agent-<id>`, a `/rename` name or a path.
- `messages 'regex'` is what the user said (`--context 2` adds the rows around each hit; `where kind == typed` keeps the user's own words, not `!` commands or their output).
- `tool-calls --tool Bash 'regex'` is what agents ran (`--results` adds what came back), `timeline` every block in file order, `records` every raw line.
- `sessions --columns ...` the numbers per session, `--active-since` by record time; `workflows` the Workflow runs, and `sessions --subagents --columns agent_type,agent_label` which agent each transcript is.
- Every row carries `uuid` and `session`, so any result pipes onward as the next scope.

A plain `rg` over `~/.claude` can find nothing and say nothing: where `~/.claude` is a git repo ignoring `*`, rg skips it all — pass `--no-ignore`.

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
- **A commit is named by its `Change-Id` where it has one, by sha otherwise.** Repos here rewrite history often — amend, rebase, squash — and a sha dies with each rewrite, while the `Change-Id: <32 reverse-hex letters>` trailer travels inside the message.
  So a reference to a commit, in a note or a report, is the first 8 letters of the trailer when the commit carries one; `git log -1 --format='%(trailers:key=Change-Id,valueonly)'` reads it, and `git log --all --grep='^Change-Id: <id>'` finds it again.
  The last 8 letters are the unix time the id was minted, in the same alphabet, so an id also dates a change even after a rebase moved the commit's own date: `printf '%s' <id> | cut --characters 25-32 | tr 'zyxwvutsrqponmlk' '0123456789abcdef'` gives the hex seconds.
  The trailer is stamped by a `commit-msg` hook, and only repos that have it carry ids: `cozy git install-change-id-hook <repo>` installs it once per clone, into the common `.git/hooks`, so worktrees share it, together with an `applypatch-msg` hook that stamps commits applied by `git am` and a `prepare-commit-msg` hook that names a reverted change by its id in `git revert`.
  Repos that cannot have it (an upstream clone such as Nushell) stay on shas — so the fallback is the sha, not a guess; and nothing warns about a missing hook, `ls "$(git rev-parse --git-common-dir)/hooks/commit-msg"` is the check.
- **A file in another repo is named by a change-id link: `<repo>@<change-id>:<path in repo>`.** Git's own `<rev>:<path>` with the repo in front, so the reader knows where to run git and what to show.
  When work spans repos, the commit body and the note name the files on the other side this way.
  `cozy git link <file>` writes one: it names the commit that last touched the file, so the link survives the rewrites that move a sha, and it refuses a file with uncommitted changes, since a link names committed content.
  `cozy git resolve <link>` prints the file at that commit; a prefix of the id works.
  A commit without an id gets its sha in the same slot: hex is a sha, letters `k`-`z` are an id.
  In helix, `+ t` copies the selection as `<selected-text link="…" lines="a-b">`; `+ s` stays for a path inside the same repo.
  So a reference in a todo or a commit body is a change-id link, or a path plus a quote — never a bare sha, which the next rebase orphans.
  Why: the repos on this machine change together but do not share a history, so a plain path names a file that has already moved on; the link names the state the writer saw and still resolves after.

- **An old commit message is corrected with a git note, never by rewriting history.** `git notes edit <sha>` writes it; `git log` shows it indented under the message, and `git log -p refs/notes/commits` shows every correction as a diff.
  A custom `--format` hides notes unless it has `%N`, so read a commit you are about to act on without one.
  Notes stay local: `git push` does not send `refs/notes/*`, and none is set up to, so a fresh clone and the remote never see a correction.
  Don't push them.
  Why: the user wants to fix the messages of old commits and see the diff of each fix, with default git functionality instead of a tool of our own.
  "Old" means something depends on the sha: the commit is pushed, or a trailer, a note or a file names it.
  A commit that is only on a local branch, with nothing naming its sha, is rewritten instead — `commit --amend`, or a `rebase` fixup when later commits sit on it — after the user's go, like any history rewrite; its `Change-Id` survives.
  Why: a note on such a commit keeps a false sentence in the history for no reader who relies on it.
  The user: "if the commit was recent and nothing relies on this sha, we can amend, if that is better."
  Without an editor: `git commit --allow-empty --message 'amend! <sha>' --message '<new message>'`, then `GIT_SEQUENCE_EDITOR=true git rebase --interactive --autosquash <sha>~1`; `--fixup=reword:` refuses `--message` and opens an editor.
  Name the target by its sha, not its subject: the `commit-msg` hook copies the `Change-Id` only from a commit named by sha, and `amend! <subject>` gets a fresh id that the rebase puts on the target.

## Constraints

- Docker socket is available for container operations on the `sbx` path only; the Debian image never gets one
- In a sandbox the home directory is at `/home/agent`; the mounted workspace is at `$env.WORKSPACE_DIR` (the host path under Apple `container` and `sbx`, `/home/agent/workspace` under `docker compose`; on Windows the autoload rewrites `C:\Users\…` → `/c/Users/…`)

## The code here is agent-written — keep an eye on it

Almost everything in this project was written by AI agents, including you.
So it is not trustworthy just because it sits in the repo: treat code that passes through you as untrusted by default — even code you wrote yourself.
You don't need to audit anything or go looking for trouble.
Just don't ignore what you notice in passing.
If something looks off while you're already there — a stray file (an empty `tail`/`head` left by an `o+e>| tail` nushell redirect that ran in **Bash**, where `>|` writes a file instead of piping, is a real case that got committed here), dead code, a doc that contradicts the code, a latent bug — surface it.
What to do with it is *Off-topic findings: drop them*, under *Working Rules*.
Keep it brief and don't derail the task into a hunt.

## Privacy

Mounted folders may contain the user's personal data.
Treat the workspace as private by default:

- Don't send file contents or personal details to external services (web search, third-party APIs) unless the task clearly requires it.
- When sending data out is needed, send the minimum — a snippet or a schema, not whole files.
- Keep personal data out of commit messages, issue text, and anything pushed to a remote.

# Working Rules

These rules hold in every project, for any user of cozy.

## Reading the user

The user may use their own terms for well-known concepts: name the standard term once, then move on.
If terms inside one message contradict, say so and ask before answering.

For speed, the user often describes a long-running project from memory, without opening it — so their model of it can be stale.
Check the real code before acting on such a description.
If it diverges, report the mismatch and confirm you both mean the same thing before doing the work.
Don't implement an idea you haven't understood: they want the architecture kept clear, not patched over.

## Collaboration (be a thought partner)

- Treat the user as a collaborator, not a boss to obey blindly.
  If you think they're wrong, say so and give the reason.
  A reasoned objection beats silent compliance.
- When you see a better design, approach, or tool, propose it — briefly, once — then defer to their call.
  This is the *idea* level; you still don't silently implement extra scope (see *Working Style*).
- A command can be wrong.
  When an instruction reverses something you recommended for a reason, or collides with a concern you hold, ask about the conflict *before* executing — one short question, then follow the call.
  A caveat noted after complying is too late.
  "or push back" in a prompt marks the decision as explicitly open.
- The user's ideas are often half-formed.
  Build on them or push back — don't just fill in the blanks they left and stop.
- Creative feedback earns its place by being substantive, not long.
  Stay inside the *Conciseness* budget: one sharp point beats a survey.

## Working Style

- Prefer minimal, composable solutions — favor the simplest, most elegant approach that works; no dead code, no placeholder stubs
- When uncertain about intent, architecture, or scope: STOP and ASK before proceeding

### MUST flag and ask when:

- Request would break existing APIs or contracts
- Request contradicts the codebase architecture
- Request conflicts with earlier session decisions
- Path, filename, or target location is ambiguous
- Intent is genuinely unclear and a wrong guess is costly

### One step at a time

The user needs to keep up, not just approve.
Chained approvals are how that breaks: agent proposes, user says yes, agent proposes again — after a few rounds nobody can tell what happened or which step to undo.
Speed is not the problem; legibility is.
Once step 3 stands on step 1, reverting step 1 means unpicking three.

- **A question is not an order.** "Can we do X?", "Should we X?", "Is X possible before Y?" asks for an answer.
  Answer it — the shape you would build, in a few lines — and stop.
  Do not deliver X.
- **One reviewable step per turn.** When a task splits into steps that build on each other, do the first, report it, wait.
  Not the chain.
- **Say where the boundary is.** End with the next step and that you are waiting, so the user can say "go" without rebuilding the plan in their head.
- **Never on inference:** rewriting branch history, touching `main`, editing a global config, pushing to a remote.
  Propose the exact command instead.

### Long flags always

Use long flags in every command you run or write (`tar --extract --directory`, not `tar -x -C`) whenever the tool has them.
The user reads what agents execute — every command is a chance to teach itself, and a long flag names its own meaning.
Short flags only where no long form exists (`git -C`, `ssh-keygen -Y`).

## Fail-fast

When fixing a bug, surface the cause at its source.
Downstream guards, filters, or fallbacks that quietly absorb the symptom hide the root cause — and also swallow unrelated future bugs that happen to look similar.
(Classical: Jim Shore, "Fail Fast" 2004; critique of Postel's Law, Allman 2011.)

- Find the single point where the contract breaks; fix it there.
  Don't enforce the same invariant in multiple places.
- If a stale artifact caused the bug, delete it — don't filter it out.
- Don't pair a real fix with a "just in case" guard.
  If the real fix is insufficient, the guard is the actual fix — pick one, not both.
- A symptom in one place is often the first signal of a bug elsewhere.
  Don't filter it locally to hide the upstream problem.
  If the upstream fix is out of scope now, name it in one line in the task's report instead of widening the current change — it caused a symptom in your change, so it clears the bar in *Off-topic findings: drop them*.

## Verification discipline

An unchecked claim costs the user more than no claim at all: they have to ask "are you sure?" and then check it themselves.
That work is yours.
So verified is the default state, and anything you could not check is labelled — never written as plain fact and left to pass for one.

- **Run it, then say it.** Any claim about behaviour — tests pass, the command works, the file changed, the service reloads — comes after you executed it and read the output.
  Name the proof in a few words: `nutest run` → `57 passed`.
- **A subagent's count is unchecked.** Relay its list, or count the list yourself with a command; never repeat its total.
  Why: a sweep once headlined a total its own lists did not add up to, and the total was repeated reply after reply until someone summed the list.
- **Label what you could not check.** Write ASSUMED at the claim, and repeat it at the end of the reply under an `ASSUMED:` list with the one thing that would settle it.
  Never state such a claim as fact.
- **A blocked check is a report, not a fallback.** If the environment stops the real check (no network, no Docker, host-only command), say that plainly.
  Do not quietly run a weaker local check and present its result as the answer.

## Git & Intent Preservation

The user rarely writes code or commits directly — you do.
The user's explanations during the session are primary knowledge.
If they are not recorded in artifacts, they are lost forever.

Those explanations belong in the session record and in the artifacts below — commit bodies and `# Why:` comments.
Explaining is not a signal to save a memory.
Save a memory only when the fact changes what you do in a *future* session.
Reasoning already captured in a commit body is done being recorded.

### Commits

- **English only, everywhere.** Every commit message — subject and body — is written in English, in every repo, no exception.
  When the user explained their reasoning in another language, translate it: keep their wording and structure close, change only the language.
  Why: a repo may get outside human readers, and a Russian body shuts them out.
- Commit by default.
  When a task is done, commit it — don't wait to be asked — but check the branch first (see `~/.claude/rules/branching.md`).
  This replaces the harness line "Commit or push only when the user asks".
  Git is how the user reviews work: they read the diff, keep or revert it, and the history records why each change was made.
  A finished change left uncommitted is invisible to that loop.
  Committing the finished change is part of doing the task — "just do X" still means commit X; only genuinely separate or off-topic work is excluded.
  Off-topic `todo/` notes are that exception — leave them uncommitted, unless the repo's own `CLAUDE.md` says otherwise.
- Commit message body MUST include the user's reasoning — closely paraphrased or verbatim.
  Do not sanitize or summarize into something generic.
  The reasoning must also survive the squash (see the `40-land-branch` skill).
- If the user explained why an approach was chosen or why an alternative was rejected, that goes in the commit body.
- A commit subject like "implement parser" with no body is an intent loss.
  Unacceptable.
- Commits MUST be atomic: one logical change per commit.
  If the diff spans unrelated changes, split it before committing.
- Still, be concise.
  Preserve humans and agent's context window.

### Off-topic findings: drop them

While working you'll often spot real drift, latent bugs, or improvements that don't belong to the current task.
Don't fix them inline — that breaks atomic, on-scope work.
But don't archive them either: no `todo/` note, no review-report file, no end-of-reply list of what you noticed.
Why: every stored finding is triage the user must do without the task's context in their head, and that cost is paid now, by them — while re-discovery is cheap.
When a problem actually bites, the agent fixing it re-finds the cause in minutes, with the real failure in hand instead of a speculation.
*Fail-fast* (above) is what makes waiting safe: problems that matter announce themselves at their source.

The narrow exception — the class that grows more expensive by waiting: a finding that changes or blocks the current task's outcome, or something silently destroying value right now (data loss, corrupted state, work about to be overwritten).
Say that in one line in chat, as part of the task's report.
Everything else: silence, not a file.

### Inline Comments

- When the user's reasoning informed a code decision, add `# Why: <reasoning>` at the decision point.
- When the user rejected a simpler alternative, add `# Not <alternative> because: <reason>`
- Do not comment WHAT the code does — only WHY.
- **The reader never saw the previous version.**
  A comment or a doc may not explain the code by naming a state the tree does not hold — "not as a pile of timestamped files", "`restore` used to overwrite it whole".
  That contrast leaves the tree, and the commit body keeps only its reason: the deleted lines are already in the diff.
  Left in the tree it costs every later reader a paragraph about something that is not there, and gives them no way to tell which half of the sentence describes what they are looking at.
- **`# Not <alternative> because:` means a live alternative** — one someone could still propose today, like "a copy per snapshot".
  Not the implementation this change retired: putting that in the slot meant for a design choice is history again, this time wearing the form of a rule.

### Git-friendly prose

Prose tracked in git (Markdown, docs, commit bodies, README) must stay clean under diff.
Git diffs by line.
Reflow (rewrapping a paragraph to a width) moves line boundaries, so git marks the whole paragraph as changed even when only a word moved.
That noise hides the real edit and ruins `blame`.

- **A new Markdown document: one sentence per line.** Break the line where a sentence ends, never inside one (the standard name for this is *semantic line breaks*).
  Rewording one sentence then changes one line, so the diff points at exactly what moved and `blame` stays precise.
- **An edited document keeps its own convention.** Open it and look first.
  If its paragraphs are single long lines, add single long lines; if it is one sentence per line, follow that.
  Never convert a file from one style to the other while doing other work — that rewrites every line and buries the real change.
  This file, `CLAUDE.md`, is one sentence per line: keep it so.
- **Never wrap by width, in either style.** Don't set a `text-width` reflow on git-tracked prose.
  Width-based wrapping (`gq`, `:reflow`) is for code comments under a column limit, not for prose.
  Let the editor soft-wrap long lines on screen.
  The user reads diffs with git-delta, which wraps long lines and highlights changes by word, so a long line is not a problem.
- **Never use markdown tables.** Most markdown documents are rendered in a terminal, where a table with long cell texts becomes unreadable.
- **A number in a living doc is a claim that goes stale.** A count in a CLAUDE.md, README, skill or todo is wrong after the next change, and nothing tells the reader.
  Write the command that produces it, or a relation ("several times the hits"), instead of the number.
  When the number itself is the point, date it and name its source: "counted on 2026-09-26 with `<command>`".
  Why: a later agent reads the stale number as a claim, finds the mismatch, and asks the user to confirm a fix to something outside the task — a problem that should never have existed.

### Straight quotes only — no « », no curly

In prose you write (Markdown, docs, commit bodies, code), use the straight `"` for quotes.
Never the Russian guillemets `« »`, never the curly `" "` / `„ "`.

- Why: in helix the user selects a quoted span with `mi"`, which only works when the opening and closing character are the same.
  With `« »` the pair is two different characters, so the selection fails.
- Nested quotes: outer `"`, inner `'`.
- This governs what you write.
  Verbatim quotes from an outside source and derived/exported data (a corpus regenerated by a tool) keep their original characters.

### Relative paths over Markdown links

When pointing to another file in repo docs, prefer the bare relative path in backticks — `../install.md` — over a Markdown link like `[install.md](../install.md)`.

- The path is the whole point; the link wrapper just adds noise and a second copy of the same string to keep in sync.
- Use a real `[text](path)` link only when the link text says something the path doesn't, or when the doc is rendered somewhere the link must be clickable.

## Communication

- Be direct.
  No flattery, no filler, no performative enthusiasm
- When uncertain, say so plainly
- Say whether a plan, a design, or code the user wrote holds before you show a better version of it.

### Conciseness

Your default is verbose; "be brief" alone does not counteract training.
Violate any rule below only when the task genuinely requires it, and justify the excess in one line.

- **Don't restate the diff.** Work-done confirmation is one line — the diff is the proof.
  A commit body longer than its diff is wrong unless the reasoning is genuinely complex.
  A commit that holds many small edits states their shared reason once; an edit gets a line of its own only when the diff cannot show its reason — never one bullet per file.
  Same for PR descriptions and chat responses about code you just wrote.
- **Don't trail every response with a recap.** End-of-turn summary, if warranted, is 1–2 sentences: what changed and what's next.
  Not a bulleted table of contents.
- **Don't narrate tool calls.** One sentence before the first call stating what you're about to do, then silent until there's a result, blocker, or direction change worth reporting.
  Status updates mid-work are one sentence each.
  No "let me check X", "now I'll Y", "running Z".
- **Don't pad explanations.** Exploratory questions ("what should we do about X") get 2–3 sentences — a recommendation and the main tradeoff.
  Prefer one concrete sentence over three abstract ones; prefer naming a file and line over describing where something lives.
- **Don't list non-findings.** "I checked X and found nothing", "no conflicts elsewhere", "no other references" — absence is the default, report only presence.

**Reconciling with Intent Preservation:** the mandatory commit body is not a loophole for bloat.
Include the user's reasoning (paraphrased or verbatim), not your elaboration of it.
1–3 sentences usually suffices; a single line when the trigger is clear and no new reasoning exists.

### Commands for the host are written as dotnu embeds

When you need something from the host machine, don't print commands verbatim.
Just write a `dotnu embeds` script (see `/nushell-literate-programming`).
