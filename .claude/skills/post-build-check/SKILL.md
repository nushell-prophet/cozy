---
name: post-build-check
description: >
  Verify a freshly-built cozy sandbox. The full check is `nu toolkit/test.nu
  test` from the host — it spawns a sandbox and verifies binaries, vendored
  repos, autoload scripts, env vars, MCP wiring and pbcopy, every value derived
  from vendor.yml and the repo. This skill adds the inside-the-sandbox checks
  test.nu can't reach. Use after `docker build` + `docker sandbox create`, or
  when the user says "I built it, what to test", "verify the build", "smoke
  test the sandbox", "post-build check", "is everything wired up".
---

# Post-build verification

## Run the host verifier first

`toolkit/test.nu` is the single source of truth for what a correct build looks
like. From the host (the cozy repo, not inside a sandbox):

```nu
nu toolkit/test.nu test -t <tag>    # tag defaults to `latest`
```

It spawns a fresh sandbox and checks binaries, vendored repos, autoload
scripts, runtime env vars, MCP wiring and pbcopy — every expected value derived
from `vendor.yml` and the repo, so the checklist can't drift out of sync with
the build. Read its final table; any `pass: false` row names the file and the
owning repo to fix.

Everything below is only the handful of checks `test.nu` can't reach from the
host. They are kept list-free on purpose — no hardcoded sets to keep in sync.

## Inside-the-sandbox checks

Run these when you are already inside a freshly-built sandbox — confirm with
`/etc/sandbox-persistent.sh` exists; if not, `docker sandbox exec -it <name> nu`
(or `sbx exec`) in first. Collect a `{check, status, detail}` row each and
print one table; don't stop on the first failure.

### bootstrap.nu parses on the shipped nu

```nu
^nu --ide-check 0 ~/repos/cozy/cozy-module/install/bootstrap.nu
```

Hints OK; any line containing `"severity":"error"` is a fail. If this fails,
`ensure-nu.sh`'s pinned fallback should have caught it during build — surface
loudly.

### Claude MCP nushell server connected

```nu
^claude mcp list
```

Must show a `nushell` entry as `✓ Connected`. `test.nu` confirms the config was
patched; only a live `claude` confirms the server actually starts.

### ~/.claude/CLAUDE.md catalog appended

```nu
open --raw ~/.claude/CLAUDE.md | str contains 'fd'
```

Greps for one tool that step 6 of bootstrap.nu appends from
`docker-files/global-claude.md`. False = the append step didn't run. The
`--raw` flag is required — without it `open` auto-parses the markdown into a
record and `str contains` errors on a non-string input.

### setup-docker-system is idempotent

```nu
^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # expect 1
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # must still be 1
```

A second `1` proves the marker-bounded block is replaced in place, not
appended (the 0.2.0 fix from commit 45cc3d9).

### Topiary formats a .nu file end-to-end

```nu
'def main [] { 1 }' | save -f /tmp/t.nu
^topiary format /tmp/t.nu
open --raw /tmp/t.nu
```

Must reformat without error. A grammar-not-found error means the
`topiary-nushell` symlink in step 8 of bootstrap.nu didn't land. Don't pass
`--language nu` alongside the file argument — topiary 0.7+ treats `--language`
and `[FILES]` as mutually exclusive (exits 2). Auto-detection via the `.nu`
extension is the supported form.

### Runtime git config comes from XDG

```nu
^git config --list --show-origin | str contains '.config/git/config'
```

Confirms 0.2.0's move of runtime git settings from `/etc/gitconfig` (which brew
git ignores) to XDG.

## Host-only checklist (user runs these)

Print these as a bulleted to-do list. The agent inside the sandbox cannot reach
them — they need either a macOS shell, registry network, or a fresh rebuild.

- [ ] On macOS host: `./host-install.sh` from clean state succeeds; `claude mcp
      list` afterwards shows a brew-resolved `nu` path (`/opt/homebrew/bin/nu`
      on Apple Silicon, `/home/linuxbrew/.linuxbrew/bin/nu` on Intel).
- [ ] `./host-install.sh --local` rsyncs from sibling `../<repo>/` clones rather
      than fetching tarballs; `~/repos/` reflects the sibling tree.
- [ ] Pre-existing host `~/.gitconfig` (user's real identity) survives — XDG
      `~/.config/git/config` only fills unset keys.
- [ ] Cold `docker build --no-cache -t cozy:v<N> .` succeeds end-to-end.
- [ ] Remove a module from `toolkit/vendor.yml`, rebuild, recreate sandbox —
      the dropped module is absent from `~/repos/` in the new image
      (stale-vendor cleanup; 0.2.0).
- [ ] `hx`, `lazygit`, `zellij` open into their TUIs on a real TTY and quit
      cleanly. `cmd+t`, `cmd+n`, `cmd+shift+g` keybindings respond as
      documented in `vendor/dotfiles/zellij/config.kdl`.

## When to escalate

If multiple unrelated checks fail simultaneously, suspect `bootstrap.nu` didn't
complete. Re-run it manually to surface the first error — do not patch
bootstrap.nu from inside the sandbox; the source of truth is the host cozy repo:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```
