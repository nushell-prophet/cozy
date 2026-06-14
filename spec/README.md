---
human-check: verified # pending | verified — flip to verified after you read it
---

# cozy spec

The full functional reference for cozy. Read this map first, then open only the subsystem file you need. Each entry below is one screen; the linked files hold the per-command contracts.

This spec sits between `../CLAUDE.md` (terse ops facts) and the code. Read it *instead of* grepping the whole codebase. It describes **what each piece does, its flags, and its side effects**, then links to the code by symbol — it never copies the code. Command purposes are reused verbatim from each command's own doc comment; the full rationale stays at the code anchor.

**Everything starts from the `../Dockerfile`.** The spec is ordered to follow the build sequence: base image → Homebrew → ENV → cached `nu` → `COPY` repo bits → `ensure-nu.sh` → hand off to `bootstrap.nu`, which runs the install steps in order. The subsystem list below follows that same flow, and each file walks its own commands in the order the Dockerfile and `bootstrap.nu` reach them — preserve that order when editing.

## Subsystems

The build sequence, in order:

- `build.md` — the spine. Walks the `Dockerfile` top to bottom, then `bootstrap.nu`'s steps 0–9 in order. The single installer is shared by the Docker build, the host `bootstrap.sh`, and the `sbx` kit; `ensure-nu.sh` handles the nu version fallback. Every other subsystem below is reached from a step here.

- `install.md` — the per-tool builders, some of which `bootstrap.nu` invokes (and all of which are available to the user in the environment via `cozy install`), in `install/mod.nu` export order: `claude`, `rust`, `polars`, `topiary`, `zellij`, `nushell`, `nu-plugin-image`.

- `modules.md` — vendored Nushell modules fanned out under `~/repos/` by `bootstrap.nu` Step 3 (nu-goodies, claude-nu, nu-kv, dotnu, numd, nu-cmd-stack, nutest, nu-multiproof) — pointers plus the in-sandbox command surface the user actually touches. Internals live in each module's own repo.
  > Per-module specs are expected to move *into the modules themselves* over time and be reconciled back here. The modules are separate repos for distribution and historical reasons, but cozy is their main customer now — their development follows cozy's needs.

- `autoload.md` — the `docker-files/` bits shipped into the sandbox by `bootstrap.nu` Step 3.5 onward: nushell autoload scripts (MCP server, module imports, completions, aliases, git-safe-directory), the `pbcopy` shim, and the global CLAUDE.md tool catalog.

After the build — used inside the running sandbox:

- `cozy-module.md` — the `cozy` command surface: `sync-repos`, `mount init`, `dev-link`, `git-harden`, `swap-zellij-super`, `configure`, `sandbox-state`, `logo`. (`cozy install` is its own sub-surface — see `install.md`.)

Outside the build — run on the host:

- `toolkit.md` — dev kit: `sandbox` (build/recreate images), `vendor` (refresh `vendor/` from GitHub or sibling repos), `docs`, and `test` (smoke-test a fresh sandbox).

## Maintaining this spec

Run `/update-spec` after changing any command, flag, or doc comment. It reconciles each entry against the code (does the anchor resolve? does the Purpose still match the doc comment? do the flags still match the signature?) and patches in place.
