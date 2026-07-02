---
task-name: install paths audit — sbx kit / Dockerfile / host-install.sh
status: draft
created: '20260702-215200 #yyyyMMdd-hhmmss'
updated: '20260702-215200 #yyyyMMdd-hhmmss'
original_session: 08d41519-11d5-4a07-ba92-022e10afb0a8
related_files:
  - Dockerfile
  - sbx-kit/spec.yaml
  - host-install.sh
  - cozy-module/install/bootstrap.nu
  - cozy-module/install/ensure-nu.sh
  - cozy-module/install/topiary.nu
  - cozy-module/install/claude.nu
  - toolkit/check.nu
  - cozy-module/verify.nu
  - README.md
  - design/build.md
---

# Install paths audit — problems, inconsistencies, refactoring opportunities

## Task from user (original)

> I @README.md it's stated that we have 3 ways of installing `cozy`: 1. `sbx` 2. Dockerfile (which has comments that it is not maintained, but I want to keep it in sync in case I decide to use `apple container`) 3. Just fresh ubuntu or macos machines.
>
> don't spare tokens, investigate the current setup steps, find potential problems and inconsistencies between methods (both sbx and Dockerfile should result in the same functionality), find refactoring opportunities to make the setup process more robust, maintainable and reliable.
>
> Document your findings in a new todo inside of todo/

## Task description (extended version)

Audit of the three install paths along four projections: env-var propagation, installed-artifact parity, failure modes / re-run behavior, and docs-vs-code claims. Four subagents swept the paths independently; contested findings were re-verified against the code by hand. Every finding below carries `file:line` evidence. Severity tags: **hang** (install blocks forever), **break** (functionality lost), **parity** (paths diverge), **drift** (no guard, will diverge later), **doc** (text wrong).

Baseline fact that drives most findings: all three paths converge on `bootstrap.nu`, but its Step 0 (`setup-docker-system` — apt deps, pbcopy shim, `/etc/sandbox-persistent.sh` env block) is gated on the marker file `/etc/sandbox-persistent.sh` that only the sbx base image ships (`bootstrap.nu:52`). sbx kit and Dockerfile both have the marker, so **those two paths are in good parity today**. Everything without the marker (fresh Ubuntu, macOS, an Apple container on stock Ubuntu) silently takes the "host" branch and loses all of Step 0.

## Findings

### A. Hangs and masked failures

- **A1 — kit's cozy clone can hang on a git credential prompt.** `sbx-kit/spec.yaml:71` runs `git clone` without `GIT_TERMINAL_PROMPT=0`. Every other clone in the tree goes through `_clone-or-fail.nu:9` which sets it. A 404/renamed repo or proxy 401 makes git prompt for a username with no TTY. This exact failure class motivated `_clone-or-fail` (CHANGELOG `c495b22`). Fix: prefix the command with `GIT_TERMINAL_PROMPT=0 `.
- **A2 — host path can hang at `brew install nushell` inside `ensure-nu.sh`.** `ensure-nu.sh:19` runs brew before `bootstrap.nu:45-46` sets `HOMEBREW_NO_ASK`/`HOMEBREW_NO_AUTO_UPDATE`, and `host-install.sh` never exports them (Dockerfile:36-37 and spec.yaml:31-32 cover their paths). In a non-TTY host context — e.g. the "pure `shell` agent" case README.md:34 names — brew's "Do you want to proceed?" blocks forever. Same class as the 0.3.1 fix `3645ca8`, which missed this leg. Fix: export both at the top of `ensure-nu.sh` (covers every caller).
- **A3 — `curl | bash` masks Homebrew-installer download failure.** `Dockerfile:14-15` and `spec.yaml:76`: if curl fails, `$(...)` yields an empty script, bash exits 0, the step "succeeds", and the build dies two commands later with `brew: not found`. Kit install output is not retained after the run, so the real cause is invisible. Fix: download to a file first (`curl -fsSL ... -o f && bash f`), so curl's exit code aborts the step.
- **A4 — host sudo leak: bootstrap is not sudo-free on hosts.** Step 0 is skipped on hosts, but Step 8 reaches `topiary.nu:74-75` `sudo apt-get install gcc libc6-dev` when gcc is missing. Without passwordless sudo this prompts (interactive) or fails (non-TTY) at the 8th step of an otherwise prompt-free flow. macOS is fine (CLT gcc shim exists because brew requires CLT; the `topiary.nu:78` error path is a rarely-firing net). Fix: fail fast at bootstrap start on Linux hosts without gcc, with an "install gcc/libc6-dev first" message — or document the requirement.

### B. Mode detection — the Apple-container blocker

- **B1 — the Dockerfile only produces cozy's full functionality on the sbx base image.** Mode detection is "marker file exists" (`bootstrap.nu:52`), not "am I in a container". Rebasing the Dockerfile onto any other base (the stated Apple-container plan) silently takes the host branch: no apt deps (`procps file gcc libc6-dev`), no pbcopy shim, no `/etc/sandbox-persistent.sh` env block (`XDG_*`, `HELIX_RUNTIME`, `LANG`, `GIT_AUTHOR_*`, `JJ_CONFIG`, MOTD) — yet still writes the `~/.cozy-installed` stamp (`bootstrap.nu:164`) and looks installed. `check-no-clobber` would also fire mid-docker-build on a non-empty base. **This is the single most important thing to fix before the Apple-container experiment.** Direction: replace implicit marker-gating with an explicit mode (`--mode docker|host` flag, or detect container via `/.dockerenv` and create the env file cozy needs instead of requiring it). Decision needed on mechanism.
- Related doc overstatement: README.md:11 "Every supported target (sbx, Docker, Apple container, macOS host) lands on the same environment" — false today for Apple container / plain hosts (see D-group and F-group below).

### C. Parity gaps between the three paths

- **C1 — `GIT_AUTHOR_*`/`JJ_CONFIG` never reach any `nu` session, on any path.** They exist only in the bash-sourced `/etc/sandbox-persistent.sh` block (`bootstrap.nu:284-296`); `sbx exec -it NAME nu --login` execs nu directly, no bash, so nu sessions fall back to the XDG identity `Agent <agent@sandbox>` (`bootstrap.nu:79-81`) and jj never loads the deployed `~/.config/jj/jj-config-claude-ai.toml` (non-default filename, needs `JJ_CONFIG`). On hosts the block doesn't exist at all, so even bash lacks them. Consequences: jj is misconfigured in every interactive nu shell; commit identity differs by path AND by shell type. Decide the intent (who should commit as Claude, where jj config should load from), then place the vars where the intended processes actually see them.
- **C2 — README.md:102 "Git attribution" is wrong about the mechanism.** It claims `/etc/sandbox-persistent.sh` is "sourced only by Claude Code's bash tool". `bootstrap.nu:294` says the base image sources it from `/etc/profile.d`, `/etc/bash.bashrc` and `~/.bashrc` — i.e. **every** bash shell exports Claude's identity, overriding even a user's own `git config`. The README's conclusion about nu shells is accidentally right (nu doesn't source bash files), for the wrong reason. Also `CLAUDE_ENV_FILE` appears nowhere in the repo except this README line — unverifiable.
- **C3 — Linux host / non-sbx container: clipboard is broken.** The `pbcopy` shim installs only in Step 0 (`bootstrap.nu:273-275`), but 8 deployed config files call `pbcopy` (helix `config.toml:173,180`, lazygit `config.yml:9,31,38`, broot `verbs.hjson:185-206`, nushell `config.nu:439`, zellij todo-nu, visidata `config.py:2`, …). Every copy keybinding errors "command not found". macOS hosts work via native pbcopy (local pasteboard instead of OSC-52 — behavioral difference only). Fix candidate: install the shim on any Linux without a `pbcopy` on PATH, independent of Step 0.
- **C4 — host env is thinner than sandbox env.** `host-install.sh:40-47` persists only `XDG_CONFIG_HOME`. Never set on hosts: `HELIX_RUNTIME` (probably fine — brew's hx self-locates; unverified), `LANG`, `XDG_DATA_HOME`/`XDG_CACHE_HOME` (self-healed inside nu by `vendor/dotfiles/nushell/env.nu:63-71`, so nothing breaks today — but only inside nu). `procps`/`file` are never installed on hosts despite README.md:47 listing them unqualified.
- **C5 — kit installs from unpinned GitHub HEAD; Dockerfile/host install from the local checkout.** `spec.yaml:71` clones the default branch with no `--branch`. A kit run can silently install different code (and a different `vendor/` snapshot) than what's on disk. Decide: HEAD-tracking is the feature (then say so in README) or pin to a tag for reproducibility.
- **C6 — cosmetic, deliberate**: `~/workspace/README.md` is Dockerfile-only (`Dockerfile:61`; acknowledged in `design/autoload.md`); MOTD banner/logo is docker+kit-only (lives inside the env block, `bootstrap.nu:295`).

### D. Re-run and recovery semantics

- **D1 — partial first-run failure on a host leaves a trap.** Destructive steps (autoload wipe `bootstrap.nu:108`, `push-to-machine --force` step 4) run long before the stamp is written last (`bootstrap.nu:164`). If the run dies at step 8, a plain re-run trips `check-no-clobber` on cozy's *own* deployed files with the misleading "back them up" message, and the user must `--force` — which also disables protection for any real user files not yet touched. `--force` conflates "skip the guard" with "recover a partial install" (`bootstrap.nu:29,54`). Fix: write an in-progress marker before the first destructive step; on re-run with in-progress-but-no-stamp, resume without tripping the guard (and keep `--force` for its original meaning only).
- **D2 — `/tmp/vendor` staleness on docker-image re-runs.** In the image path `/tmp/vendor` is baked in (`Dockerfile:48`). `cozy sync-repos` updates `~/repos/*` but never `/tmp/vendor`; a later bootstrap re-run prefers `/tmp/vendor` (`bootstrap.nu:340`) and clobbers the synced modules back to the build-time snapshot. Medium confidence — depends on whether the sandbox runtime gives the container a fresh tmpfs `/tmp` (verify live). Cheap fix regardless: have bootstrap consume-and-delete `/tmp/vendor`, or prefer `~/repos/cozy/vendor` when it exists.
- **D3 — in-sandbox config edits are lost on re-run.** `bootstrap.nu:120` passes `--force --commit-changes` but not `--commit-existing` — the toolkit flag that snapshots the destination before overwrite (`vendor/dotfiles/toolkit.nu:226-237`). A re-run (or `sbx kit add`) overwrites uncommitted user edits in `~/.config/*` with no snapshot. Fix: add `--commit-existing`.
- **D4 — verified, latent: the Step-6 CLAUDE.md append converges only by hidden coupling.** Step 4 deploys a fresh `~/.claude/CLAUDE.md` (it's in `vendor/dotfiles/paths-docker.csv:5`, plain `cp` overwrite in `toolkit.nu`), then Step 6 appends the catalog once (`bootstrap.nu:126-127`) — so today re-runs do NOT duplicate. But nothing states or guards this: drop that CSV row or reorder the steps and the append starts stacking, and `verify.nu`'s `check-catalog` (grep-count ≥ 1) would not notice. Fix: marker-wrap the catalog append and replace in place, exactly like the env block (`bootstrap.nu:297-313`).

### E. Guard and verification coverage gaps

- **E1 — `toolkit/check.nu` guards 5 env keys + a PATH prefix, nothing else.** Unguarded keys living in 2+ places: `HOME`, `HOMEBREW_NO_ASK`, `HOMEBREW_NO_AUTO_UPDATE`, `TERM`/`COLORTERM`/`TERM_PROGRAM` (`check.nu:19`). PATH is compared by prefix only — Dockerfile inherits the base tail via `${PATH}` while the kit hardcodes its tail (`spec.yaml:17`); tails can drift silently (`check.nu:84`). And nothing guards the *install-command sequence* itself, which exists in three copies (Dockerfile RUN, kit `commands.install`, host-install.sh) held together by convention (`design/build.md:21`).
- **E2 — `ensure-nu.sh` smoke test covers less than its docs imply.** `nu -c "use bootstrap.nu"` (`ensure-nu.sh:26`) parses bootstrap + its two `use`s only. Autoload scripts, dotfiles `config.nu`/`env.nu`, `cozy-module/*.nu`, and the lazy install modules (`rust.nu`, `zellij.nu`, …) are not covered: a nu syntax drift there installs "successfully" and breaks every interactive session afterward. Fix: extend the check (`nu --ide-check` over autoload + config) or scope the claim in `ensure-nu.sh:22-25` / `design/build.md:40`.
- **E3 — `cozy verify` never runs automatically, and refuses to run outside a sandbox.** Not wired into any path (grep: only `mod.nu:11`), and `verify.nu:225` errors without the marker, so host installs are never verifiable. Also `verify.nu:25-31` hand-lists 17 tools and `verify.nu:48-52` hand-lists 3 files, contradicting CLAUDE.md:84 "never hand-listed" (the dirs/envs checks do derive). Fix: add a final kit install command `nu -c '... verify | where not pass'` failing loudly; make verify's sandbox-only checks conditional so hosts can run the subset; scope the CLAUDE.md claim.
- **E4 — network allowlist gaps (`spec.yaml:36-54`, self-declared provisional).** Plausibly missing: `pkg-containers.githubusercontent.com` (ghcr bottle redirect), `release-assets.githubusercontent.com` (ensure-nu fallback tarball redirect), and whatever CDN `claude.ai/install.sh` fetches the binary from (not visible in-repo; if blocked, `claude install` half-fails and `bootstrap.nu:151` dies one step later with "claude not found"). Likely unused at install time: `codeload.github.com` (vendor tarballs are a pre-build host-side fetch). On-demand `cozy install rust/zellij/nushell/polars` need `sh.rustup.rs`, `static.rust-lang.org`, `crates.io` — absent, worth a spec comment. Verify all on a live `sbx run`.

### F. Documentation drift (beyond C2)

- README.md:11 — "same environment" for Apple container/macOS host: overstated (see B1, C-group).
- README.md:34 — "deploys the full environment ... into virtually any Ubuntu-based sandbox": full only with the sbx marker; plain Ubuntu loses Step 0 (pbcopy, env block, apt deps).
- README.md:36 — "exits early if [brew] isn't on PATH": actually auto-installs on Linux with passwordless sudo (`host-install.sh:16-24`); exits early only otherwise.
- README.md:47 — Technologies list: `procps file gcc libc6-dev` are Step-0-only; the "base image adds rg, jq, gh…" parenthetical means hosts get no `rg`/`jq`/`gh` from cozy at all — no host/sandbox distinction is made.
- CLAUDE.md:18 — "apt proxy" is stale; Step 0 does an http→https sources rewrite, no proxy (`bootstrap.nu:246-260`). Same stale phrase in `Dockerfile:57` ("/etc/apt proxy file").
- CLAUDE.md:27 — Step 9 also merges `externalEditorContext` and writes the stamp; not mentioned.
- design/build.md:74-76 + bootstrap.nu:137-140 — "No clone fallback (fail-fast)" is **wrong**: `topiary.nu:22-28` clones `topiary-nushell` from GitHub whenever `~/git/topiary-nushell` is absent. The fail-fast intent is not enforced by the code. Either delete the fallback in topiary.nu (align code to stated intent) or fix the three doc sites.
- design/build.md:31 — ENV list omits the two `HOMEBREW_*` vars; "Step 0 mirrors this block" is imprecise (subset + git/jj additions).
- design/ `reconciled-at: 03a87ce` is 5 install-path commits behind (`3645ca8`, `3c23179`, `8251c9f`, `4a7aa11`, `05fd413`) — run `/update-design`.
- host-install.sh's rc-block on Ubuntu: writing a new `~/.bash_profile` (`host-install.sh:36`) makes bash login shells skip `~/.profile` — the conventional home of `eval "$(brew shellenv)"` on Linux — potentially dropping brew off PATH for login shells. Also the block never adds `~/.local/bin` to PATH, so a pinned-nu fallback (`ensure-nu.sh:73`) stops shadowing brew's nu the moment the script exits. Fix: append to `~/.bashrc` (or to `~/.profile` if no `~/.bash_profile` existed), and include `~/.local/bin` in PATH.

## Refactoring opportunities (ranked)

1. **Collapse the triplicated boot tail into one shared script** (e.g. `cozy-module/install/run-install.sh`: HOMEBREW env → brew-nushell pre-install → `ensure-nu.sh` → `nu bootstrap.nu`), called by Dockerfile, kit and host-install.sh. Kills the ordering-drift risk (E1), gives one home for the HOMEBREW exports (A2) and the curl guard (A3), and keeps the Dockerfile in sync for the Apple-container plan almost for free — it shrinks to base + brew + clone/COPY + one RUN.
2. **Make install mode explicit instead of marker-sniffing** (B1): `--mode docker|host` or container detection, so any container base gets Step 0 and a missing marker becomes an error or a created file, not a silent host fallback. Prerequisite for Apple container.
3. **In-progress marker + `--force`/`--recover` split** (D1) — removes the worst data-loss/confusion path on hosts.
4. **Converge every step + auto-verify**: marker-wrap the CLAUDE.md append (D4), add `--commit-existing` (D3), wire `cozy verify` as the final kit install command and make it host-capable (E3). Turns silent partial installs into loud failures.
5. **Harden the network/prompt contract**: `GIT_TERMINAL_PROMPT=0` on the kit clone (A1), allowlist the redirect CDNs (E4), assert `which claude` before `claude mcp add` (`bootstrap.nu:150-151`).
6. **Extend `check.nu`**: add `HOME` + `HOMEBREW_*` keys, compare full PATH tails, and (optionally) assert the kit's 5 install commands textually against the shared script once refactoring 1 lands.

## Implementation plan

Quick wins (one-liners, no design decisions):
- [ ] `GIT_TERMINAL_PROMPT=0` on the kit clone (`sbx-kit/spec.yaml:71`)
- [ ] Export `HOMEBREW_NO_ASK`/`HOMEBREW_NO_AUTO_UPDATE` in `ensure-nu.sh`
- [ ] Curl-to-file for the Homebrew installer in Dockerfile + kit
- [ ] `--commit-existing` on the push-to-machine call (`bootstrap.nu:120`)
- [ ] Marker-wrap the Step-6 catalog append
- [ ] `which claude` assert before `claude mcp add`
- [ ] host-install.sh rc-block: target `~/.bashrc`/`~/.profile` correctly, add `~/.local/bin` to PATH

Decisions needed from user before implementing:
- [ ] B1 mode-detection mechanism (explicit flag vs `/.dockerenv` vs "create the marker file when containerized")
- [ ] C1 intent: where should `GIT_AUTHOR_*` (Claude identity) and `JJ_CONFIG` actually apply — bash only, all shells, Claude Code only?
- [ ] C5 kit pinning: HEAD-tracking as a feature, or pin to release tag?
- [ ] C3 pbcopy on Linux hosts: install shim whenever no pbcopy exists?
- [ ] Refactoring 1 (shared boot-tail script) — approve shape before touching three entry points
- [ ] topiary clone fallback: delete it (fail-fast intent) or document it?

Doc fixes (can batch into one commit):
- [ ] README lines 11, 34, 36, 47, 102; CLAUDE.md lines 18, 27; Dockerfile:57; design/build.md:31, 74-76; then `/update-design` to advance `reconciled-at`

Verify on a live `sbx run` (can't be determined from the repo):
- [ ] Whether kit `environment.variables` reach a direct `sbx exec ... nu` process (assumed yes)
- [ ] Whether `/tmp` is fresh tmpfs in a running sandbox (D2 severity)
- [ ] Actual blocked/needed domains during a full kit install, incl. the claude binary CDN (E4)

## Affected files

Existing: see `related_files` frontmatter. New files: possibly `cozy-module/install/run-install.sh` (refactoring 1). No code was changed by this audit.
