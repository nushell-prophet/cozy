---
name: post-build-check
description: >
  Verify a freshly-built cozy sandbox from inside it: binaries on PATH, vendored
  modules under ~/repos/, nushell autoload, claude MCP wiring, bootstrap.nu
  idempotency, ~/workspace/ shape. Use after `docker build` + `docker sandbox
  create`, when the user says "I built it, what to test", "verify the build",
  "smoke test the sandbox", "post-build check", or "is everything wired up".
---

# Post-build verification

Run this **inside** a freshly-built cozy sandbox to confirm `bootstrap.nu`
completed correctly and the runtime matches expectations. Auto-runs everything
that can be checked from inside the container, then emits a host-side checklist
for items the agent cannot reach.

## Preflight

Confirm we are inside the sandbox: `/etc/sandbox-persistent.sh` exists. If not,
stop and tell the user to `docker sandbox exec -it <name> nu` (or `sbx exec`)
into the new sandbox first.

## Auto-checks

Run each in sequence; collect a `{check, status, detail}` row per item and
print one markdown table at the end. Don't stop on the first failure — surface
all of them.

### 1. Binaries on PATH

```nu
['nu' 'fd' 'bat' 'rg' 'delta' 'jj' 'vd' 'gh' 'hx' 'lazygit' 'zellij'
 'topiary' 'claude' 'broot' 'git-lfs' 'pbcopy']
| each {|b| {bin: $b, found: (which $b | is-not-empty)} }
```

Any `found: false` is a fail. `pbcopy` is the OSC 52 shim from
`docker-files/`, not macOS.

### 2. Vendored modules under ~/repos/

Expected names come from `toolkit/vendor.yml` `repo:` keys plus `cozy` itself
(staged by the Dockerfile). At time of writing: `claude-nu`, `cozy`,
`dotfiles`, `dotnu`, `my-claude-skills`, `nu-cmd-stack`, `nu-goodies`,
`nu-kv`, `nu-multiproof`, `numd`, `nushell-skills`, `nutest`,
`topiary-nushell`.

Read the live list from vendor.yml rather than hardcoding — the set drifts.
The Dockerfile only COPYs `docker-files/` and `cozy-module/` into
`~/repos/cozy/`, so `vendor.yml` is not under `~/repos/cozy/toolkit/`. Read it
from the workspace mount where this skill is invoked (typically the cozy
workspace itself):

```nu
let vendor_yml = (
  ['./toolkit/vendor.yml' ($env.WORKSPACE_DIR? | default '' | path join 'toolkit/vendor.yml')]
  | each { |p| $p | path expand }
  | where { |p| $p | path exists }
  | first
)
if ($vendor_yml | is-empty) {
  error make { msg: 'vendor.yml not found — re-invoke from the cozy workspace mount' }
}
let expected = (open $vendor_yml | get repo | append 'cozy' | sort)
let actual = (ls ~/repos | get name | path basename | sort)
{missing: ($expected | where $it not-in $actual), extra: ($actual | where $it not-in $expected)}
```

Both lists empty = pass.

### 3. Nushell autoload populated

```nu
let expected = ['module-imports.nu' 'hooks-config.nu' 'my-nu-completions.nu'
                'standard-aliasses.nu' 'mcp-server.nu']
let actual = (ls ~/.config/nushell/autoload | get name | path basename)
$expected | where $it not-in $actual
```

Empty result = pass.

### 4. bootstrap.nu parses on shipped nu

```nu
^nu --ide-check 0 ~/repos/cozy/cozy-module/install/bootstrap.nu
```

Hints OK; any line containing `"severity":"error"` is a fail. If this fails,
`ensure-nu.sh`'s pinned fallback should have caught it during build — surface
loudly.

### 5. Claude MCP nushell server registered

```nu
^claude mcp list
```

Must contain a `nushell` entry; ideally `✓ Connected`. A `not connected` line
is a fail.

### 6. ~/.claude/CLAUDE.md catalog appended

```nu
open --raw ~/.claude/CLAUDE.md | str contains 'fd'
```

Greps for one tool that step 6 of bootstrap.nu appends from
`docker-files/global-claude.md`. False = the append step didn't run. The
`--raw` flag is required — without it `open` auto-parses the markdown into a
record and `str contains` errors on a non-string input.

### 7. ~/workspace/ shape

```nu
ls ~/workspace | get name | path basename | sort
```

Must be exactly `[README.md, mounted]`. `README.md` comes from the final
Dockerfile COPY; `mounted` is the host-folder symlink. Anything else is
likely a stale `mkdir` left over by an earlier bootstrap.nu version (see
CHANGELOG 0.2.0).

### 8. XDG / runtime env survives a fresh shell

```nu
^nu -lc 'echo $env.XDG_CONFIG_HOME $env.XDG_DATA_HOME $env.HELIX_RUNTIME $env.LANG'
```

All four must be non-empty; `LANG` must be `C.UTF-8`. Empty values mean the
`# >>> cozy env >>>` block in `/etc/sandbox-persistent.sh` isn't being
sourced.

### 9. setup-docker-system is idempotent

```nu
^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # expect 1
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
^grep -c '# >>> cozy env >>>' /etc/sandbox-persistent.sh   # must still be 1
```

A second `1` proves the marker-bounded block is replaced in place, not
appended (the 0.2.0 fix from commit 45cc3d9).

### 10. Topiary end-to-end on a .nu file

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

### 11. XDG git config in place

```nu
^git config --list --show-origin | str contains '.config/git/config'
```

Confirms 0.2.0's move of runtime git settings from `/etc/gitconfig` (which
brew git ignores) to XDG.

## Report

Print a single markdown table:

| Check | Status | Detail |
|---|---|---|
| 1. Binaries on PATH | ✓ / ✗ | (missing bins, if any) |
| 2. Vendored modules | ✓ / ✗ | (missing / extra repos) |
| ... | ... | ... |

Then print the host-only checklist below verbatim.

## Host-only checklist (user runs these)

Print these as a bulleted to-do list. Agent inside the sandbox cannot reach
them — they need either macOS shell, registry network, or a fresh rebuild.

- [ ] On macOS host: `./bootstrap.sh` from clean state succeeds; `claude mcp
      list` afterwards shows a brew-resolved `nu` path (`/opt/homebrew/bin/nu`
      on Apple Silicon, `/home/linuxbrew/.linuxbrew/bin/nu` on Intel).
- [ ] `./bootstrap.sh --local` rsyncs from sibling `../<repo>/` clones rather
      than fetching tarballs; `~/repos/` reflects sibling tree.
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

If multiple unrelated auto-checks fail simultaneously, suspect `bootstrap.nu`
didn't complete. Re-run it manually to surface the first error:

```nu
^nu ~/repos/cozy/cozy-module/install/bootstrap.nu
```

Read the output for the first error and surface to the user — do not patch
bootstrap.nu from inside the sandbox; the source of truth is the host cozy
repo.
