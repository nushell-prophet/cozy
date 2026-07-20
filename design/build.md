---
human-check: pending   # pending | verified — flip to verified after you read it
covers:                # source paths update-design reconciles this file against
  - Dockerfile
  - cozy-module/install/run-install.sh
  - cozy-module/install/ensure-nu.sh
  - cozy-module/install/.nushell-version
  - cozy-module/install/bootstrap.nu
  - sbx-kit/spec.yaml
reconciled-at: 0eeb1329e2cc38cd941ba552592ecd09684ff189
---

# build — the boot sequence (the spine)

**Everything starts here.** Three entry paths converge on the same boot tail, [`../cozy-module/install/run-install.sh`](../cozy-module/install/run-install.sh) (ensure brew → `ensure-nu.sh` → `bootstrap.nu`) — the command sequence exists in that one script and nowhere else, so the environment is identical whether you build the image, install on a host, or layer the [`sbx` kit](https://docs.docker.com/ai/sandboxes/customize/kits/). The paths differ only in how the checkout lands:

- **Docker** — [`../Dockerfile`](../Dockerfile) COPYs the repo bits → `run-install.sh`
- **Host** — a git checkout → [`cozy-module/install/run-install.sh`](../cozy-module/install/run-install.sh)
- **sbx kit** — [`../sbx-kit/spec.yaml`](../sbx-kit/spec.yaml) clones the repo in-sandbox → `run-install.sh`

This file walks the [`Dockerfile`](../Dockerfile) top to bottom, then `bootstrap.nu`'s steps 0–9 in order, and links out to the other design files at the step where each is reached. **This order is the canonical order for the whole project** — README, CLAUDE.md, and every other design file mirror it. Change the order here and propagate it everywhere.

`bootstrap.nu` auto-detects its mode (no flags): a container marker present ([`/etc/sandbox-persistent.sh`](https://docs.docker.com/ai/sandboxes/faq/#how-do-i-set-custom-environment-variables-inside-a-sandbox) from the sbx base image, or `/.dockerenv` for non-sbx container bases) → run the container system setup (Step 0); `/tmp/vendor` present → use the Docker-staged vendor as-is; else → use the committed [`vendor/`](../vendor/). Re-run = clean setup; idempotency is not a goal.

## Dockerfile

The Dockerfile builds the **Debian rootless** run path — plain `docker run` and Apple `container`, **in testing** (`sbx` never touches it; it uses the kit). Its point is least privilege: the `agent` gets passwordless sudo only during the build (apt, brew's chown, the tree-sitter compile), revoked in the final layer, so the running container can't escalate. Debian slim ships none of the sbx template's agent tooling, so the early layers add it back. It still defines the canonical order. In order:

1. `FROM debian:12-slim`.
2. **Root build layer** — rewrite apt sources `http://` → `https://` (the VM allows :443, not :80; TLS peer-verify is off for this first apt because the CA bundle isn't installed yet — apt still verifies packages via gpg), then `apt-get install` sudo, ca-certificates, curl, git, build-essential, procps, file, rsync, ripgrep, jq. build-essential/procps/file back Homebrew's Linux toolchain requirement; rsync backs `install-skills` (Step 5); rg + jq replace agent tools the template bundled (kept on apt so the shared brew list stays untouched).
3. Create the `agent` user (uid/gid 1000) and grant passwordless sudo via a `/etc/sudoers.d/agent-build` drop-in — **build-only**, deleted in the final layer.
4. Ship the `/etc/sandbox-persistent.sh` marker (BuildKit makes no `/.dockerenv` at build time, so this is what fires bootstrap Step 0) and add a source line to `/etc/bash.bashrc` for interactive shells. `USER agent`.
5. Install Homebrew — cache-priming only: `run-install.sh` auto-installs brew when it's missing, so this layer is optional for correctness; it keeps brew out of the uncached tail.
6. `ENV` blocks — `PATH` puts `~/.local/bin` first (so a pinned `nu` shadows brew's), then `~/.cargo/bin` (so cargo-built binaries from `cozy install nushell`/`zellij` shadow brew's — bootstrap creates the dir up front so exists-filtered PATHs like dotfiles `env.nu` keep it before rust is installed), then linuxbrew; plus `HELIX_RUNTIME`, `HOME`, `TERM*`, `LANG`, and the `XDG_*` dirs. Also `HOMEBREW_NO_ASK=1` (brew's "Do you want to proceed?" prompt hangs forever without a TTY) and `HOMEBREW_NO_AUTO_UPDATE=1` (skip the implicit `brew update` — faster, and bottle versions stay fixed); `ensure-nu.sh` and `bootstrap.nu` export the same pair so the host path is covered too. `bootstrap.nu` Step 0 mirrors this block into `/etc/sandbox-persistent.sh` for in-sandbox re-runs; [`sbx-kit/spec.yaml`](../sbx-kit/spec.yaml)'s `environment.variables` mirrors it for the kit.
7. `brew install nushell` — cache-priming too: `ensure-nu.sh` (via `run-install.sh`) installs `nu` when it's absent.
8. `COPY` repo bits — `vendor/` → `/tmp/vendor/` (bootstrap fans it out under `~/repos/`); [`cozy-module/`](../cozy-module/) + [`docker-files/`](../docker-files/) → `~/repos/cozy/`, so `bootstrap.nu` resolves `cozy_root` from `path self` (three dirnames up).
9. `RUN run-install.sh` — the shared boot tail: ensure brew (no-op here) → `ensure-nu.sh` (see below) → `nu bootstrap.nu` (steps 0–9 below).
10. `COPY workspace-README.md` → `~/workspace/README.md`. See [`autoload.md`](autoload.md).
11. **Final root layer** (kept last so editing it doesn't invalidate the cached brew layers) — write `/etc/profile.d/cozy.sh` (brew shellenv + the per-user PATH prepend + source `/etc/sandbox-persistent.sh`) so login shells — including the `bash -lc` `cozy verify` reads env through — regain the PATH additions and the cozy env block that `/etc/profile` rebuilds away; then delete the sudoers drop-in to revoke the build-time privilege. `USER agent`.

## ensure-nu.sh

Ensure `nu` can parse `bootstrap.nu`. Tries latest brew `nu` first; if it can't parse (nushell is pre-1.0 and syntax drifts between releases), downloads the pinned version from [`../cozy-module/install/.nushell-version`](../cozy-module/install/.nushell-version) into `~/.local/bin/nu`, which shadows brew's `nu` via the `PATH` order above. If even the pinned version can't parse it, `bootstrap.nu` has a real bug — fail loudly rather than install a broken environment.
**Code:** [`cozy-module/install/ensure-nu.sh`](../cozy-module/install/ensure-nu.sh)

## bootstrap.nu — install steps

Entry: `export def main [--force]`. `--force` skips the host-install clobber guard. The installer consumes the committed `vendor/` snapshot as-is and never fetches modules — refreshing `vendor/` (from upstream or siblings) is [`toolkit/vendor.nu`](../toolkit/vendor.nu)'s job, run before a build.
**Code:** [`cozy-module/install/bootstrap.nu`](../cozy-module/install/bootstrap.nu) → `export def main`

### Step 0 — system setup (container) / clobber guard (host)
Gated on a container marker: `/etc/sandbox-persistent.sh` (shipped by the sbx base image) or `/.dockerenv` (non-sbx container bases — marker-only gating made those silently take the host branch). **Container:** `setup-docker-system` wipes colliding `config.nu`/`env.nu`, rewrites apt sources `http://` → `https://` (the VM allows :443, not :80), `apt-get install` procps/file/gcc/libc6-dev (gcc + libc6-dev are needed for the tree-sitter-nu compile in Step 8), and writes the runtime env-export block (marker-wrapped) into `/etc/sandbox-persistent.sh` (created when only `/.dockerenv` was present). **Host** (markers absent): `check-no-clobber` refuses to overwrite existing user configs unless `--force` or the `~/.cozy-installed` stamp is present.
**Code:** `bootstrap.nu` → `def setup-docker-system`, `def check-no-clobber`

### Before Step 1 — gcc fail-fast + pbcopy shim
Two guards in `main` between Step 0 and the brew installs. A Linux **host** without gcc fails before anything is modified — Step 8 compiles the tree-sitter-nu grammar, containers get gcc from Step 0's apt install, but the flow won't sudo mid-install, so surface it up front (macOS is covered via the Xcode CLT brew requires). Then the `pbcopy` shim is installed to `~/.local/bin` on every Linux, container or host — the dotfiles deployed in Step 4 call `pbcopy` and Linux has no native one; a user's own non-cozy `pbcopy` on PATH is never shadowed. See [`autoload.md`](autoload.md).
**Code:** `bootstrap.nu` → `export def main` (pre-Step-1 block)

### Step 1 — brew installs
`brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd jj git-lfs`, then `brew cleanup --prune=all`. Errors if brew is missing.

### Step 2 — XDG git config
Writes `~/.config/git/{config,ignore}`: identity `Agent <agent@sandbox>` (so Step 4 can commit), `safe.directory=*`, `gc.auto=0`, `core.fsync=all`. XDG (not `/etc/gitconfig`) avoids sudo and is overridden by a real user's `~/.gitconfig`, so a personal identity still wins.

### Step 3 — populate ~/repos/
`populate-repos` mirrors `cozy-module/` + `docker-files/` to `~/repos/cozy/` (skipped in Docker, where the `COPY` already did it), then fans out every vendored module from `/tmp/vendor` (Docker) or `cozy_root/vendor/` into `~/repos/`. The source is used as-is; an empty source is a corrupt checkout and errors out. See [`modules.md`](modules.md).
**Code:** `bootstrap.nu` → `def populate-repos`

### Step 3.5 — nushell autoload
Wipes `~/.config/nushell/autoload/` (cozy owns it; stale files from removed-upstream scripts must not accumulate), then copies `docker-files/nushell-autoload/*.nu` into it. See [`autoload.md`](autoload.md).

### Steps 4 & 5 — dotfiles + skills
From `~/repos/dotfiles`, spawns nu to run `toolkit push-to-machine --force --create-dirs --docker --commit-existing --commit-changes` (deploys helix/zellij/lazygit/broot/nushell/jj/wezterm configs; `--commit-existing` snapshots pre-existing destination files before the forced overwrite, so a re-run can't silently lose in-sandbox config edits) then `toolkit install-skills --all`. Always `--docker` because cozy only vendors the docker paths file. Config sources live in the `dotfiles` repo — see [`modules.md`](modules.md).

### Step 6 — global Claude instructions
Appends [`docker-files/global-claude.md`](../docker-files/global-claude.md) (the tool catalog) to `~/.claude/CLAUDE.md`.

### Step 7 — broot init
`broot --write-default-conf` + `--set-install-state installed` (moved here from the Dockerfile so host installs get it too).

### Step 8 — topiary install
Symlinks the vendored `~/repos/topiary-nushell` to `~/git/topiary-nushell` (where `topiary.nu` looks), then runs `topiary install`. No clone fallback — if the vendored grammar is missing it fails loudly (fail-fast). See [`install.md`](install.md) for what `topiary install` does.
**Code:** `bootstrap.nu` (Step 8 block) → `topiary install`

### Step 9 — Claude Code + nushell MCP
`claude install` (see [`install.md`](install.md)), then `claude mcp add --scope user --transport stdio nushell -- nu --mcp`, then merges `externalEditorContext: true` into `~/.claude.json`. Finally writes the `~/.cozy-installed` stamp (last, so a partial failure leaves no stamp and forces `--force` to recover) and, if env exports were just written but the current shell predates them, prints a "run `exec bash -l`" note.

## run-install.sh (the shared boot tail)

The one script every path runs. Ensures brew — auto-installs only on Linux with passwordless sudo (the sbx case; it then `eval`s `brew shellenv`, since the installer never touches the calling shell's PATH), fails fast with a copy-paste snippet on macOS (keeps password prompts out of the no-prompt flow). Then `ensure-nu.sh`, then `nu bootstrap.nu "$@"`. On hosts (no container markers — same detection as bootstrap.nu Step 0) it finally appends an `XDG_CONFIG_HOME` export to the user's shell rc (so macOS `nu` reads `~/.config/nushell/` instead of `~/Library/Application Support/`).
**Code:** [`cozy-module/install/run-install.sh`](../cozy-module/install/run-install.sh)

## sbx-kit/spec.yaml (sbx kit)

A [`mixin`](https://docs.docker.com/ai/sandboxes/customize/kit-reference/#top-level-fields) kit that layers cozy on the standard [`shell`](https://docs.docker.com/ai/sandboxes/agents/shell/) agent. [`environment.variables`](https://docs.docker.com/ai/sandboxes/customize/kit-reference/#environment) mirrors the Dockerfile `ENV`; [`commands.install`](https://docs.docker.com/ai/sandboxes/customize/kit-reference/#install) is two steps: clone cozy (the one step that can't live in `run-install.sh` — the script doesn't exist in-sandbox until the clone lands) → `run-install.sh`, its output redirected to `~/cozy-install.log` (sbx swallows install-command stdout with no flag to show it, so the log is the only way to watch progress or read back a failure — `sbx exec -it <name> tail -f ~/cozy-install.log` from a second terminal). No [`files/`](https://docs.docker.com/ai/sandboxes/customize/kit-reference/#static-files) tree — the repo is cloned in-sandbox, so `cozy_root` lines up via `path self`. [`network.allowedDomains`](https://docs.docker.com/ai/sandboxes/customize/kit-reference/#network) is provisional (derived by walking the install path; verify on a real [`sbx run`](https://docs.docker.com/reference/cli/sbx/run/)).
**Code:** [`sbx-kit/spec.yaml`](../sbx-kit/spec.yaml)
