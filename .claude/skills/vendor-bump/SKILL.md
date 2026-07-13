---
name: vendor-bump
description: >
  Re-vendor modules from upstream into cozy/vendor/ and prepare atomic commits
  grouped by repo. Use when the user says "vendor updated versions", "I vendored,
  commit", "nu toolkit/vendor.nu then commit", "refresh vendor", "bump vendored
  modules", or "vendor the latest, commit by groups".
---

# Vendor bump

Refresh the cozy `vendor/` tree and produce one atomic commit per upstream repo
whose files changed. The user has repeatedly asked for this split-by-repo
grouping ("commit by groups"); never combine multiple repos into one commit.

## Preflight

- `cd` to the cozy repo root (the dir with `toolkit/vendor.nu` and `vendor/`)
- `git status` is clean under `vendor/`. If there are pending vendor changes from
  a previous run, stop and ask the user whether to commit, stash, or discard
  them before re-vendoring

## 1. Run vendor.nu

```sh
nu toolkit/vendor.nu --no-commit            # all repos, github tarballs (anonymous unless GH_TOKEN set)
nu toolkit/vendor.nu --local --no-commit    # all repos, rsync from sibling ../<repo>/ dirs (dev workflow)
nu toolkit/vendor.nu <repo> --no-commit     # just one repo from vendor.yml
```

**Always pass `--no-commit`.** `vendor.nu` auto-commits its result with a
generic `vendor: update <repo>` message by default — that has no body and
violates the Intent Preservation rule this skill exists to honor. `--no-commit`
leaves the changes unstaged so steps 2–4 below can compose richer per-repo
commits.

Default fetch is tarballs. Use `--local` only when the user has unpushed work
in sibling clones they want to vendor before pushing — confirm with them if
unclear. Without a `<repo>` arg, `vendor.nu` deletes and rewrites all of
`vendor/` from scratch; with one, it wipes and rewrites only that repo's dir.

## 2. Group the diff by repo

`vendor/` is laid out as `vendor/<repo>/<module>/...` where `<repo>` and
`<module>` come from `toolkit/vendor.yml` (authoritative). Each top-level
`vendor/<repo>/` dir with any change is one commit unit.

```nu
git status -s vendor/ | lines | each { split column ' ' status path }
| flatten | get path | split row '/' | get 0..1 | str join '/' | uniq
```

The `dotfiles` repo is an exception worth noting: it contains many per-app
modules (`broot/`, `claude/`, `helix/`, `lazygit/`, `nushell/`, `zellij/`,
`wezterm/`, ...). When changes span only one or two of those, prefer a tighter
subject like `vendor: updated dotfiles/zellij` and stage only that subdir. When
many apps changed at once, one `vendor: updated dotfiles` commit is fine.

## 3. Compose subject + body per repo

Subject conventions (verified against `git log --oneline -- vendor/`):

- Simple bump: `vendor: updated <repo>` (e.g. `vendor: updated nu-goodies`)
- Single-file bump: `vendor: updated <filename>` (e.g. `vendor: updated wezterm.lua`)
- Specific behavior change worth naming: `vendor: <repo> <short description>`
  (e.g. `vendor: dotfiles XDG_CONFIG_HOME fallback in env.nu`)

**Body MUST paraphrase what changed upstream.** Get it by reading the sibling
repo's git log between the previously-vendored revision and now:

```sh
git -C ../<repo> fetch
git -C ../<repo> log --oneline <last-vendored-sha>..HEAD
```

If the user knows the previously-vendored revision, ask. Otherwise diff the
just-rewritten `vendor/<repo>/` against the index (`git diff --staged
vendor/<repo>/`) and describe the substance — what behavior changed for the
user, not which lines moved.

If the upstream change is purely whitespace, formatting, or a re-run of
topiary, say so plainly in the body. Don't pad with fake reasoning — the
Intent Preservation rule means the body reflects the *actual* upstream intent,
not a generic "refresh".

## 4. Stage and commit per repo

```sh
git add vendor/<repo>/
git commit -m "<subject>" -m "<body>"
```

Files removed upstream show as `D` in `git status` — include them in the same
per-repo commit, don't split. If an entire repo disappeared (dropped from
`vendor.yml`), the subject should say `vendor: drop <repo>` and the body
should reference the `vendor.yml` change.

## 5. Report

List the commits created — one line each with subject. Note any repo where
the body is sparse because upstream history was unavailable; flag it so the
user can amend.

## Notes

- `toolkit/vendor.yml` is the source of truth for which repos and which
  submodule subdirs are vendored. If `vendor/` contains a repo not in
  `vendor.yml` after the run, that's a bug in `vendor.nu`, not something to
  commit around.
- `nutest` (vyadh/nutest) and `my-claude-skills` (maxim-uvarov/...) are
  third-party; their commit bodies should clearly attribute upstream rather
  than imply local authorship.
