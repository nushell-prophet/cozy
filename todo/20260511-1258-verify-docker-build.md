---
task-name: verify-docker-build
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify Docker build path via bootstrap.nu

## Task from user (original)

create the necessary number of todos for checking the introduced functionality after 288a2c950544afee20c81a329b3a356a45c92fd2 (the tip of source/master)

## Task description (extended version)

Smoke-test the primary path: `docker build -t cozy:v1 .` followed by
`docker sandbox create -t cozy:v1 shell ~/path/to/project`. The Dockerfile
now collapses to a single `RUN nu -c 'use bootstrap.nu; bootstrap'` (auto-
detects Docker via `/etc/sandbox-persistent.sh` marker). All former
USER-root layers (apt installs, pbcopy, git identity, apt proxy,
`/etc/sandbox-persistent.sh` env exports) are absorbed into
`bootstrap.nu`'s `setup-docker-system` step.

Goal: confirm a freshly built image produces a working sandbox with feature
parity vs. the pre-extraction Dockerfile.

## Requirements

- [ ] `docker build -t cozy:v1 .` succeeds from a clean state (no cached layers)
- [ ] Resulting image launches via `docker sandbox create -t cozy:v1 shell <path>`
- [ ] `claude` runs and the nushell MCP server is registered
- [ ] All Homebrew tools resolve on PATH: `nu fzf lazygit hx zellij broot delta vd bat topiary fd jj git-lfs`
- [ ] `~/repos/` contains every module listed in `toolkit/vendor.yml`
- [ ] Dotfiles deployed: `~/.config/helix/`, `~/.config/zellij/`, `~/.config/jj/`, `~/.config/nushell/` exist with vendored content
- [ ] `~/.claude/settings.json` has baked `cleanupPeriodDays=36500`, `editorMode=normal`, `verbose=true`
- [ ] `~/.claude/CLAUDE.md` ends with the `docker-files/global-claude.md` content
- [ ] `~/.config/git/config` contains `[user] Agent`, `[safe] directory = *`, `[gc] auto = 0`, `[core] fsync = all`
- [ ] `~/.config/git/ignore` contains `.DS_Store Thumbs.db desktop.ini`
- [ ] `/etc/apt/apt.conf.d/90proxy` exists and routes apt through `host.docker.internal:3128`
- [ ] `~/.local/bin/pbcopy` exists, mode 755, OSC 52 shim works
- [ ] `/etc/sandbox-persistent.sh` has appended env exports (GIT_AUTHOR_*, JJ_CONFIG, XDG_*, HELIX_RUNTIME, LANG)
- [ ] Broot init: `~/.config/broot/conf.hjson` exists; `broot --version` runs
- [ ] Topiary installed with nushell grammar (formats a `.nu` file)

## Implementation plan

- [ ] Step 1: clean build — `docker build --no-cache -t cozy:v1 cozy/` and capture log
- [ ] Step 2: launch sandbox against a throwaway workspace
- [ ] Step 3: walk the Requirements checklist inside the sandbox (one nu pipeline to print pass/fail per check)
- [ ] Step 4: smoke-test claude — `claude mcp list` shows `nushell`; an MCP `evaluate` call works
- [ ] Step 5: compare build-log line count vs. pre-extraction baseline (sanity, not strict)

## Affected files

- Existing files: `Dockerfile`, `sandbox-toolkit/install/bootstrap.nu`, `sandbox-toolkit/install/mod.nu`
- New files: none for this todo (verification only)
