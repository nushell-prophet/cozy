---
human-check: pending   # pending | verified — flip to verified after you read it
covers:
  - toolkit/vendor.yml
  - docker-files/nushell-autoload/module-imports.nu
  - vendor/nu-goodies/
  - vendor/nu-kv/
  - vendor/dotnu/
  - vendor/numd/
  - vendor/claude-nu/
  - vendor/nu-cmd-stack/
  - vendor/nutest/
  - vendor/nu-multiproof/
---

# Vendored Nushell modules

The Nushell modules fanned out under `~/repos/` by `bootstrap.nu` Step 3. Each entry is a **pointer + in-sandbox surface**: what the module is for, the handful of commands the user actually touches in-sandbox, and where the code lives. Internals are not documented here — they live in each module's own repo.

`../toolkit/vendor.yml` is the source of truth for *which* modules are vendored and which subdir of each repo is copied. The autoloaded ones are imported by `../docker-files/nushell-autoload/module-imports.nu`; its `overlay use` / `use` order is followed below. Modules that are vendored but **not** autoloaded (nutest, nu-multiproof) come last — they need a manual `use`. Most user-facing descriptions here are reused verbatim from `../README.md`'s "Nushell modules loaded by default" section.

> Per-module specs are expected to move *into the modules themselves* over time and be reconciled back here. The modules are separate repos for distribution and historical reasons, but cozy is their main customer now — their development follows cozy's needs.

## nu-goodies
A personal collection of everyday Nushell commands developed over time. In the AI context, two commands may be especially useful:
- `example` — captures the last pipeline from history, runs it, and formats command + output as a copyable snippet (wraps output in `# =>` comments and the command in `nu -c '...'`)
- `copy-out` — grabs commands with their output from Zellij pane scrollback and copies them to the clipboard (output lines are prefixed with `# =>`)

**Load:** autoloaded, no prefix (`overlay use ~/repos/nu-goodies/nu-goodies`).
**Code:** `vendor/nu-goodies/nu-goodies/` — repo `nushell-prophet/nu-goodies`.

## nu-kv
A key-value store for Nushell. Backing store path is set from `$env.WORKSPACE_DIR` (sandbox-state) when mounted, else `~/.local/share/nu-kv`.

**Load:** autoloaded with the `kv` prefix (`overlay use ~/repos/nu-kv/kv --prefix`).
**Code:** `vendor/nu-kv/kv/` — repo `nushell-prophet/nu-kv`.

## dotnu
`dotnu embeds` is a module for literate programming. It executes a Nushell script, captures output from `| print $in` lines, and injects the results back into the `.nu` file as `# =>` comments after each corresponding line.

**Load:** autoloaded with the `dotnu` prefix (`overlay use ~/repos/dotnu/dotnu --prefix`).
**Code:** `vendor/dotnu/dotnu/` — repo `nushell-prophet/dotnu`.

## numd
`numd` is a module for literate programming. `numd run <file>` parses Nushell code blocks in an `.md` file, executes them, and updates the file with captured output.

**Load:** autoloaded with the `numd` prefix (`overlay use ~/repos/numd/numd --prefix`).
**Code:** `vendor/numd/numd/` — repo `nushell-prophet/numd`.

## claude-nu
A Nushell toolbox for working with Claude Code sessions. Main commands:
- `claude-nu messages` — extract user messages from sessions (filtering, multi-session search, assistant responses)
- `claude-nu sessions` — parse session files into structured summaries
- `claude-nu parse-session` — detailed session analysis with selectable columns (file ops, tool stats, agents, etc.)
- `claude-nu export-session` — export session dialogue as markdown
- `claude-nu save-markdown` — save exported sessions to files
- `claude-nu fetch-claude-docs` — download Claude Code docs for offline use
- `claude-nu fetch-nushell-docs` — download Nushell docs (from the Nushell book) for offline use

**Load:** autoloaded, no prefix (`use ~/repos/claude-nu/claude-nu/` — exports stay under the `claude-nu` namespace).
**Code:** `vendor/claude-nu/claude-nu/` — repo `nushell-prophet/claude-nu`.

## nu-cmd-stack
Command history stacking module — push commands onto a stack and step through them (`cmd-stack push`, `next`, `prev`, `history`).

**Load:** autoloaded, no prefix (`use ~/repos/nu-cmd-stack/cmd-stack`).
**Code:** `vendor/nu-cmd-stack/cmd-stack/` — repo `nushell-prophet/nu-cmd-stack`.

## nutest
[nutest](https://github.com/vyadh/nutest) is a Nushell test framework by [vyadh](https://github.com/vyadh). Licensed under MIT.

**Load:** *not* autoloaded — `use ~/repos/nutest/nutest`.
**Code:** `vendor/nutest/nutest/` — repo `vyadh/nutest` (third-party).

## nu-multiproof
Multi-proof utilities: seal a worktree with a content manifest, SSH signature, and OpenTimestamps (Bitcoin) timestamp, then verify a proof bundle without the original repo. Entry command is `nu-multiproof seal` (regenerate manifest, root CID, sign, stamp); `nu-multiproof verify` checks a bundle. Subcommands cover `ots`, `ssh-sign`, `git-proof`, `tree-hashes`, `cid-v0`.

**Load:** *not* autoloaded — `use ~/repos/nu-multiproof/nu-multiproof`.
**Code:** `vendor/nu-multiproof/nu-multiproof/` — repo `nushell-prophet/nu-multiproof`.

## Also vendored — not command modules
These appear in `vendor.yml` but are configs or Claude skills, not Nushell command modules:
- **dotfiles** (`nushell-prophet/my-dotfiles`) — personal configs (helix, zellij, lazygit, broot, nushell, claude, jj, wezterm, visidata). Deployed by `bootstrap.nu` Steps 4–5; see `autoload.md` and `dotfiles/CLAUDE.md`.
- **my-claude-skills** (`maxim-uvarov/my-claude-skills`) and **nushell-skills** (`nushell-prophet/nushell-skills`) — Claude Code skills installed by `toolkit install-skills`.
- **topiary-nushell** (`blindFS/topiary-nushell`) — Nushell grammar + queries for the topiary formatter, wired up in `bootstrap.nu` Step 8; see `install.md`.
