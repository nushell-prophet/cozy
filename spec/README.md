---
human-check: pending # pending | verified — flip to verified after you read it
---

# cozy spec

**Why cozy is built the way it is, and in what order.** Read this map first, then open the one subsystem file you need.

This is not a command reference. The Nushell modules are self-documenting — `help <cmd>` and the doc comments are the source of truth for *what* each command does and its flags. Duplicating that here only rots. So this spec holds the part no single script can carry: the **build order** (it spans the `../Dockerfile`, `bootstrap.nu`, and the kit) and the **motivation** — why each tool is compiled from source, why each module is vendored, why each file ships into the sandbox.

It sits between `../CLAUDE.md` (terse ops facts) and the code, and links to code by symbol — it never copies the code.

**Everything starts from the `../Dockerfile`.** The spec follows the build sequence: base image → Homebrew → ENV → cached `nu` → `COPY` repo bits → `ensure-nu.sh` → `bootstrap.nu`, which runs the install steps in order. Each file walks its own part in that same order — preserve it when editing.

## Subsystems

The build sequence, in order:

- `build.md` — the spine. Walks the `Dockerfile` top to bottom, then `bootstrap.nu`'s steps 0–9. The single installer is shared by the Docker build, the host `bootstrap.sh`, and the `sbx` kit. Every other file is reached from a step here.

- `install.md` — why the per-tool builders compile from source (and why they're exposed as `cozy install` for on-demand rebuilds inside the sandbox).

- `modules.md` — why the Nushell modules are vendored and how they load. Pointers only; what each command does lives in the module's own repo and in `../README.md`.

- `autoload.md` — the `docker-files/` shipped into the sandbox and why each one is needed (self-healing config, the `pbcopy` shim, the global CLAUDE.md tool catalog).

Host-side build tooling:

- `toolkit.md` — how images get built and modules get vendored from the host. The mechanism and its source of truth, not a command catalog.

## Maintaining this spec

Run `/update-spec` after changing the build order, an install step, or the reason something is packaged. It checks that the build sequence still matches the code and the rationale still holds — not flags or command contracts, which the code documents itself.
