---
task-name: install paths audit — sbx kit / Dockerfile / host-install.sh
status: in_progress
created: '20260702-215200 #yyyyMMdd-hhmmss'
updated: '20260726-003638 #yyyyMMdd-hhmmss'
original_session: 08d41519-11d5-4a07-ba92-022e10afb0a8
related_files:
  - Dockerfile
  - sbx-kit/spec.yaml
  - cozy-module/install/run-install.sh
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

## Re-verified 2026-07-26 against HEAD

Fixed since the audit: the topiary clone fallback is gone (`fac4c64`), so the fail-fast wording in `bootstrap.nu` and `design/build.md:96` is now true and the open decision below is closed. The "apt proxy" phrase is gone from `CLAUDE.md`, the `Dockerfile` and the README. `design/build.md:41` now names both `HOMEBREW_*` vars. `run-install.sh:39` now puts `~/.local/bin` on PATH — but only inside the script; the rc-block it writes still targets `~/.bash_profile` and still carries no PATH line, so that finding is only half-addressed.

Everything else re-checked and still true: `bootstrap.nu:176` still appends the catalog unwrapped (D4), there is still no `which claude` assert, `check.nu:20` still guards 5 env keys plus a PATH prefix (E1), `verify.nu:360` still refuses to run outside a sandbox and `const tools` is still hand-listed (E3), and `design/` is still 7 install-path commits behind its `reconciled-at` baseline.

E4 stopped being a guess: `firewall/allowed-domains.txt` — written against what the tools actually fetch — carries `release-assets.githubusercontent.com`, `pkg-containers.githubusercontent.com`, `downloads.claude.ai` and `github-cloud.githubusercontent.com`, none of which are in `sbx-kit/spec.yaml`. The two lists disagree in both directions and nothing guards them; see `20260724-023000-sbx-allowlist-same-hole.md`, which supersedes E4.

## Task from user (original)

> I @README.md it's stated that we have 3 ways of installing `cozy`: 1. `sbx` 2. Dockerfile (which has comments that it is not maintained, but I want to keep it in sync in case I decide to use `apple container`) 3. Just fresh ubuntu or macos machines.
>
> don't spare tokens, investigate the current setup steps, find potential problems and inconsistencies between methods (both sbx and Dockerfile should result in the same functionality), find refactoring opportunities to make the setup process more robust, maintainable and reliable.
>
> Document your findings in a new todo inside of todo/

## Task description (extended version)

Audit of the three install paths along four projections: env-var propagation, installed-artifact parity, failure modes / re-run behavior, and docs-vs-code claims. Four subagents swept the paths independently; contested findings were re-verified against the code by hand. Every finding below carries `file:line` evidence. Severity tags: **hang** (install blocks forever), **break** (functionality lost), **parity** (paths diverge), **drift** (no guard, will diverge later), **doc** (text wrong).

Baseline fact that drives most findings: all three paths converge on `bootstrap.nu`, but its Step 0 (`setup-docker-system` — apt deps, pbcopy shim, `/etc/sandbox-persistent.sh` env block) is gated on the marker file `/etc/sandbox-persistent.sh` that only the sbx base image ships (`bootstrap.nu:52`). sbx kit and Dockerfile both have the marker, so **those two paths are in good parity today**. Hosts (fresh Ubuntu, macOS) take the "host" branch and skip Step 0; containers without the marker are now caught via `/.dockerenv` detection (applied from B1).

## Findings

### D. Re-run and recovery semantics

- **D1 — partial first-run failure on a host leaves a trap.** Destructive steps (autoload wipe `bootstrap.nu:108`, `push-to-machine --force` step 4) run long before the stamp is written last (`bootstrap.nu:164`). If the run dies at step 8, a plain re-run trips `check-no-clobber` on cozy's *own* deployed files with the misleading "back them up" message, and the user must `--force` — which also disables protection for any real user files not yet touched. `--force` conflates "skip the guard" with "recover a partial install" (`bootstrap.nu:29,54`). Fix: write an in-progress marker before the first destructive step; on re-run with in-progress-but-no-stamp, resume without tripping the guard (and keep `--force` for its original meaning only).
- **D2 — `/tmp/vendor` staleness on docker-image re-runs.** In the image path `/tmp/vendor` is baked in (`Dockerfile:48`). `cozy sync-repos` updates `~/repos/*` but never `/tmp/vendor`; a later bootstrap re-run prefers `/tmp/vendor` (`bootstrap.nu:340`) and clobbers the synced modules back to the build-time snapshot. Medium confidence — depends on whether the sandbox runtime gives the container a fresh tmpfs `/tmp` (verify live). Cheap fix regardless: have bootstrap consume-and-delete `/tmp/vendor`, or prefer `~/repos/cozy/vendor` when it exists.
- **D4 — verified, latent: the Step-6 CLAUDE.md append converges only by hidden coupling.** Step 4 deploys a fresh `~/.claude/CLAUDE.md` (it's in `vendor/dotfiles/paths-docker.csv:5`, plain `cp` overwrite in `toolkit.nu`), then Step 6 appends the catalog once (`bootstrap.nu:126-127`) — so today re-runs do NOT duplicate. But nothing states or guards this: drop that CSV row or reorder the steps and the append starts stacking, and `verify.nu`'s `check-catalog` (grep-count ≥ 1) would not notice. Fix: marker-wrap the catalog append and replace in place, exactly like the env block (`bootstrap.nu:297-313`).

### E. Guard and verification coverage gaps

- **E1 — `toolkit/check.nu` guards 5 env keys + a PATH prefix, nothing else.** Unguarded keys living in 2+ places: `HOME`, `HOMEBREW_NO_ASK`, `HOMEBREW_NO_AUTO_UPDATE`, `TERM`/`COLORTERM`/`TERM_PROGRAM` (`check.nu:19`). PATH is compared by prefix only — Dockerfile inherits the base tail via `${PATH}` while the kit hardcodes its tail (`spec.yaml:17`); tails can drift silently (`check.nu:84`). The *install-command sequence* is no longer a drift risk — it collapsed into the shared `cozy-module/install/run-install.sh` (45cb593); the env keys and PATH tail above remain the open gap.
- **E2 — `ensure-nu.sh` smoke test covers less than its docs imply.** `nu -c "use bootstrap.nu"` (`ensure-nu.sh:26`) parses bootstrap + its two `use`s only. Autoload scripts, dotfiles `config.nu`/`env.nu`, `cozy-module/*.nu`, and the lazy install modules (`rust.nu`, `zellij.nu`, …) are not covered: a nu syntax drift there installs "successfully" and breaks every interactive session afterward. Fix: extend the check (`nu --ide-check` over autoload + config) or scope the claim in `ensure-nu.sh:22-25` / `design/build.md:40`.
- **E3 — `cozy verify` never runs automatically, and refuses to run outside a sandbox.** Not wired into any path (grep: only `mod.nu:11`), and `verify.nu:225` errors without the marker, so host installs are never verifiable. Also `verify.nu:25-31` hand-lists 17 tools and `verify.nu:48-52` hand-lists 3 files, contradicting CLAUDE.md:84 "never hand-listed" (the dirs/envs checks do derive). Fix: add a final kit install command `nu -c '... verify | where not pass'` failing loudly; make verify's sandbox-only checks conditional so hosts can run the subset; scope the CLAUDE.md claim.
- **E4 — network allowlist gaps (`spec.yaml:36-54`, self-declared provisional).** Plausibly missing: `pkg-containers.githubusercontent.com` (ghcr bottle redirect), `release-assets.githubusercontent.com` (ensure-nu fallback tarball redirect), and whatever CDN `claude.ai/install.sh` fetches the binary from (not visible in-repo; if blocked, `claude install` half-fails and `bootstrap.nu:151` dies one step later with "claude not found"). Likely unused at install time: `codeload.github.com` (vendor tarballs are a pre-build host-side fetch). On-demand `cozy install rust/zellij/nushell/polars` need `sh.rustup.rs`, `static.rust-lang.org`, `crates.io` — absent, worth a spec comment. Verify all on a live `sbx run`.

### F. Documentation drift (beyond C2)

- README.md:34 — "deploys the full environment ... into virtually any Ubuntu-based sandbox": full only with the sbx marker; plain Ubuntu loses Step 0 (env block, apt deps).
- README.md:47 — Technologies list: `procps file gcc libc6-dev` are Step-0-only; the "base image adds rg, jq, gh…" parenthetical means hosts get no `rg`/`jq`/`gh` from cozy at all — no host/sandbox distinction is made.
- ~~CLAUDE.md:18 / Dockerfile:57 — stale "apt proxy" phrase~~ — fixed; no site mentions a proxy now.
- CLAUDE.md:27 — Step 9 also merges `externalEditorContext` and writes the stamp; not mentioned.
- ~~design/build.md:74-76 + bootstrap.nu — "No clone fallback (fail-fast)" contradicted by `topiary.nu`~~ — fixed by deleting the fallback (`fac4c64`), the option this note recommended.
- ~~design/build.md:31 — ENV list omits the two `HOMEBREW_*` vars~~ — fixed. "Step 0 mirrors this block" is still imprecise (subset + git/jj additions).
- design/ `reconciled-at: 03a87ce` is 5 install-path commits behind (`3645ca8`, `3c23179`, `8251c9f`, `4a7aa11`, `05fd413`) — run `/update-design`.
- run-install.sh's rc-block on Ubuntu (was host-install.sh's): writing a new `~/.bash_profile` (`run-install.sh:53`) makes bash login shells skip `~/.profile` — the conventional home of `eval "$(brew shellenv)"` on Linux — potentially dropping brew off PATH for login shells. Also the block never adds `~/.local/bin` to PATH, so a pinned-nu fallback (`ensure-nu.sh:80`) stops shadowing brew's nu the moment the script exits. Fix: append to `~/.bashrc` (or to `~/.profile` if no `~/.bash_profile` existed), and include `~/.local/bin` in PATH.

## Refactoring opportunities (ranked)

3. **In-progress marker + `--force`/`--recover` split** (D1) — removes the worst data-loss/confusion path on hosts.
4. **Converge every step + auto-verify**: marker-wrap the CLAUDE.md append (D4), wire `cozy verify` as the final kit install command and make it host-capable (E3). Turns silent partial installs into loud failures.
5. **Harden the network/prompt contract**: allowlist the redirect CDNs (E4), assert `which claude` before `claude mcp add` (`bootstrap.nu:150-151`).
6. **Extend `check.nu`**: add `HOME` + `HOMEBREW_*` keys, compare full PATH tails, and (optionally) assert that the kit's install commands and the Dockerfile RUN tail invoke `run-install.sh` (refactoring 1 landed in 45cb593).

## Implementation plan

Quick wins (one-liners, no design decisions):
- [ ] Marker-wrap the Step-6 catalog append
- [ ] `which claude` assert before `claude mcp add`
- [ ] run-install.sh rc-block: target `~/.bashrc`/`~/.profile` correctly (still writes `~/.bash_profile`), and add `~/.local/bin` to the exported PATH (the script's own `export` at `:39` does not survive it)

Decisions needed from user before implementing:
- [x] topiary clone fallback — deleted (`fac4c64`)

Doc fixes (can batch into one commit):
- [ ] README lines 34, 47; CLAUDE.md line 27; design/build.md's "Step 0 mirrors this block"; then `/update-design` to advance `reconciled-at` (7 install-path commits behind)

Verify on a live `sbx run` (can't be determined from the repo):
- [ ] Whether kit `environment.variables` reach a direct `sbx exec ... nu` process (assumed yes)
- [ ] Whether `/tmp` is fresh tmpfs in a running sandbox (D2 severity)
- [ ] Actual blocked/needed domains during a full kit install, incl. the claude binary CDN (E4)
- [ ] Apple-container base: does it create `/.dockerenv` (the step-0 container detection hinges on it), and does `setup-docker-system`'s sudo/apt path work there (e.g. root without sudo)?

## Affected files

Existing: see `related_files` frontmatter. New files: `cozy-module/install/run-install.sh` (refactoring 1, landed in 45cb593 — replaces `host-install.sh`). No code was changed by this audit.
