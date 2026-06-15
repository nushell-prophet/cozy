---
name: post-build-check
description: >
  Verify a freshly-built cozy sandbox. Inside the sandbox run `cozy verify`;
  from the host run `nu toolkit/test.nu test`. Both run the same checks
  (cozy-module/verify.nu), deriving every expected value from the repo. Use
  after `docker build` + `docker sandbox create`, or when the user says "I
  built it, what to test", "verify the build", "smoke test the sandbox",
  "post-build check", "is everything wired up".
---

# Post-build verification

The checks live in `cozy-module/verify.nu` and run two ways:

- **Inside a freshly-built sandbox:** `cozy verify`
- **From the host** (also builds + spawns a throwaway sandbox):
  `nu toolkit/test.nu test -t <tag>`

`cozy` is a Nushell overlay loaded by the `module-imports.nu` autoload, not a
PATH binary. Autoloads fire in an interactive shell and in the nushell MCP
`evaluate` tool, but **not** in non-interactive `nu -c '...'`. So run `cozy
verify` through the nushell MCP tool or an interactive shell. From plain `nu -c`
the overlay is absent (`command not found`) — load it first with `overlay use
~/repos/cozy/cozy-module/ as cozy --prefix`.

Both run the identical check set and derive every expected value from sources
that ship into the sandbox — `vendored-repos.nuon` (repos), the
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
sandbox, run `cozy verify` (or `nu toolkit/test.nu test`) on the result instead
of re-checking by hand — only the host-specific nuances below need eyes:

- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds, then `nu
      toolkit/test.nu test -t v<N>` passes.
- [ ] Drop a module from `toolkit/vendor.yml`, rebuild, recreate — `test.nu
      test` reports the dropped module absent from `~/repos/`.
- [ ] On macOS: `./host-install.sh` from a clean state succeeds and `cozy
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
