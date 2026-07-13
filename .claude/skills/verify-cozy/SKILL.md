---
name: verify-cozy
description: >
  Verify a cozy build by running `cozy verify` against a target you name — a
  locally-built docker container (default), a running sbx sandbox, or a host
  checkout. The checks (cozy-module/verify.nu) derive every expected value from
  the repo. Use when you say "verify the build", "build-check", "smoke test the
  sandbox", "is everything wired up", "/verify-cozy docker", after building the
  image, or after creating a sandbox.
---

# verify-cozy

Runs cozy's own check suite (`cozy-module/verify.nu`) against a target. `verify.nu`
takes a transport closure, so the check logic is identical everywhere — the only
thing that changes per target is how the commands are carried. Name the target as
the argument; with no argument the target is `docker`.

The checks derive every expected value from sources that ship into the build —
`vendored-repos.nuon` (repos), the `docker-files/nushell-autoload/` glob (autoload
scripts), and the export block in `bootstrap.nu` (env vars) — so the checklist
can't drift from the build. They cover binaries on PATH, vendored repos, autoload
scripts, runtime env, MCP wiring, pbcopy, the appended CLAUDE.md tool catalog,
that `bootstrap.nu` parses on the shipped nu, topiary's grammar, and XDG git
config.

`cozy` is a Nushell overlay (loaded by the `modules-core.nu` autoload), not a PATH
binary. Autoloads fire in an interactive shell and the MCP `evaluate` tool but
**not** under `nu -c`, so there load the overlay yourself:
`nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'`.

The env checks read a login shell (via `bash -lc`), not verify's own process, so
they report the same result however verify was launched. The git identity
(`GIT_AUTHOR_*`, `GIT_COMMITTER_*`) and `JJ_CONFIG` live only in
`/etc/sandbox-persistent.sh`; a login shell must source it (the sbx base does this;
the Debian image does it via `/etc/profile.d`), or those five checks false-fail.

Read the printed table; any `pass: false` row names what to fix and, for files,
the owning repo. There is nothing to hand-maintain — to add or change a check,
edit `cozy-module/verify.nu`.

## Targets

### `docker` (default) — build locally, verify in a throwaway container

No push, no sbx. Exercises the shared boot tail (`run-install.sh` → `ensure-nu.sh`
→ `bootstrap.nu`) that every install path runs.

```sh
docker build -t cozy:verify .            # add --no-cache to force a clean build
docker run --rm cozy:verify \
  nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'
```

- Layer cache: editing `cozy-module/` re-runs only the bootstrap layer (~30–60s);
  editing base deps re-runs brew (minutes).
- Build egress: the sandbox VM blocks `:80`, allows `:443`. The Dockerfile already
  uses https apt sources, so builds work in restricted networks.
- **Boundary:** this validates the shared install logic, NOT sbx-specific wiring
  (the kit spec, sbx's git-config rewrites, the microVM). It is a fast pre-check —
  do a final `sbx run` smoke test before relying on a change.
- If `cozy verify` aborts on a missing external command (e.g. `gh` on a lean
  image) rather than reporting it as a `pass: false` row, that absent tool is
  itself the finding — note it. (`verify.nu` throwing instead of reporting on a
  fully-absent tool is a known robustness gap.)

### `<sandbox-name>` — verify a running sbx sandbox

Run `cozy verify` inside the sandbox — any launch path works: the nushell MCP
`evaluate` tool, an interactive shell, or `nu -c` from Bash (load the overlay
yourself under `nu -c`, per above). One MCP-only gotcha: an `evaluate` session
caches the module it loaded at startup, so if you edit `verify.nu` mid-session,
re-run via `nu -c` (fresh parse), not the stale overlay.

### `host` — a host checkout

The machine cozy was installed on. `verify` can't reach some host-only paths;
pair it with the host-only checklist below.

## Caveat — `CLAUDE.md catalog` (sandbox target)

This one row can fail on a healthy build. The catalog is appended to
`~/.claude/CLAUDE.md` by bootstrap step 6, but that same file is also user state:
`cozy sandbox-state import` overwrites it whole from a snapshot. If the snapshot
has no catalog, import wipes the build's catalog and the check fails — not a build
defect. Worse, it can't self-heal: `export` snapshots the clobbered
(catalog-less) file, so once lost the catalog stays lost across the import/export
loop. Before treating this row as a real failure, check whether `cozy
sandbox-state import` ran in this sandbox. (Underlying fix — give the catalog a
marker block so export strips it and the build keeps owning it — is unbuilt as of
2026-07.)

## Manual checks (not automated)

A few things `verify` deliberately leaves out:

- **Idempotency of setup-docker-system.** Re-running `bootstrap.nu` mutates the
  target, so it stays out of the smoke test. To check by hand, confirm the marker
  block stays single after a re-run:
  ```nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # expect 1
  ^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # must still be 1
  ```

## Host-only checklist (a human runs these)

The host and rebuild paths `verify` can't reach. Where a step produces a sandbox
or container, run `verify-cozy` on the result instead of re-checking by hand —
only the host-specific nuances below need eyes:

- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds, then the built
      container passes `verify-cozy docker` (or a sandbox from that image passes).
- [ ] Drop a module from `toolkit/vendor.yml`, rebuild, recreate — `cozy verify`
      reports the dropped module absent from `~/repos/`.
- [ ] On macOS: `cozy-module/install/run-install.sh` from a clean state succeeds
      and `cozy verify` passes. Then confirm `claude mcp list` resolves a brew `nu`
      path (`/opt/homebrew/bin/nu` on Apple Silicon, `/home/linuxbrew/...` on
      Intel) — host-specific, not covered by `verify`.
- [ ] Pre-existing host `~/.gitconfig` (the user's real identity) survives — XDG
      `~/.config/git/config` only fills unset keys.
- [ ] `hx`, `lazygit`, `zellij` open into their TUIs on a real TTY and quit
      cleanly; `cmd+t`, `cmd+n`, `cmd+shift+g` respond as documented in
      `vendor/dotfiles/zellij/config.kdl`.

## When to escalate

If many checks fail at once, suspect `bootstrap.nu` didn't complete. Re-run it to
surface the first error — don't patch bootstrap.nu from inside a sandbox; the
source of truth is the host cozy repo:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```
