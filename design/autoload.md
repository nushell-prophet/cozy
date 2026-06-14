---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - docker-files/nushell-autoload/module-imports.nu
  - docker-files/nushell-autoload/mcp-server.nu
  - docker-files/nushell-autoload/git-safe-directory.nu
  - docker-files/nushell-autoload/my-nu-completions.nu
  - docker-files/nushell-autoload/standard-aliasses.nu
  - docker-files/global-claude.md
  - docker-files/pbcopy
  - docker-files/logo.ans
  - docker-files/workspace-README.md
---

# cozy autoload & shipped docker-files

The `docker-files/` bits that land in the running sandbox. `bootstrap.nu` Step 3.5 copies `docker-files/nushell-autoload/*.nu` → `~/.config/nushell/autoload/` (loaded on every shell start), Step 6 appends `global-claude.md` to `~/.claude/CLAUDE.md`, and the `pbcopy` shim is installed to `~/.local/bin` (Step 0). The `Dockerfile`'s final `COPY` places `workspace-README.md` at `~/workspace/README.md`. `logo.ans` stays in place and is read by `cozy logo` and the build MOTD.

Each entry records why the file ships — the self-healing or workaround it exists for. **Code** points at the file.

## Autoload scripts (`~/.config/nushell/autoload/`)

Nushell loads autoload scripts alphabetically. They are listed below in that load order (`git-safe-directory` → `mcp-server` → `module-imports` → `my-nu-completions` → `standard-aliasses`); the entries are reordered only so the environment-shaping scripts read first. There is no ordering dependency between them.

### git-safe-directory.nu
Re-assert git `safe.directory = '*'` on shell start. Self-healing: `docker sandbox` create overwrites the global setting with just the workspace-root path, so submodule repos beneath it trip "dubious ownership" under VirtioFS. Guarded so the normal path writes nothing.
**Code:** `docker-files/nushell-autoload/git-safe-directory.nu`

### mcp-server.nu
Ensure the nushell MCP server is registered in Claude Code user config. Self-healing: sandbox create may overwrite `~/.claude.json`, this restores the `mcpServers.nushell` stdio entry (`nu --mcp`).
> NOTE: registered in `~/.claude.json` (user scope), NOT `~/.claude/settings.json`.
**Code:** `docker-files/nushell-autoload/mcp-server.nu`

### module-imports.nu
Resolve `$env.WORKSPACE_DIR` to the in-VM mount path, then overlay/use the vendored `~/repos/` modules on every shell start (nu-goodies, cozy, nu-kv, dotnu, numd, claude-nu, cmd-stack, plus zellij's todo.nu). Sets `$env.kv.path` under the workspace sandbox-state dir when mounted. Windows hosts get `C:\Users\…` → `/c/Users/…` rewritten here.
**Code:** `docker-files/nushell-autoload/module-imports.nu` → `def resolve-workspace-mount`

### my-nu-completions.nu
Custom completions for external tools — defines the `tte` extern with style-name completion.
**Code:** `docker-files/nushell-autoload/my-nu-completions.nu` → `export extern tte`

### standard-aliasses.nu
Defines the `lg` → `lazygit` alias (the only alias in the file today).
**Code:** `docker-files/nushell-autoload/standard-aliasses.nu` → `alias lg = lazygit`

## global-claude.md
The tool catalog appended to `~/.claude/CLAUDE.md` by `bootstrap.nu` Step 6. A markdown brief that tells the agent what cozy built around it: available tools (shell, editors, git, search, data/languages, formatting, package managers), where Nushell modules live, the registered Nushell MCP server, sandbox constraints, and a privacy section.
**Code:** `docker-files/global-claude.md`

## pbcopy
Clipboard shim installed to `~/.local/bin/pbcopy` (Step 0). Reads stdin and emits it as an OSC 52 terminal escape (`base64`-encoded) to `/dev/tty`, so copy-to-clipboard works over the terminal without a real pasteboard.
**Code:** `docker-files/pbcopy`

## logo.ans
The cozy ANSI logo asset. Read by `cozy logo` (anchored via `path self`) and by the build/MOTD line in `bootstrap.nu`. Not copied elsewhere — consumed in place from `~/repos/cozy/docker-files/logo.ans`.
**Code:** `docker-files/logo.ans`

## workspace-README.md
The "You're inside a cozy sandbox" orientation page, placed at `~/workspace/README.md` by the `Dockerfile`'s final `COPY` (not by `bootstrap.nu`). Describes the environment — the vendored `~/repos/` modules, the `cozy` command surface, and every config file cozy touched — for whoever opens the workspace. Points at `~/repos/cozy/README.md` for the full tour.
**Code:** `docker-files/workspace-README.md`
