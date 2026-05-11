---
task-name: verify-host-bootstrap
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify `./bootstrap.sh` host entry path

## Task from user (original)

create the necessary number of todos for checking the introduced functionality after 288a2c950544afee20c81a329b3a356a45c92fd2 (the tip of source/master)

## Task description (extended version)

`cozy/bootstrap.sh` is the new host entry that mirrors the Docker path:
ensures brew + nu, then execs `bootstrap.nu` with forwarded args. Auto-
detection means `setup-docker-system` is *skipped* on host (no
`/etc/sandbox-persistent.sh` marker), and `populate-repos` uses committed
`vendor/` as-is unless `--local` forces a refresh from sibling repos.

Goal: confirm host install works end-to-end without sudo prompts, without
touching `/etc/`, and without overwriting an existing `~/.gitconfig`.

## Requirements

- [ ] `./bootstrap.sh` (no flags) completes on macOS host with brew preinstalled
- [ ] `setup-docker-system` does NOT fire (no apt calls, no `/etc/` writes)
- [ ] `ensure-nu.sh` happy path: latest brew `nu` parses `bootstrap.nu`, no fallback download
- [ ] `~/repos/` populated from committed `vendor/` (no GitHub fetch, no rsync)
- [ ] Existing `~/.gitconfig` (host user's real identity) is NOT overwritten — XDG `~/.config/git/config` only kicks in when global has no setting
- [ ] Dotfiles deploy: `toolkit push-to-machine --docker` is invoked (cozy only vendors `paths-docker.csv`; this is by design — feature parity, not host-specific paths)
- [ ] `claude` installed, nushell MCP registered
- [ ] `./bootstrap.sh --local` triggers `toolkit/vendor.nu --local` (rsync from sibling repos) and `~/repos/` reflects the sibling-repo source tree, not the committed `vendor/`
- [ ] No `/etc/apt/apt.conf.d/90proxy` written, no `/etc/sandbox-persistent.sh` written
- [ ] Script-level `cd "$(dirname "$0")"` works regardless of caller's cwd

## Implementation plan

- [ ] Step 1: prepare clean macOS host or a fresh non-cozy Ubuntu container with brew installed
- [ ] Step 2: snapshot `~/.gitconfig`, `~/repos/`, `~/.claude/`, `/etc/apt/`, `/etc/sandbox-persistent.sh` if present
- [ ] Step 3: run `./bootstrap.sh` from arbitrary cwd; capture stdout/stderr
- [ ] Step 4: walk Requirements checklist; diff snapshot
- [ ] Step 5: clean `~/repos/`, run `./bootstrap.sh --local`; verify rsync source vs. tarball source
- [ ] Step 6: verify `~/.gitconfig` is untouched (precedence: global > XDG)

## Affected files

- Existing files: `bootstrap.sh`, `sandbox-toolkit/install/bootstrap.nu`, `sandbox-toolkit/install/ensure-nu.sh`, `toolkit/vendor.nu`
- New files: none
