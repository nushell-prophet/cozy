---
task-name: post-build-verification
status: pending
created: 2026-05-11
updated: 2026-05-11
related_files:
  - sandbox-toolkit/install/bootstrap.nu
  - sandbox-toolkit/install/topiary.nu
  - toolkit/vendor.nu
  - toolkit/test.nu
---

# Post-build verification — `cozy:v1` (release-fixes-orchestration follow-up)

## Already verified inside the running container (this session)

Removed from the actionable list — done in conversation. For audit:

| Fix | How verified |
|-----|--------------|
| F1 | `~/git/topiary-nushell` symlink in place; `~/.config/topiary/` has queries + languages.ncl; `topiary format` runs idempotently on a real .nu file |
| F2 (docker case) | `claude mcp list` → `nushell: ... ✓ Connected` |
| F3 | Wrote sentinel into `~/.config/nushell/history.sqlite3`, ran the wipe block verbatim from bootstrap.nu; `config.nu` got removed, history sentinel survived |
| F7, F8, F9, F10, F12 | Read CHANGELOG `[Unreleased]`, README, CLAUDE.md, sandbox-toolkit/README.md end-to-end — all reflect final state, no `INSTALL_CLAUDE`/`MODULES_SOURCE` ads, host-install section present, architecture diagram + sources-of-truth list updated |
| F11 | `~/.claude/CLAUDE.md` contains the `fd` entry |
| F13 | All 5 autoload filenames `test.nu` expects exist under `~/.config/nushell/autoload/` (`module-imports.nu`, `hooks-config.nu`, `my-nu-completions.nu`, `standard-aliasses.nu`, `mcp-server.nu`) |
| F14 | Ran the marker-replace logic 3× in a row against `/etc/sandbox-persistent.sh`; block count stayed at 1; `$HOME` literal preserved (no `$$HOME` corruption from regex backref) |
| F16 | `~/workspace/` has only `README.md` (from Dockerfile COPY) — no `mounted` symlink, no stale empty mkdir |
| Binaries on PATH | fd, bat, rg, delta, jj, vd, gh, hx, lazygit, zellij, topiary, claude, nu, broot all present |
| MCP nushell tool calls | this conversation is using `mcp__nushell__evaluate` from inside the container — works |
| 13 vendored modules in `~/repos/` | claude-nu, cozy, dotfiles, dotnu, my-claude-skills, nu-cmd-stack, nu-goodies, nu-kv, nu-multiproof, numd, nushell-skills, nutest, topiary-nushell |
| `bootstrap.nu` parses on shipped nu | `nu --ide-check` on `~/repos/cozy/sandbox-toolkit/install/bootstrap.nu` returns hints only, no errors, under nu 0.112.2 |

## Still TODO — needs host shell or rebuild

### Single command that catches a lot

- [ ] **`nu toolkit/test.nu test` from the macOS host.** Spawns a fresh sandbox via `docker sandbox` / `sbx` and asserts the autoload + MCP wiring end-to-end. Cannot run from inside the container (the inner Docker doesn't expose the `sandbox`/`sbx` subcommand).

### macOS-host fixes (need a Mac shell, outside Docker)

- [ ] **F2 on macOS.** From a clean macOS shell, run `./host-install.sh`. After it finishes, `claude mcp list` should show a brew-resolved `nu` path (e.g. `/opt/homebrew/bin/nu`), **not** `/home/linuxbrew/...`.
- [ ] **F5 on macOS.** From a directory that is *not* this repo: `cd /tmp && nu /Users/user/git/ai-sandbox-dev-container/cozy/toolkit/vendor.nu --local`. Confirm `vendor/` is written under `cozy/`, **not** under `/tmp/vendor/`.
- [ ] **F17 on macOS.** On a Mac without Xcode CLT (or temporarily hide `gcc`), trigger `topiary.nu`'s "gcc missing" branch. Should print the Xcode-CLT hint and exit cleanly — no `sudo apt-get` attempt.
- [ ] **`./host-install.sh` from arbitrary cwd.** Script-level `cd "$(dirname "$0")"` lets it run from anywhere on the host.
- [ ] **`~/.gitconfig` preserved.** Pre-existing host `~/.gitconfig` (user's real identity) not overwritten. Git precedence is global > XDG; XDG `~/.config/git/config` only fills unset keys.
- [ ] **No `/etc/` writes on host.** No `/etc/apt/apt.conf.d/90proxy`, no `/etc/sandbox-persistent.sh` written — `setup-docker-system` stays off because the marker is absent.
- [ ] **`ensure-nu.sh` happy path on macOS.** Latest brew `nu` parses `bootstrap.nu` cleanly; no fallback download to `~/.local/bin/nu`.

### Rebuild / re-run path

- [ ] **F4 — stale vendor files removed.** Drop one module from `toolkit/vendor.yml`, re-vendor, rebuild image. Confirm the removed module is gone from the image's `~/repos/`. (Inside-container test impossible: needs full image rebuild.)
- [ ] **F15 — autoload dir cleaned on host re-run.** Drop one `.nu` from `docker-files/nushell-autoload/`, re-run `./host-install.sh` on host. Confirm the removed file is gone from `~/.config/nushell/autoload/`. (Inside-container test impossible: this is the host branch of the wipe.)
- [ ] **Cold `docker build --no-cache -t cozy:v1 .`** succeeds from scratch (no cached layers).
- [ ] **`/tmp/vendor` fallback.** After build, delete `/tmp/vendor` inside the running container and re-run `cozy install bootstrap` → falls back to committed `vendor/` under `~/repos/cozy/`, no surprise GitHub fetch.

### Synthetic vendor.nu failures (corrupt → verify → revert)

- [ ] Mangled `vendor.yml` github path (nonexistent repo) → `vendor.nu` exits non-zero with the curl error visible, NOT a downstream `tar: not in gzip format` confusion. Stderr is not swallowed.
- [ ] `GH_TOKEN=<valid-token>` set → curl invocation includes `Authorization: bearer …` header (verify via `curl -v` trace or by exhausting anonymous 60/hr limit first).
- [ ] Only `GITHUB_TOKEN=<valid>` set (`GH_TOKEN` unset) → same header appears (fallback path works).
- [ ] Both unset → no `Authorization` header sent.
- [ ] `vendor check` subcommand also uses `gh-curl-args` for `nushell-prophet/repos` listing — not just `fetch-tarball`.
- [ ] `GH_TOKEN=bogus` → clean `401` from curl, NOT a silent `tar` failure downstream.

### Synthetic ensure-nu.sh fallback (corrupt → verify → revert)

- [ ] Inject a post-`.nushell-version` syntax construct into `bootstrap.nu` → fallback fires; `~/.local/bin/nu` created mode 755; `nu --version` reports the pinned version from `.nushell-version`.
- [ ] After fallback, `which nu` resolves to `~/.local/bin/nu` (PATH order: `~/.local/bin` before brew).
- [ ] Corrupt `bootstrap.nu` past repair (e.g. unterminated string) → script exits 1 with the "likely a real bug" stderr message (not silent).
- [ ] Spot-check arch detection on amd64 (dev env is arm64): tarball URL builds correctly for `x86_64-unknown-linux-gnu` and `x86_64-apple-darwin`.
- [ ] `mktemp -d` + `trap 'rm -rf "$tmp"' EXIT` cleans up on both success and failure paths.

### Interactive eyeball (briefly open each)

- [ ] `hx`, `lazygit`, `zellij` open into their UIs and quit cleanly. Binaries load (`--version` works); a real TTY is the only remaining check.

## Out-of-scope issue surfaced during verification (flag, don't block)

- **`br` (broot launcher) autoload doesn't define `br`.** `vendor/dotfiles/nushell/autoload/br.nu` does `export def --env br [...]` — when nushell autoloads a file as a module, the module name (`br`) collides with the exported command name (`br`), and the script errors. This is **pre-existing** (lives in vendored `dotfiles`), not introduced by this branch. Fix belongs in the `dotfiles` repo: rename to `export def --env main` (and let nushell expose the module-as-command), or rename the file. Worth a separate todo, but **not a release blocker**.

## Release gate

When all items above pass, you can tag the release (`/make-a-release`).
