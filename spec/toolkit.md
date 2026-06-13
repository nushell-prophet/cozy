---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-spec reconciles this file against
  - toolkit/mod.nu
  - toolkit/sandbox.nu
  - toolkit/vendor.nu
  - toolkit/docs.nu
  - toolkit/test.nu
  - toolkit/vendor.yml
---

# toolkit (host-side dev kit)

The build/dev kit run **on the host**, not inside the sandbox. It builds and recreates
images, refreshes the vendored modules, syncs docs, and smoke-tests a fresh sandbox.
Exports are wired in [`toolkit/mod.nu`](../toolkit/mod.nu), which re-exports three
sub-surfaces in this order: `sandbox`, `vendor`, `docs`. `test` lives in its own file,
run directly (`nu toolkit/test.nu test`).

Each entry: **Purpose** is the first line of the command's own doc comment (verbatim).
**Flags** are derived from the signature. **Code** points at the symbol; the full
rationale stays there.

> NOTE: `cozy/CLAUDE.md` and `spec/README.md` reference `toolkit/pack-kit.nu` (said to
> generate `kit/files/`) and a `toolkit docs` command for the `sbx` kit. No `pack-kit.nu`
> exists under `toolkit/` (or anywhere in `cozy/`). Stale doc reference — see summary.

## toolkit sandbox
No doc comment; `export def main [] { help sandbox }` just prints sub-help.
> NOTE: missing Purpose doc comment on `sandbox.nu` `main`.
**Code:** `toolkit/sandbox.nu` → `export def main`

### toolkit sandbox build
Build Docker image with auto-incremented vN tag, recreate existing sandboxes
**Flags:** `--image (-i): string = "cozy"`; `--path (-p): path` (default `pwd`);
`--recreate: string` (sandbox name, completed); `--recreate-all`
**Code:** `toolkit/sandbox.nu` → `export def build`

### toolkit sandbox run
Run sandbox with latest image tag
**Flags:** positional `project_path?: path` (default `$PWD`); `--image (-i): string = "cozy"`
**Code:** `toolkit/sandbox.nu` → `export def run`

### toolkit sandbox ls
List sandboxes as a table
**Code:** `toolkit/sandbox.nu` → `export def ls`

### toolkit sandbox stop
Stop sandbox(es)
**Flags:** rest `...name: string` (sandbox names, completed)
**Code:** `toolkit/sandbox.nu` → `export def stop`

### toolkit sandbox rm
Remove sandbox(es)
**Flags:** rest `...name: string` (sandbox names, completed)
**Code:** `toolkit/sandbox.nu` → `export def rm`

## toolkit vendor
Refresh vendored modules and configs into vendor/
**Flags:** positional `repo?: string` (one repo from `vendor.yml`, completed; omit for
all); `--local (-l)` (rsync from sibling `~/repos/` instead of GitHub tarballs);
`--no-commit` (skip the auto git commit). Wipes the whole `vendor/` when refreshing all,
else just the target repo's dir.
**Code:** `toolkit/vendor.nu` → `export def main`

### toolkit vendor check
Check for nushell-prophet repos not yet in vendor.yml
**Flags:** `--add (-a)` (append the new repos to `vendor.yml` with default modules)
**Code:** `toolkit/vendor.nu` → `export def "main check"`

> `toolkit/vendor.yml` is the source of truth for which modules are vendored: each entry
> is `{repo, github, modules}`, where `modules` lists the subdirs (or files) copied out of
> the upstream repo into `vendor/<repo>/`. Read by `vendor.nu` via `load-modules`.

## toolkit docs
Sync Docker sandbox docs to local markdown.
Downloads a fixed page list (sandbox docs + `docker sandbox` CLI reference) as markdown
into `docs.docker.com/` — its own git repo, gitignored by cozy — then commits. Idempotent;
run from the `cozy/` directory.
**Code:** `toolkit/docs.nu` → `export def main`

## toolkit/test.nu

Standalone smoke test, not wired into `mod.nu`. Run with `nu toolkit/test.nu test`.
Creates a fresh `claude-test` sandbox, waits for readiness, then checks tools launch,
files/dirs exist, env vars match, and the MCP + pbcopy wiring is in place.

### test (test.nu)
No doc comment; `export def main [] { help main }` just prints sub-help.
> NOTE: missing Purpose doc comment on `test.nu` `main`.
**Code:** `toolkit/test.nu` → `export def main`

### test test
Run checks against a fresh sandbox, clean up after
**Flags:** `--tag (-t): string = "latest"`; `--keep (-k)` (keep sandbox after tests)
**Code:** `toolkit/test.nu` → `export def "main test"`

### test clean
Remove leftover test sandbox
**Code:** `toolkit/test.nu` → `export def "main clean"`
