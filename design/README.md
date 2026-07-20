---
human-check: pending # pending | verified — flip to verified after you read it
---

# cozy design

**Why cozy is built the way it is, and in what order.** Read this map first, then open the one subsystem file you need.

This is not a command reference. The Nushell modules are self-documenting — `help <cmd>` and the doc comments are the source of truth for *what* each command does; duplicating that here only rots. So these notes hold the part no single script can carry: the **build order** (it spans the [`../Dockerfile`](../Dockerfile), `bootstrap.nu`, and the kit) and the **motivation** — why each tool is compiled from source, why each module is vendored, why each file ships into the sandbox. They sit between [`../CLAUDE.md`](../CLAUDE.md) (terse ops facts) and the code, linking to it by symbol, never copying.

**Everything converges on the boot tail.** These notes follow the build sequence in execution order: an entry point puts the repo on disk — the [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml) kit (primary) clones it in-sandbox, the [`../Dockerfile`](../Dockerfile) (secondary) COPYs it into an image — then both call `run-install.sh` (→ `ensure-nu.sh` → `bootstrap.nu`), which runs the install steps in order. Each file walks its own part in that same order — preserve it when editing.

## Subsystems

The build sequence, in order:

- [`build.md`](build.md) — the spine. Walks the two entry points (the `sbx` kit, then the [`Dockerfile`](../Dockerfile) top to bottom), then the boot tail they share — [`cozy-module/install/run-install.sh`](../cozy-module/install/run-install.sh) → `ensure-nu.sh` → `bootstrap.nu`'s steps 0–9. A host checkout runs the same tail. Every other file is reached from a step here.

- [`install.md`](install.md) — why the per-tool builders compile from source (and why they're exposed as `cozy install` for on-demand rebuilds inside the sandbox).

- [`modules.md`](modules.md) — why the Nushell modules are vendored and how they load. Pointers only; what each command does lives in the module's own repo and in [`../README.md`](../README.md).

- [`autoload.md`](autoload.md) — the [`docker-files/`](../docker-files/) shipped into the sandbox and why each one is needed (self-healing config, the `pbcopy` shim, the global CLAUDE.md tool catalog).

Host-side build tooling:

- [`toolkit.md`](toolkit.md) — how modules get vendored and the build's invariants get checked, from the host. The mechanism and its source of truth, not a command catalog.

## Maintaining these notes

Run `/update-design` after changing the build order, an install step, or the reason something is packaged. It checks that the build sequence still matches the code and the rationale still holds — not flags or command contracts, which the code documents itself.
