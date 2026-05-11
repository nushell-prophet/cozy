---
task-name: verify-ensure-nu-fallback
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify ensure-nu.sh pinned-version fallback

## Task from user (original)

create the necessary number of todos for checking the introduced functionality after 288a2c950544afee20c81a329b3a356a45c92fd2 (the tip of source/master)

## Task description (extended version)

`959f1d3 bootstrap: pin-with-fallback for nushell version` introduced
`sandbox-toolkit/install/ensure-nu.sh` + `.nushell-version` (currently
`0.112.2`). Both `bootstrap.sh` and the Dockerfile call it before invoking
`bootstrap.nu`.

Logic:

1. If `nu` is missing → `brew install nushell`.
2. Smoke-test with `nu -c "use bootstrap.nu"` (parse + top-level eval).
3. If parse fails → download pinned `nu-${VERSION}-${arch}-${os}.tar.gz`
   from GitHub releases into `~/.local/bin/nu` (already first on PATH per
   Dockerfile ENV / bootstrap.sh export).
4. Re-smoke-test pinned binary. If even pinned fails → exit 1 with the
   "likely a real bug" message.

Goal: confirm fallback fires when (and only when) latest nushell can't
parse `bootstrap.nu`, and that failure messaging is loud.

## Requirements

- [ ] Happy path: latest brew nushell parses `bootstrap.nu` → script exits 0, no download, brew `nu` remains on PATH
- [ ] Synthetic parse failure (see plan) → fallback download fires, `~/.local/bin/nu` is created with mode 755, version matches `.nushell-version`
- [ ] After fallback, `which nu` resolves to `~/.local/bin/nu` (PATH order: `~/.local/bin` before brew)
- [ ] After fallback, `nu --version` reports the pinned version
- [ ] Architecture/OS detection covers all four combos: `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-apple-darwin`, `aarch64-apple-darwin`
- [ ] If pinned binary also can't parse → script exits 1 with the "likely a real bug" message on stderr (not silent)
- [ ] Curl uses `-fsSL` (consistent with vendor.nu fail-fast principle)
- [ ] `mktemp -d` + `trap 'rm -rf "$tmp"' EXIT` cleans up on both success and failure paths

## Implementation plan

- [ ] Step 1: happy path — fresh sandbox, run `ensure-nu.sh`; confirm no download, `which nu` = brew path
- [ ] Step 2: synthetic failure — temporarily prepend `bootstrap.nu` with a syntax construct only post-0.112 supports (or use the inverse: a removed construct); run `ensure-nu.sh`; confirm fallback fires
- [ ] Step 3: post-fallback — confirm `~/.local/bin/nu` exists, mode 755, version = `.nushell-version`; PATH resolution correct
- [ ] Step 4: hard failure — also corrupt `bootstrap.nu` (e.g. unterminated string); run `ensure-nu.sh`; confirm exit 1 with the "likely a real bug" stderr message
- [ ] Step 5: revert `bootstrap.nu` corruption
- [ ] Step 6: arch detection — spot-check on amd64 sandbox too (current dev env is arm64); confirm tarball URL builds correctly

## Affected files

- Existing files: `sandbox-toolkit/install/ensure-nu.sh`, `sandbox-toolkit/install/.nushell-version`, `sandbox-toolkit/install/bootstrap.nu`, `bootstrap.sh`, `Dockerfile`
- New files: none
