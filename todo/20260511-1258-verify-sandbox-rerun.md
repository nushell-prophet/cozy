---
task-name: verify-sandbox-rerun
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify `cozy install bootstrap` re-run inside live sandbox

## Task from user (original)

create the necessary number of todos for checking the introduced functionality after 288a2c950544afee20c81a329b3a356a45c92fd2 (the tip of source/master)

## Task description (extended version)

The bootstrap.nu docstring declares "Re-run = clean setup. Idempotency is
not a goal." Several commits target re-run correctness specifically:

- `05930ab` — wipe `~/.config/nushell` at start of `setup-docker-system` so
  nu's auto-created defaults don't collide with the dotfiles deploy
- `cd5ff32` → `f7b0203` — apt proxy file timing: write *after* `apt-get
  install`, not before, because build-time has direct egress but re-run
  doesn't
- `1055fdd` — fill Dockerfile-only gaps that broke in-sandbox re-runs
- `ad6285a` — decouple sandbox-runtime setup from `--in-docker` (since dropped)
- `2430d86` — `--in-docker` flag removed entirely; mode is filesystem-detected

Goal: confirm `cozy install bootstrap` invoked inside a running sandbox
produces a clean, working environment without breaking what's already
deployed.

## Requirements

- [ ] `nu -c 'use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu; bootstrap'` exits 0
- [ ] `setup-docker-system` fires (because `/etc/sandbox-persistent.sh` exists)
- [ ] `~/.config/nushell` is wiped and then replaced via dotfiles deploy (no stale `config.nu`/`env.nu`/`history.*` collisions)
- [ ] apt-get update succeeds on re-run despite the pre-existing `/etc/apt/apt.conf.d/90proxy` (proxy routes through host)
- [ ] `/etc/sandbox-persistent.sh` env exports remain present (not duplicated awkwardly, but a second append is acceptable per design)
- [ ] `~/.local/bin/pbcopy` overwritten cleanly (mode 755)
- [ ] `~/.config/git/{config,ignore}` overwritten with current content
- [ ] Vendor source resolves to `/tmp/vendor` if still present, else committed `vendor/` (no surprise GitHub fetch)
- [ ] `claude mcp list` still shows `nushell` after `claude install` re-runs
- [ ] Re-run completes faster than fresh install (brew is no-op, apt is cached)

## Implementation plan

- [ ] Step 1: launch a fresh cozy:v1 sandbox from `verify-docker-build`
- [ ] Step 2: capture state — file hashes of `~/.config/git/*`, `~/.claude/settings.json`, `/etc/apt/apt.conf.d/90proxy`
- [ ] Step 3: run `nu -c '... bootstrap'` and capture stdout/stderr
- [ ] Step 4: re-capture state; diff against step 2 — confirm only intended changes
- [ ] Step 5: run claude inside the sandbox and confirm MCP still works
- [ ] Step 6: edge case — delete `/tmp/vendor`, then re-run; confirm fallback to committed `vendor/`

## Affected files

- Existing files: `sandbox-toolkit/install/bootstrap.nu`, `sandbox-toolkit/install/mod.nu`
- New files: none
