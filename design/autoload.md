---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - docker-files/nushell-autoload/modules-core.nu
  - docker-files/nushell-autoload/modules-repl.nu
  - docker-files/nushell-autoload/mcp-server.nu
  - docker-files/nushell-autoload/git-global-ignore.nu
  - docker-files/nushell-autoload/git-identity.nu
  - docker-files/nushell-autoload/git-safe-directory.nu
  - docker-files/global-claude.md
  - docker-files/pbcopy
  - docker-files/logo.ans
  - docker-files/workspace-README.md
reconciled-at: 874e4a409b8c7877a9c05a0db8f6acbefd07b1ef
---

# cozy autoload & shipped docker-files

The [`docker-files/`](../docker-files/) bits that land in the running sandbox. `bootstrap.nu` Step 3.5 copies `docker-files/nushell-autoload/*.nu` → `~/.config/nushell/autoload/` (loaded on every shell start), Step 6 appends `global-claude.md` to `~/.claude/CLAUDE.md`, and the `pbcopy` shim is installed to `~/.local/bin` (on every Linux, just before Step 1). The [`Dockerfile`](../Dockerfile)'s final `COPY` places `workspace-README.md` at `~/workspace/README.md`. `logo.ans` stays in place and is read by `cozy logo` and the build MOTD.

Each entry records why the file ships — the self-healing or workaround it exists for. **Code** points at the file.

## Autoload scripts (`~/.config/nushell/autoload/`)

Nushell loads autoload scripts alphabetically; they're listed below in that order (`git-global-ignore` → `git-identity` → `git-safe-directory` → `mcp-server` → `modules-core` → `modules-repl`). The only ordering dependency is `modules-core` before `modules-repl` — alphabetical naming guarantees it, so the REPL-only modules can build on the core overlays.

Cozy is not the only writer of that directory: Step 4's dotfiles deploy lands `br.nu`, `completions.nu`, `hooks-config.nu` and `zzz_ignore_vars.nu` there too, from `vendor/dotfiles/nushell/autoload/`. Only the cozy-owned files are documented below. Note also that nushell reads that one directory and does not recurse into subdirectories of it, and that it `source`s each file rather than `use`-ing it — which is why `completions.nu` is a loader of `use` lines instead of the completion files simply being dropped in (they define `export extern main`, a name that only resolves through `use`).

### git-global-ignore.nu
Keep cozy's global gitignore patterns (`.DS_Store`, `Thumbs.db`, `desktop.ini`) active on shell start. Self-healing: `sbx` sets `core.excludesFile = ~/.gitignore_global` in `~/.gitconfig` on every create, which shadows git's XDG default (`~/.config/git/ignore`) where cozy wrote those patterns. git allows one excludesFile and `~/.gitconfig` wins over XDG, so cozy can't reclaim it — the autoload mirrors its canonical `~/.config/git/ignore` into whatever excludesFile resolves to, keeping sbx's `.sbx`. No-ops when excludesFile is unset (plain host reads the XDG default) or nothing is missing.
**Code:** [`docker-files/nushell-autoload/git-global-ignore.nu`](../docker-files/nushell-autoload/git-global-ignore.nu)

### git-identity.nu
Write the human's own git identity into `~/.gitconfig` on shell start, from the `COZY_GIT_USER_NAME` / `COZY_GIT_USER_EMAIL` variables `../toolkit/container.nu` reads off the host's `git config --global` and forwards at run time. Three layers, each narrower than the last, so a commit says who made it: the XDG file holds the `Agent <agent@sandbox>` placeholder (present so build-time commits work), `~/.gitconfig` overrides it for the human, and the `GIT_AUTHOR_*`/`GIT_COMMITTER_*` values in Claude Code's own `env` setting (`bootstrap.nu` step 9) override that inside the agent's process tree only — not in any shell, so this middle layer is what the human's own shell lands on. Not in `bootstrap.nu` because: those variables arrive at run time, long after the image is built. Written with `git config --file`, not as a file write, so sbx's `core.excludesFile` in the same file survives — and not `--global`, which does not mean `~/.gitconfig`: git writes there only when that file already exists, and otherwise writes `$XDG_CONFIG_HOME/git/config` when *that* one does. That is cozy's exact layout, so `--global` overwrites the placeholder in the bottom layer instead of adding the middle one. Guarded so the normal path writes nothing; no-ops when the variables are unset (a host with no global identity, or the sbx path, which has no forwarding yet).
**Code:** [`docker-files/nushell-autoload/git-identity.nu`](../docker-files/nushell-autoload/git-identity.nu)

### git-safe-directory.nu
Re-assert git `safe.directory = '*'` on shell start. Self-healing: sandbox creation overwrites the global setting with just the workspace-root path, so submodule repos beneath it trip "dubious ownership" under VirtioFS. Guarded so the normal path writes nothing.
**Code:** [`docker-files/nushell-autoload/git-safe-directory.nu`](../docker-files/nushell-autoload/git-safe-directory.nu)

### mcp-server.nu
Two jobs. First, raise `$env.NU_MCP_OUTPUT_LIMIT` to 64kb from nu-mcp's 10kb default: over the cap the tool returns *no* output at all, only a note pointing at `$history.N`, so every long result cost a second round trip — and in the session logs more than half were never fetched. Set here rather than via `claude mcp add --env` because nu-mcp reads it with `as_filesize`, which refuses a string, so a process env var is silently ignored. Not `0` (unlimited): one stray `open big.json` would then push a whole file into the context window — a roomier backstop, still a backstop. Second, ensure the nushell MCP server is registered in Claude Code user config. Self-healing: sandbox create may overwrite `~/.claude.json`, this restores the `mcpServers.nushell` stdio entry (`$nu.current-exe` + `--mcp`, matching Step 9). It compares the stored `command` rather than testing for presence, so an entry that is present but wrong gets repaired — a presence test never fires for one. The path is `$nu.current-exe` and not `which nu` because `which` answers about any command of that name, which a `def` or an alias can shadow.
> NOTE: registered in `~/.claude.json` (user scope), NOT `~/.claude/settings.json`.
**Code:** [`docker-files/nushell-autoload/mcp-server.nu`](../docker-files/nushell-autoload/mcp-server.nu)

### modules-core.nu
Resolve `$env.WORKSPACE_DIR` to the in-VM mount path, then overlay the vendored `~/repos/` modules that must work in any context: nu-goodies, cozy, nu-kv, dotnu, numd. Sets `$env.kv.path` under the workspace sandbox-state dir when mounted. Windows hosts get `C:\Users\…` → `/c/Users/…` rewritten here. **Also loaded outside autoload:** non-interactive `nu --config ~/.config/nushell/autoload/modules-core.nu -c …` runs it (Helix's `shell`, agent `nu -c` from the Bash tool), because a one-shot `-c` skips autoload but honours `--config`. Everything here must stay safe in a one-shot `-c` — no prompt hooks, no REPL state.
**Code:** [`docker-files/nushell-autoload/modules-core.nu`](../docker-files/nushell-autoload/modules-core.nu) → `def resolve-workspace-mount`

### modules-repl.nu
Interactive-only module additions, `use`d on every interactive shell start: claude-nu, the two completions claude-nu still ships (claude/nu), zellij's todo.nu, nu-cmd-stack (followed by `cmd-stack init`, which registers its keybindings — a bare `use` binds no keys). Split out from the core set so non-interactive `-c` consumers don't load session tools that have no meaning there. The completions for tools claude-nu has nothing to do with (zellij, fd, chafa, sandbox-exec) moved to the dotfiles repo and arrive via its own `completions.nu` autoload; `claude.nu` and `nu.nu` stayed because the first imports four internals of `sessions.nu` for the live session picker and the second is the only one claude-nu's test suite covers.
**Code:** [`docker-files/nushell-autoload/modules-repl.nu`](../docker-files/nushell-autoload/modules-repl.nu)

## global-claude.md
The tool catalog appended to `~/.claude/CLAUDE.md` by `bootstrap.nu` Step 6. A markdown brief that tells the agent what cozy built around it: available tools (shell, editors, git, search, data/languages, formatting, package managers), where Nushell modules live, a Nushell pitfalls cheatsheet, the registered Nushell MCP server and its two usage caveats (the `evaluate` session persists across calls and re-running `use` does *not* reliably re-read an edited module — tested three ways, all served the stale copy, and a stale `toolkit/container.nu` once recreated the egress proxy from the previous pin while printing success; the fix is a fresh process, not a re-`use`. And the MCP `nu` skips the login shell, so anything set only in `/etc/sandbox-persistent.sh` is absent — the agent's own identity is not, it rides Claude Code's `env` setting), git rules for the sandbox (chiefly: never `git add -A`/`git add .`, which stage parked notes and another task's edits), sandbox constraints, a note that the code here is agent-written and the agent should keep an eye on it, and a privacy section. Its most load-bearing line is not a fact but an instruction: end any nu pipeline you are going to read with `| to nuon --pretty`, because a stock one-shot `nu` renders an 80-column box table that drops columns and truncates names without saying so. That it is an instruction and not a mechanism is a decision, not an omission — a `nu` wrapper injecting a display config was built and reverted, since `--config` is an opt-out (and the documented `nu --config …/modules-core.nu -c …` form was exactly the one it could not reach), while a pipeline ending in `| table` renders to a string before any config is consulted. An instruction cannot rot; its weakness is that it fires only when the agent remembers.
**Code:** [`docker-files/global-claude.md`](../docker-files/global-claude.md)

## pbcopy
Clipboard shim installed to `~/.local/bin/pbcopy` on every Linux, container or host, just before Step 1 — the dotfiles deployed in Step 4 call `pbcopy` and Linux has no native one; a user's own non-cozy `pbcopy` on PATH is never shadowed. Reads stdin and emits it as an OSC 52 terminal escape (`base64`-encoded) to `/dev/tty`, so copy-to-clipboard works over the terminal without a real pasteboard.
**Code:** [`docker-files/pbcopy`](../docker-files/pbcopy)

## logo.ans
The cozy ANSI logo asset. Read by `cozy logo` (anchored via `path self`) and by the build/MOTD line in `bootstrap.nu`. Not copied elsewhere — consumed in place from `~/repos/cozy/docker-files/logo.ans`.
**Code:** [`docker-files/logo.ans`](../docker-files/logo.ans)

## workspace-README.md
The "You're inside a cozy sandbox" orientation page, placed at `~/workspace/README.md` by the `Dockerfile`'s final `COPY` (not by `bootstrap.nu`). Describes the environment — the vendored `~/repos/` modules, the `cozy` command surface, and every config file cozy touched — for whoever opens the workspace. Points at `~/repos/cozy/README.md` for the full tour.
**Code:** [`docker-files/workspace-README.md`](../docker-files/workspace-README.md)
