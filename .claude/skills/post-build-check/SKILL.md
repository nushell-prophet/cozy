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

These need a macOS shell, registry network, or a fresh rebuild — none reachable
from inside the sandbox or from `verify`:

- [ ] On macOS host: `./host-install.sh` from clean state succeeds; `claude mcp
      list` afterwards shows a brew-resolved `nu` path (`/opt/homebrew/bin/nu`
      on Apple Silicon, `/home/linuxbrew/.linuxbrew/bin/nu` on Intel).
- [ ] `./host-install.sh --local` rsyncs from sibling `../<repo>/` clones rather
      than fetching tarballs; `~/repos/` reflects the sibling tree.
- [ ] Pre-existing host `~/.gitconfig` (user's real identity) survives — XDG
      `~/.config/git/config` only fills unset keys.
- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds end-to-end.
- [ ] Remove a module from `toolkit/vendor.yml`, rebuild, recreate sandbox —
      the dropped module is absent from `~/repos/` in the new image.
- [ ] `hx`, `lazygit`, `zellij` open into their TUIs on a real TTY and quit
      cleanly. `cmd+t`, `cmd+n`, `cmd+shift+g` keybindings respond as documented
      in `vendor/dotfiles/zellij/config.kdl`.

## When to escalate

If many checks fail at once, suspect `bootstrap.nu` didn't complete. Re-run it
to surface the first error — don't patch bootstrap.nu from inside the sandbox;
the source of truth is the host cozy repo:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```
