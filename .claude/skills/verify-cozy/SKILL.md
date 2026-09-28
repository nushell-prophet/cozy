---
name: verify-cozy
description: >
  Verify a cozy build by running `cozy verify` against a target you name — a
  locally-built docker container (default), a running Apple `container` cage,
  a running sbx sandbox, or a host checkout. The checks live in cozy-module/verify.nu. Use when you say "verify
  the build", "build-check", "smoke test the
  sandbox", "is everything wired up", "/verify-cozy docker", after building the
  image, or after creating a sandbox.
---

# verify-cozy

Runs cozy's own check suite (`cozy-module/verify.nu`) against a target.
`verify.nu` takes a transport closure, so the check logic is identical everywhere — the only thing that changes per target is how the commands are carried.
Name the target as the argument; with no argument the target is `docker`.

The repo, autoload and env checks derive their expected values from sources that ship into the build — `vendored-repos.nuon` (repos), the `docker-files/nushell-autoload/` glob (autoload scripts), and the export block in `bootstrap.nu` (env vars) — so those three can't drift from the build.
The binary list is the exception: `verify.nu`'s `const tools` is hand-kept, because the binaries are spread across the base image and `bootstrap.nu`'s `brew install` with no machine-readable source of truth.
Add a brew tool, add it there too.

The checks cover: that each expected binary *launches* (not merely resolves on PATH), vendored repos, autoload scripts, runtime env, the agent's identity in Claude Code settings, pbcopy, the appended CLAUDE.md tool catalog, that `bootstrap.nu` parses on the shipped nu, topiary's grammar, the global-ignore patterns, XDG git config, and the two network rows — that `api.anthropic.com` is tunneled rather than intercepted (`tls:`), and that an egress allowlist is in force (`egress:`).

`cozy` is a Nushell overlay (loaded by the `modules-core.nu` autoload), not a PATH binary.
Autoloads fire in an interactive shell but **not** under `nu -c`, so there load the overlay yourself: `nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'`.

The env checks read a bare `bash -c` with each expected key stripped from the child's environment first (`env -u`), so they report what the sandbox itself supplies, however verify was launched.
On a base image that bakes no `ENV` those keys live only in `/etc/sandbox-persistent.sh`, and a non-interactive non-login shell reads neither `/etc/profile` nor `/etc/bash.bashrc` — so something must carry them there, or the rows false-fail.
`BASH_ENV` is what carries them — set in the `Dockerfile` for the Debian image, and supplied by the sbx base itself (confirmed on a live sandbox 2026-07).

The `claude env:` rows are separate and read a file, not an env: the agent's identity (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`, `JJ_CONFIG`) lives in the `env` field of `~/.claude/settings.json`, so it belongs to the Claude Code process and not to any shell.
Nothing in verify runs inside Claude Code, so the effective value is out of reach — the rows assert the file, which is where the failure that actually happened would show.

Read the printed table; any `pass: false` row names what to fix and, for files, the owning repo.
To add or change a check, edit `cozy-module/verify.nu`.

## Targets

### `docker` (default) — build locally, verify in a throwaway container

No push, no sbx.
Exercises the shared boot tail (`run-install.sh` → `ensure-nu.sh` → `bootstrap.nu`) that every install path runs.

```sh
docker build -t cozy:verify .            # add --no-cache to force a clean build
docker run --rm cozy:verify \
  nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'
```

- Layer cache: editing `cozy-module/` re-runs only the bootstrap layer (~30–60s); editing base deps re-runs brew (minutes).
- Build egress: the sandbox VM blocks `:80`, allows `:443`.
  The Dockerfile already uses https apt sources, so builds work in restricted networks.
- **The two `egress:` rows fail on this target, by design.**
  A bare `docker run` has no allowlist in front of it — the cage comes from `compose.yaml`, not the image.
  Expect 2 failures here and read the other 58; to see all 60 pass, bring the container up with `docker compose up -d` and verify through `docker compose exec cozy`.
- **Boundary:** this validates the shared install logic, NOT sbx-specific wiring (the kit spec, sbx's git-config rewrites, the microVM).
  It is a fast pre-check — the final smoke test is the Apple `container` path, the one in daily use (target `container <name>` below).
  Add an `sbx run` only when the change touches the kit or other sbx wiring.
- A missing external command (e.g. `gh` on a lean image) is reported as a `pass: false` row, not an abort — the transport turns command-not-found into exit 127.

### `container <name>` — verify a running Apple `container` cage

The main run path: an image from `container build -t cozy:latest .`, brought up with `nu toolkit/container.nu up <name> <workspace>`.
Run the `check:` line that `up` prints:

```sh
container exec <name> nu --commands 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'
```

The cage is in front here, so this is the target where the two `egress:` rows are meant to pass.
A rebuilt image reaches only a new container: `up` refuses an existing name, so `container stop <name>; container delete <name>` first.

### `<sandbox-name>` — verify a running sbx sandbox

Run `cozy verify` inside the sandbox — any launch path works: an interactive shell, or `nu -c` from Bash (load the overlay yourself under `nu -c`, per above).

### `host` — a host checkout

The machine cozy was installed on.
`verify` can't reach some host-only paths; pair it with the host-only checklist below.

## Caveat — `CLAUDE.md catalog` (sandbox target)

The catalog is appended to `~/.claude/CLAUDE.md` by bootstrap step 6, and that same file is also user state.
`cozy sandbox-state global-claude restore` overwrites no `CLAUDE.md`, so the live file survives it and this row failing means the catalog is genuinely missing.
Taking the history's version by hand (`git -C ~/.claude restore CLAUDE.md`) can still drop a newer catalog; re-run `cozy install bootstrap`, which replaces the marker block in place.

## Manual checks (not automated)

A few things `verify` deliberately leaves out:

- **Idempotency of setup-docker-system.**
  Re-running `bootstrap.nu` mutates the target, so it stays out of the smoke test.
  To check by hand, confirm the marker block stays single after a re-run:
  ```nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # expect 1
  ^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # must still be 1
  ```

## Host-only checklist (a human runs these)

The host and rebuild paths `verify` can't reach.
Where a step produces a sandbox or container, run `verify-cozy` on the result instead of re-checking by hand — only the host-specific nuances below need eyes:

- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds, then the built container passes `verify-cozy docker` (or a sandbox from that image passes).
- [ ] Drop a module from `toolkit/vendor.yml`, rebuild, recreate — `cozy verify` reports the dropped module absent from `~/repos/`.
- [ ] On macOS: `cozy-module/install/run-install.sh` from a clean state succeeds and `cozy verify` passes.
- [ ] Pre-existing host `~/.gitconfig` (the user's real identity) survives — XDG `~/.config/git/config` only fills unset keys.
- [ ] `hx`, `lazygit`, `zellij` open into their TUIs on a real TTY and quit cleanly; `cmd+t`, `cmd+n`, `cmd+alt+l` respond as documented in `vendor/dotfiles/zellij/config.kdl`.

## When to escalate

If many checks fail at once, suspect `bootstrap.nu` didn't complete.
Re-run it to surface the first error — don't patch bootstrap.nu from inside a sandbox; the source of truth is the host cozy repo:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```
