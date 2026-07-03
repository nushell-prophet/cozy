---
name: post-build-check
description: >
  Verify a freshly-built cozy sandbox by running `cozy verify` inside it. The
  checks (cozy-module/verify.nu) derive every expected value from the repo. Use
  after building the image and creating a sandbox, or when the user says "I
  built it, what to test", "verify the build", "smoke test the sandbox",
  "post-build check", "is everything wired up".
---

# Post-build verification

The checks live in `cozy-module/verify.nu`. Run them inside a freshly-built
sandbox with `cozy verify`.

Run `cozy verify` via `nu -c` from the **Bash tool** — not the nushell MCP `evaluate` tool. `cozy` is a Nushell overlay (loaded by the `module-imports.nu` autoload), not a PATH binary, and autoloads don't fire under `nu -c`, so load the overlay yourself: `nu -c 'overlay use ~/repos/cozy/cozy-module/ as cozy --prefix; cozy verify'`.

Don't use the MCP `evaluate` tool for this. Its `nu` is spawned directly, not from a login shell, so it never sources `/etc/sandbox-persistent.sh` — where the git identity (`GIT_AUTHOR_*`, `GIT_COMMITTER_*`) and `JJ_CONFIG` are exported. Those five env checks then report `pass: false` on a healthy build (the real container ENV — `XDG_*`, `HELIX_RUNTIME`, `LANG` — is inherited, so it misleads by passing some of the block). The Bash tool's shell is profile-initialized (it sources that file), so a `nu -c` child inherits the full env and every check passes — as does a real login shell, `bash -lc 'nu -c "…"'`.

The checks derive every expected value from sources that ship into the sandbox
— `vendored-repos.nuon` (repos), the
`docker-files/nushell-autoload/` glob (autoload scripts), and the export block
in `bootstrap.nu` (env vars) — so the checklist can't drift from the build.
They cover binaries on PATH, vendored repos, autoload scripts, runtime env, MCP
wiring, pbcopy, the appended CLAUDE.md tool catalog, that `bootstrap.nu` parses
on the shipped nu, topiary's grammar, and XDG git config.

Read the printed table; any `pass: false` row names what to fix and, for files,
the owning repo. There is nothing to hand-maintain here — to add or change a
check, edit `cozy-module/verify.nu`.

## Manual checks (not automated)

A few things `verify` deliberately leaves out:

- **Idempotency of setup-docker-system.** Re-running `bootstrap.nu` mutates the
  sandbox, so it stays out of the smoke test. To check by hand, confirm the
  marker block stays single after a re-run:
  ```nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # expect 1
  ^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
  ^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # must still be 1
  ```

## Host-only checklist (a human runs these)

The host and rebuild paths `verify` can't reach. Where a step produces a
sandbox, run `cozy verify` on the result instead of re-checking by hand — only
the host-specific nuances below need eyes:

- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds, then a sandbox
      built from that image passes `cozy verify`.
- [ ] Drop a module from `toolkit/vendor.yml`, rebuild, recreate — `cozy verify`
      reports the dropped module absent from `~/repos/`.
- [ ] On macOS: `cozy-module/install/run-install.sh` from a clean state succeeds and `cozy
      verify` passes. Then confirm `claude mcp list` resolves a brew `nu` path
      (`/opt/homebrew/bin/nu` on Apple Silicon, `/home/linuxbrew/...` on Intel)
      — host-specific, not covered by `verify`.
- [ ] Pre-existing host `~/.gitconfig` (the user's real identity) survives — XDG
      `~/.config/git/config` only fills unset keys.
- [ ] `hx`, `lazygit`, `zellij` open into their TUIs on a real TTY and quit
      cleanly; `cmd+t`, `cmd+n`, `cmd+shift+g` respond as documented in
      `vendor/dotfiles/zellij/config.kdl`.

## When to escalate

If many checks fail at once, suspect `bootstrap.nu` didn't complete. Re-run it
to surface the first error — don't patch bootstrap.nu from inside the sandbox;
the source of truth is the host cozy repo:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```
