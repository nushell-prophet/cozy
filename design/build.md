---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - Dockerfile
  - cozy-module/install/run-install.sh
  - cozy-module/install/ensure-nu.sh
  - cozy-module/install/.nushell-version
  - cozy-module/install/bootstrap.nu
  - sbx-kit/spec.yaml
reconciled-at: 03a87ce2f81ce9eadf5835c34f9e6f4288a050c5
---

# build — the boot sequence (the spine)

**Everything starts here.** Three entry paths converge on the same boot tail, `../cozy-module/install/run-install.sh` (ensure brew → `ensure-nu.sh` → `bootstrap.nu`) — the command sequence exists in that one script and nowhere else, so the environment is identical whether you build the image, install on a host, or layer the `sbx` kit. The paths differ only in how the checkout lands:

- **Docker** — `../Dockerfile` COPYs the repo bits → `run-install.sh`
- **Host** — a git checkout → `cozy-module/install/run-install.sh`
- **sbx kit** — `../sbx-kit/spec.yaml` clones the repo in-sandbox → `run-install.sh`

This file walks the `Dockerfile` top to bottom, then `bootstrap.nu`'s steps 0–9 in order, and links out to the other design files at the step where each is reached. **This order is the canonical order for the whole project** — README, CLAUDE.md, and every other design file mirror it. Change the order here and propagate it everywhere.

`bootstrap.nu` auto-detects its mode (no flags): `/etc/sandbox-persistent.sh` present → run the Docker system setup (Step 0); `/tmp/vendor` present → use the Docker-staged vendor as-is; else → use the committed `vendor/`. Re-run = clean setup; idempotency is not a goal.

## Dockerfile

The Dockerfile is deliberately thin — it stages bits and hands off. In order:

1. `FROM docker/sandbox-templates:shell` — Ubuntu base with git, curl, Python, Node.js, Go, ripgrep, jq, gh. `USER agent`.
2. Install Homebrew — cache-priming only: `run-install.sh` auto-installs brew when it's missing, so this layer is optional for correctness; it keeps brew out of the uncached tail.
3. `ENV` blocks — `PATH` puts `~/.local/bin` first (so a pinned `nu` shadows brew's), then linuxbrew; plus `HELIX_RUNTIME`, `HOME`, `TERM*`, `LANG`, and the `XDG_*` dirs. `bootstrap.nu` Step 0 mirrors this block into `/etc/sandbox-persistent.sh` for in-sandbox re-runs; `sbx-kit/spec.yaml`'s `environment.variables` mirrors it for the kit.
4. `brew install nushell` — cache-priming too: `ensure-nu.sh` (via `run-install.sh`) installs `nu` when it's absent.
5. `COPY` repo bits — `vendor/` → `/tmp/vendor/` (bootstrap fans it out under `~/repos/`); `cozy-module/` + `docker-files/` → `~/repos/cozy/`, so `bootstrap.nu` resolves `cozy_root` from `path self` (three dirnames up).
6. `RUN run-install.sh` — the shared boot tail: ensure brew (no-op here) → `ensure-nu.sh` (see below) → `nu bootstrap.nu` (steps 0–9 below).
7. `COPY workspace-README.md` → `~/workspace/README.md` — the only step after bootstrap. See `autoload.md`.

## ensure-nu.sh

Ensure `nu` can parse `bootstrap.nu`. Tries latest brew `nu` first; if it can't parse (nushell is pre-1.0 and syntax drifts between releases), downloads the pinned version from `../cozy-module/install/.nushell-version` into `~/.local/bin/nu`, which shadows brew's `nu` via the `PATH` order above. If even the pinned version can't parse it, `bootstrap.nu` has a real bug — fail loudly rather than install a broken environment.
**Code:** `cozy-module/install/ensure-nu.sh`

## bootstrap.nu — install steps

Entry: `export def main [--force]`. `--force` skips the host-install clobber guard. The installer consumes the committed `vendor/` snapshot as-is and never fetches modules — refreshing `vendor/` (from upstream or siblings) is `toolkit/vendor.nu`'s job, run before a build.
**Code:** `cozy-module/install/bootstrap.nu` → `export def main`

### Step 0 — system setup (Docker) / clobber guard (host)
Gated on the `/etc/sandbox-persistent.sh` marker the base image ships. **Docker:** `setup-docker-system` wipes colliding `config.nu`/`env.nu`, rewrites apt sources `http://` → `https://` (the VM allows :443, not :80), `apt-get install` procps/file/gcc/libc6-dev (gcc + libc6-dev are needed for the tree-sitter-nu compile in Step 8), installs the `pbcopy` shim to `~/.local/bin`, and writes the runtime env-export block (marker-wrapped) into `/etc/sandbox-persistent.sh`. **Host** (marker absent): `check-no-clobber` refuses to overwrite existing user configs unless `--force` or the `~/.cozy-installed` stamp is present.
**Code:** `bootstrap.nu` → `def setup-docker-system`, `def check-no-clobber`

### Step 1 — brew installs
`brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd jj git-lfs`, then `brew cleanup --prune=all`. Errors if brew is missing.

### Step 2 — XDG git config
Writes `~/.config/git/{config,ignore}`: identity `Agent <agent@sandbox>` (so Step 4 can commit), `safe.directory=*`, `gc.auto=0`, `core.fsync=all`. XDG (not `/etc/gitconfig`) avoids sudo and is overridden by a real user's `~/.gitconfig`, so a personal identity still wins.

### Step 3 — populate ~/repos/
`populate-repos` mirrors `cozy-module/` + `docker-files/` to `~/repos/cozy/` (skipped in Docker, where the `COPY` already did it), then fans out every vendored module from `/tmp/vendor` (Docker) or `cozy_root/vendor/` into `~/repos/`. The source is used as-is; an empty source is a corrupt checkout and errors out. See `modules.md`.
**Code:** `bootstrap.nu` → `def populate-repos`

### Step 3.5 — nushell autoload
Wipes `~/.config/nushell/autoload/` (cozy owns it; stale files from removed-upstream scripts must not accumulate), then copies `docker-files/nushell-autoload/*.nu` into it. See `autoload.md`.

### Steps 4 & 5 — dotfiles + skills
From `~/repos/dotfiles`, spawns nu to run `toolkit push-to-machine --force --create-dirs --docker --commit-changes` (deploys helix/zellij/lazygit/broot/nushell/jj/wezterm configs) then `toolkit install-skills --all`. Always `--docker` because cozy only vendors the docker paths file. Config sources live in the `dotfiles` repo — see `modules.md`.

### Step 6 — global Claude instructions
Appends `docker-files/global-claude.md` (the tool catalog) to `~/.claude/CLAUDE.md`.

### Step 7 — broot init
`broot --write-default-conf` + `--set-install-state installed` (moved here from the Dockerfile so host installs get it too).

### Step 8 — topiary install
Symlinks the vendored `~/repos/topiary-nushell` to `~/git/topiary-nushell` (where `topiary.nu` looks), then runs `topiary install`. No clone fallback — if the vendored grammar is missing it fails loudly (fail-fast). See `install.md` for what `topiary install` does.
**Code:** `bootstrap.nu` (Step 8 block) → `topiary install`

### Step 9 — Claude Code + nushell MCP
`claude install` (see `install.md`), then `claude mcp add --scope user --transport stdio nushell -- nu --mcp`, then merges `externalEditorContext: true` into `~/.claude.json`. Finally writes the `~/.cozy-installed` stamp (last, so a partial failure leaves no stamp and forces `--force` to recover) and, if env exports were just written but the current shell predates them, prints a "run `exec bash -l`" note.

## run-install.sh (the shared boot tail)

The one script every path runs. Ensures brew — auto-installs only on Linux with passwordless sudo (the sbx case; it then `eval`s `brew shellenv`, since the installer never touches the calling shell's PATH), fails fast with a copy-paste snippet on macOS (keeps password prompts out of the no-prompt flow). Then `ensure-nu.sh`, then `nu bootstrap.nu "$@"`. On hosts (no container marker — same detection as bootstrap.nu Step 0) it finally appends an `XDG_CONFIG_HOME` export to the user's shell rc (so macOS `nu` reads `~/.config/nushell/` instead of `~/Library/Application Support/`).
**Code:** `cozy-module/install/run-install.sh`

## sbx-kit/spec.yaml (sbx kit)

A `mixin` kit that layers cozy on the standard `shell` agent. `environment.variables` mirrors the Dockerfile `ENV`; `commands.install` is two steps: clone cozy (the one step that can't live in `run-install.sh` — the script doesn't exist in-sandbox until the clone lands) → `run-install.sh`. No `files/` tree — the repo is cloned in-sandbox, so `cozy_root` lines up via `path self`. `network.allowedDomains` is provisional (derived by walking the install path; verify on a real `sbx run`).
**Code:** `sbx-kit/spec.yaml`
