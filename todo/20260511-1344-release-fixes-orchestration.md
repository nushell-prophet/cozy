---
task-name: release-fixes-orchestration
status: completed
created: 2026-05-11
updated: 2026-05-11
completed: 2026-05-11
related_files:
  - sandbox-toolkit/install/bootstrap.nu
  - toolkit/vendor.nu
  - toolkit/test.nu
  - Dockerfile
  - README.md
  - CHANGELOG.md
  - CLAUDE.md
  - docker-files/global-claude.md
  - ../CLAUDE.md
  - sandbox-toolkit/README.md
---

# Release-fixes orchestration: sequential agents, atomic commits

## Task from user (original)

create a todo for that, to spawn agents sequentially fix everything and commit atomically along the way

## Context

After the 9-agent release audit and 1-agent verification pass (this session), 12 verified findings remain on branch `feat/dockerfile-thin`. One finding (H1 — CLAUDE.md double-append) was disproved on verification and is dropped. H8 was downgraded.

Each fix should land as a focused commit so a future bisect can isolate behavior changes. Agents run **sequentially** (not parallel) because most fixes touch `bootstrap.nu`, `CHANGELOG.md`, or `README.md` — parallel work would race.

## Ground rules for every agent

- One logical change per commit. Subject ≤ 70 chars, body explains *why* (paraphrase the audit reasoning verbatim per CLAUDE.md intent-preservation rule).
- Cite the audit finding ID (B1, H2, etc.) in commit body so the trail back to this todo is explicit.
- Fail-fast: don't pair a fix with a "just in case" guard. If a stale artifact caused the bug, delete it.
- No new docs, comments, or scope creep beyond the finding being addressed.
- Verify the fix locally where possible (parse-test the file, re-run a relevant smoke command) before committing.
- If a fix turns out to be wrong or overlaps with another, **stop and report back** — do not invent scope.

## Execution order (top-down, sequential)

Code fixes first (changes shape of files docs describe), then docs (describe final state accurately), then test/polish last.

### Phase 1 — Code BLOCKERs

- [x] **F1 (B1) — Restore vendored topiary-nushell visibility.** Currently `topiary.nu:20` reads `~/git/topiary-nushell`; vendored copy lands at `~/repos/topiary-nushell/` and is invisible. Old Dockerfile had `if [ -d ~/repos/topiary-nushell ]; then mkdir -p ~/git && ln -s ~/repos/topiary-nushell ~/git/topiary-nushell; fi`. Add equivalent to `bootstrap.nu` just before step 8 (topiary install). Don't ship a defensive clone fallback — symlink alone, then `topiary install` proceeds. Verify by running `topiary install` against the synthetic symlink. Commit: `fix(bootstrap): symlink vendored topiary-nushell so topiary install uses it (B1)`.

- [x] **F2 (B2) — Resolve MCP `nu` path at runtime, not hardcoded linuxbrew.** `bootstrap.nu:104` literal `/home/linuxbrew/.linuxbrew/bin/nu` breaks macOS host install silently. Replace with `which nu | get path.0` (it's been on PATH since step 1 brew-installed it). One-line change. Verify: `nu -c 'which nu | get path.0'` returns a valid path on the audit host. Commit: `fix(bootstrap): resolve nu path at runtime for claude mcp add (B2)`.

### Phase 2 — Code HIGHs

- [x] **F3 (H3) — Stop wiping nushell history on re-run.** `bootstrap.nu:119-120` does `rm -rf ~/.config/nushell` to avoid `config.nu`/`env.nu`/autoload collisions on re-run. History sqlite files live in the same dir and get destroyed. Per fail-fast: delete only the colliding artifacts (`config.nu`, `env.nu`, `autoload/`), preserve `history.sqlite3*`. Verify: simulate by creating a fake history file, run the wipe step manually, check survival. Commit: `fix(bootstrap): preserve nushell history on re-run wipe (H3)`.

- [x] **F4 (H2) — Delete stale vendored module files on re-run.** `bootstrap.nu:213-215` `cp -r` overlays without `rm -rf` first. Mirror the cozy_dst loop pattern (lines 195-199): for each entry, rm the dst path if present, then cp. Verify with the same `src/{a} → dst/{a,stale} → cp -r → ls dst` test. Commit: `fix(bootstrap): rm -rf vendor dst before cp -r to drop stale files (H2)`.

- [x] **F5 (H4) — vendor.nu must not write to caller's pwd.** `vendor.nu:93,101` use `pwd | path join …`. Fix by having `vendor.nu` derive its own root from `path self | path dirname | path dirname` (the cozy root, which it lives under at `toolkit/vendor.nu`). Drop the `pwd`-based logic entirely. `bootstrap.nu`'s spawn at line 209 stays as-is. Verify: `cd /tmp && nu /Users/.../cozy/toolkit/vendor.nu --local` writes to `/Users/.../cozy/vendor/`, not `/tmp/vendor/`. Commit: `fix(vendor): derive vendor_dir from path self, not pwd (H4)`.

- [x] **F6 (H5) — Fix misleading "matches Dockerfile" brew-split comment.** `bootstrap.nu:37` claim is false; Dockerfile has one `brew install nushell`. Options: (a) drop the second brew group + extra cleanup if no layering benefit exists, (b) rewrite the comment to state the actual reason (or that there isn't one and the split is vestigial). Pick (a) if cleanup-between is truly noop; (b) otherwise. Commit: `refactor(bootstrap): drop spurious brew split / fix misleading comment (H5)`.

### Phase 3 — Documentation

- [x] **F7 (B3) — Rewrite CHANGELOG `[Unreleased]`.** Three fixes in one commit:
    1. Line 12: drop `--in-docker for the Dockerfile path,` — final flag surface is just `--local`.
    2. Line 18-19: change `'... bootstrap --in-docker'` → `nu …/bootstrap.nu`; replace `(gated on --in-docker)` with `(auto-gated on /etc/sandbox-persistent.sh)`.
    3. Delete line 20 (the "drop --in-docker" entry) since lines 12/18/19 now describe the final state directly.
    4. Add missing entries under Added/Fixed for: `f624b24` vendor fail-fast + GH_TOKEN, `d60fb7e` `--local` semantics shift, `ad6285a`+`1055fdd` in-sandbox bootstrap fixes, `05930ab` nushell config wipe (post-F3 wording: history preserved), `23ae7fe` unconditional git identity, `6ab6541` always-pass `--docker` to push-to-machine.
    Suggested text is in the release-readiness agent report (Section 2).
    Commit: `changelog: rewrite Unreleased for final state, add 6 missing entries (B3)`.

- [x] **F8 (B4) — Add host-install section to README.md.** New section between Quick Start and Technologies. Three lines: clone, `./bootstrap.sh`, note `--local` for sibling-repo refresh. Commit: `docs(readme): document bootstrap.sh host install path (B4)`.

- [x] **F9 (B5) — Strip `INSTALL_CLAUDE` and `MODULES_SOURCE=clone` from docs.** Four locations: `README.md:20`, `README.md:85-87` (whole subsection), `cozy/CLAUDE.md:14`, `/Users/user/git/ai-sandbox-dev-container/CLAUDE.md:41`. Delete advertising, don't replace with anything (the agent-free path can come back as a code feature later if wanted). Commit: `docs: drop stale --build-arg INSTALL_CLAUDE / MODULES_SOURCE refs (B5)`.

- [x] **F10 (H6) — Rewrite `cozy/CLAUDE.md:7-21` architecture diagram.** Reflect thin Dockerfile + bootstrap.nu absorption. Use the sketch from the docs agent's Section 4 rec 3. Commit: `docs(claude.md): redraw architecture for thin Dockerfile + bootstrap.nu (H6)`.

- [x] **F11 (H7) — Add `fd` to `docker-files/global-claude.md`.** One-word fix under File Navigation & Search, after `bat`. Pre-existing oversight, not introduced by this branch — flag in commit body. Commit: `docs(global-claude): add fd to tool catalog (H7)`.

- [x] **F12 (M5+M6) — Cross-link bootstrap.nu in Sources of truth.** `cozy/CLAUDE.md:58-63` add bootstrap.nu and `.nushell-version`; `sandbox-toolkit/README.md:75` add `bootstrap` to install subcommands list. One commit, two files. Commit: `docs: list bootstrap.nu + .nushell-version as sources of truth (M5,M6)`.

### Phase 4 — Tests and polish

- [x] **F13 (M3) — Fix `toolkit/test.nu` autoload filename drift.** Lines 36-41 reference `cmd-stack-import.nu`, `my_nu_completions.nu`, `standard_4002_aliasses.nu` — none exist. Real filenames: `module-imports.nu`, `my-nu-completions.nu`, `standard-aliasses.nu`. Drop `cmd-stack-import.nu` (cmd-stack loads via `module-imports.nu` overlay). Verify by running `nu toolkit/test.nu test` against a fresh image and confirming the autoload checks pass. Commit: `fix(test): correct autoload filenames in existence checks (M3)`.

- [x] **F14 (M1) — Dedup `/etc/sandbox-persistent.sh` env block on re-run.** Wrap the cozy block between `# >>> cozy env >>>` / `# <<< cozy env <<<` markers; on each run, read the file, replace any existing block by marker, append if missing. Commit: `fix(bootstrap): idempotent env block in /etc/sandbox-persistent.sh (M1)`.

- [x] **F15 (M2) — Wipe `~/.config/nushell/autoload/` on host re-run too.** Currently only Docker re-runs are cleaned (via F3's per-file wipe). On host, stale autoload `.nu` files from removed-upstream entries persist. Apply the same per-file allowlist logic on host before the step 5 cp loop. Commit: `fix(bootstrap): clean autoload dir before copy on host re-run (M2)`.

- [x] **F16 (M4) — Gate `mkdir ~/workspace` on docker marker.** `bootstrap.nu:185` creates an unused `~/workspace/` on macOS host. Move into `setup-docker-system` or drop entirely (Dockerfile's `COPY README.md /home/agent/workspace/README.md` auto-creates the dir). Verify Dockerfile path still works. Commit: `fix(bootstrap): scope ~/workspace creation to docker mode (M4)`.

- [x] **F17 (H8) — OS-guard topiary apt fallback.** `topiary.nu:68-71` runs `sudo apt-get` unconditionally if gcc missing. Add `if $nu.os-info.name == 'macos'` branch that prints "install Xcode CLT (xcode-select --install)" and exits. Commit: `fix(topiary): guide macOS users to Xcode CLT instead of apt-get (H8)`.

### Phase 5 — Final verification (no commit)

- [~] After F1-F17, run a docker build of `cozy:v1` end-to-end and the user-checkable items from `todo/20260511-1310-verify-full-functionality.md`. Report results back to the user; do not cut the release tag without their go-ahead.
    - **Deferred** at user request — F1-F17 commits ship the deliverable; user will run the build themselves when convenient.

## Affected files

- `sandbox-toolkit/install/bootstrap.nu` (F1, F2, F3, F4, F6, F14, F15, F16)
- `sandbox-toolkit/install/topiary.nu` (F17)
- `toolkit/vendor.nu` (F5)
- `toolkit/test.nu` (F13)
- `CHANGELOG.md` (F7)
- `README.md` (F8, F9)
- `CLAUDE.md` (F9, F10, F12)
- `/Users/user/git/ai-sandbox-dev-container/CLAUDE.md` (F9)
- `docker-files/global-claude.md` (F11)
- `sandbox-toolkit/README.md` (F12)

New files: none.

## Risks and dependencies

- F1 (topiary symlink) must land before any Phase 5 docker build — without it, builds clone from github.com which may be rate-limited.
- F7 (CHANGELOG rewrite) should land after F3-F6 so the CHANGELOG can describe final code state, not transient states.
- F8-F12 (docs) depend on F1-F6 (code) so the docs describe the final code.
- F2 + F5 + F17 are the macOS-host fixes; if user only ships Docker path in this release, these can defer to a follow-up — but they're cheap, low-risk, in scope of this branch's intent.
- Agents must not amend or force-push; any rework lands as new commits.
- Working tree should be clean at the start of each agent — orchestrator confirms `git status` between phases.

## Execution result

**Date:** 2026-05-11

**Modified files:** none directly by orchestrator. Each fix landed in its own commit; affected files are listed in the per-fix sections above.

**Commits landed (oldest first, in execution order):**

| Fix | Hash | Subject |
|-----|------|---------|
| F1 (B1) | 53970d8 | fix(bootstrap): symlink vendored topiary-nushell so topiary install uses it |
| F2 (B2) | da7f93b | fix(bootstrap): resolve nu path at runtime for claude mcp add |
| F3 (H3) | 31c23f5 | fix(bootstrap): preserve nushell history on re-run wipe |
| F4 (H2) | 362ce1f | fix(bootstrap): rm -rf vendor dst before cp -r to drop stale files |
| F5 (H4) | f4d3590 | fix(vendor): derive vendor_dir from path self, not pwd |
| F6 (H5) | 5c9a481 | refactor(bootstrap): drop spurious brew split / fix misleading comment |
| F7 (B3) | a4ff1ad | changelog: rewrite Unreleased for final state, add 6 missing entries |
| F8 (B4) | 265ebe5 | docs(readme): document bootstrap.sh host install path |
| F9 (B5) | 8d0e454 + e91c5ab | docs: drop stale --build-arg INSTALL_CLAUDE / MODULES_SOURCE refs (parent CLAUDE.md committed separately on workspace repo) |
| F10 (H6) | 3f5b690 | docs(claude.md): redraw architecture for thin Dockerfile + bootstrap.nu |
| F11 (H7) | 3ee2519 | docs(global-claude): add fd to tool catalog |
| F12 (M5,M6) | eba94ec | docs: list bootstrap.nu + .nushell-version as sources of truth |
| F13 (M3) | f9e8ce1 | fix(test): correct autoload filenames in existence checks |
| F14 (M1) | 45cc3d9 | fix(bootstrap): idempotent env block in /etc/sandbox-persistent.sh |
| F15 (M2) | 121ee4a | fix(bootstrap): clean autoload dir before copy on host re-run |
| F16 (M4) | 7ecd43a | fix(bootstrap): scope ~/workspace creation to docker mode |
| F17 (H8) | 47946af | fix(topiary): guide macOS users to Xcode CLT instead of apt-get |

**Notable agent deviations (within scope, flagged here for visibility):**

- **F8 link cleanup:** the README's Technologies section had an anchor link to the deleted `### Building without Claude Code` section. Agent removed the broken anchor while keeping `Claude Code` as plain text — minor cleanup beyond strict scope.
- **F14 capture-group escape:** Nushell's `str replace --regex` interprets `$name` in replacements as a regex backref, which would have consumed literal `$HOME` in the env exports. Agent escaped `$` → `$$` and added a `# Why:` comment at the decision point.
- **F15 refactor:** F3's autoload wipe lived inside `setup-docker-system` (docker-only). Rather than duplicate the wipe on the host path, agent moved the wipe into `main` so it runs unconditionally before the autoload copy — single source of truth for the wipe.
- **F16 chose option (b) drop:** Dockerfile's `COPY README.md /home/agent/workspace/README.md` auto-creates the dir, and bootstrap.nu doesn't write to `~/workspace` after the mkdir. Drop was safe.
- **F17 used `match` over `if/else if/else`:** matches the nushell-style preference; raised `error make` on macOS and unknown-OS branches to mirror `bootstrap.nu`'s "brew not found" idiom.

**Phase 5 (verification):** deferred at user request. F1-F17 commits are the deliverable for this orchestration. User will run `docker build -t cozy:v1 .` and the verification items from `todo/20260511-1310-verify-full-functionality.md` themselves before tagging.

**Summary:** all 17 verified findings from the release audit are fixed and committed atomically on `feat/dockerfile-thin`, plus one follow-up commit on the parent workspace repo (e91c5ab) for the workspace-level CLAUDE.md update. Working tree clean. No amends, no force-pushes. Each commit body cites the audit finding ID and explains the reasoning behind the fix.
