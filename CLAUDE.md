# cozy

Modern, beginner-friendly terminal environment for AI agents, running inside `sbx` (Docker's standalone sandbox runtime, formerly `docker sandbox`). Tested with Claude Code; other agents can be configured via `sbx`.

## Architecture

Every install path (docker build, sbx kit, plain host checkout) runs the same boot tail, `cozy-module/install/run-install.sh`: ensure brew → `ensure-nu.sh` (install nu, smoke-test it against bootstrap.nu, pin on parse drift) → `nu bootstrap.nu`. All install logic lives in `cozy-module/install/bootstrap.nu`; the Dockerfile just cache-primes brew + nushell, COPYs repo bits, and calls the shared script.

```
Dockerfile (thin)
├── Base: docker/sandbox-templates:shell (Ubuntu, git, curl, Python, Node.js, Go, rg, jq, gh)
├── RUN install Homebrew + brew install nushell (cached layers; run-install.sh re-checks, so they're optional for correctness)
├── COPY vendor/ → /tmp/vendor/; cozy-module/ + docker-files/ → ~/repos/cozy/
└── RUN run-install.sh — the shared boot tail: ensure brew (no-op here) → ensure-nu.sh → nu bootstrap.nu

bootstrap.nu (all install logic; every path reaches it via run-install.sh)
├── Step 0: setup-docker-system (gated on /etc/sandbox-persistent.sh or /.dockerenv) — apt sources → https, apt deps, runtime env exports (pbcopy shim installs separately, on every Linux)
├── Step 1: brew install rest of tools (fzf, helix, lazygit, zellij, broot, git-delta, visidata, bat, topiary, fd, jj, git-lfs)
├── Step 2: XDG git config (~/.config/git/{config,ignore})
├── Step 3: populate ~/repos/ from /tmp/vendor (docker) or cozy_root/vendor (host); modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, topiary-nushell, dotfiles, my-claude-skills, nushell-skills
├── Step 3.5: copy docker-files/nushell-autoload/*.nu → ~/.config/nushell/autoload/ (visidata config ships via dotfiles in Steps 4–5)
├── Steps 4–5: dotfiles deploy via `toolkit push-to-machine --docker`; install Claude skills via `toolkit install-skills --all`
├── Step 6: append docker-files/global-claude.md to ~/.claude/CLAUDE.md (tool catalog)
├── Step 7: broot init
├── Step 8: topiary install (binary + grammar via vendored topiary-nushell + config)
└── Step 9: Claude Code install + register nushell as stdio MCP via `claude mcp add`
```

## Run

The `sbx` kit is the only run path — no image build. It clones cozy in-sandbox and runs the same `bootstrap.nu`:

```sh
sbx run shell --kit sbx-kit/ ~/path/to/project
#       ^^agent              ^^workspace
```

`sbx` pulls images only from a registry, and cozy images stay local-only (never pushed), so a `docker build`ed image can't be fed to `sbx` — the kit (in-sandbox build) replaces that path entirely.

The agent name (`claude`, `shell`, etc.) selects which agent process runs inside the sandbox — it is independent of the base image (`docker/sandbox-templates:shell`) used in the Dockerfile.

Requires Docker Desktop 4.58+ on macOS or Windows.

## Sandbox Management

```sh
sbx ls
sbx exec -it <name> nu        # shell into sandbox with nushell
sbx exec -it -w /home/agent <name> nu  # start from home dir
sbx stop <name>
sbx rm <name>
```

## Local Docs

`toolkit docs` downloads Docker sandbox documentation as markdown into `docs.docker.com/` — a self-contained git repo inside `cozy/`, ignored by `.gitignore`. Re-run to sync updates; idempotent. When you need Docker sandbox docs, read from `docs.docker.com/` instead of fetching from the web.

## Rebuilding

The kit re-clones cozy and re-runs `bootstrap.nu` on every `sbx run`, so picking up changes just means running it again — but the kit clones from GitHub, so push first. The Dockerfile image is built separately (`docker build`) and isn't used by `sbx`; rebuild it only for the plain-`docker` artifact.

## Rules

- Do NOT suggest pushing images or tags to Docker Hub or any registry. All images are local-only.
- Keep command output visible — don't use quiet/silent flags (`-qq`, `-s`, `--quiet`) in scripts. Users should see what's happening during installation and setup.

## Changelog

`CHANGELOG.md` targets potential new users (there are no existing users yet). Each entry should answer: "would this matter to someone deciding whether to adopt cozy, or how to use it?"

- KEEP: user-facing CLI/flag changes, behavior changes a user would notice, bug fixes adopters could still hit, vendored module bumps with the new capability named.
- DROP: "Affects: X, Y, Z" file lists, internal refactor rationale, build-time bug fixes that no longer apply, vague "refreshed from upstream" lines.
- One line per entry, two at most. Include commit hash(es) for traceability.
- When editing existing sections, verify diff scope matches commit message — `7130961` silently deleted `[0.2.3]` while claiming only to extend a file list.

## Sources of truth

- Build order + rationale (why each tool compiles from source / module is vendored / file ships): `design/` — one map (`design/README.md`) + per-subsystem files; run `/update-design` to reconcile against code
- Last-validated baseline for the doc/design checks: each check records where it last passed, so re-runs only inspect the diff since. `make-a-release` off the previous version tag; `update-design` off each design file's `reconciled-at:` frontmatter (scoped to that file's `covers:` paths); `validate-docs` off the local ref `refs/cozy/docs-validated` (a ref, not a tag, so `git push --tags` leaves it alone). A marker means "a clean full pass happened at this commit" — only a full pass advances it (`--full`, or a full scan, rebuilds a baseline you no longer trust). Never advance a marker on a partial, user-named-subset check
- Keybindings: `vendor/dotfiles/zellij/config.kdl` (README keybinding docs drift from this)
- Vendored modules: `toolkit/vendor.yml` via `toolkit/vendor.nu` (not the CLAUDE.md architecture list). `toolkit/vendor.nu` also projects it into `cozy-module/vendored-repos.nuon` — the manifest that ships into the sandbox, read by `cozy sync-repos` and `cozy-module/verify.nu`. `toolkit check` guards the manifest against `vendor.yml`; never hardcode the list
- `cozy` command surface: `cozy-module/mod.nu` exports
- Post-build verification: `cozy-module/verify.nu` — one check set, run by `cozy verify` inside a sandbox. Checks take a transport closure so the check logic is independent of how commands are carried; expected values derive from `vendored-repos.nuon`, the `docker-files/nushell-autoload/` glob and `bootstrap.nu`'s env exports — never hand-listed
- Install step order (host + docker + kit): the shared boot tail `cozy-module/install/run-install.sh` (ensure brew → `ensure-nu.sh` → `bootstrap.nu`), then `cozy-module/install/bootstrap.nu`'s steps 0–9 — one sequence for all build paths
- Pinned nushell fallback: `cozy-module/install/.nushell-version` — consumed by `ensure-nu.sh` when latest `nu` can't parse `bootstrap.nu`
- Kit spec for `sbx run shell --kit ./sbx-kit/`: `sbx-kit/spec.yaml` — environment mirrors the Dockerfile ENV; commands.install is clone + the shared `run-install.sh` (the clone can't live in the script — it doesn't exist in-sandbox until the clone lands). The shared env values (Dockerfile ENV / kit / `bootstrap.nu` exports) can't share one literal across the three formats — `toolkit check` guards them against drift; the *command sequence* CAN and does share one literal: `run-install.sh`
- CHANGELOG entries are historical — cross-reference sequential versions for contradictions

## Notes

- Workspace is mounted at its original host path (e.g. `/Users/user/temp/docker/`), not at `/workspace` or `/home/agent`
- Only the workspace folder from `sbx run` is synced — `exec` from a different folder doesn't mount it
- Sandbox creation rewrites git config on every start. `sbx` sets `core.excludesFile = ~/.gitignore_global` in `~/.gitconfig`, and edits two keys in cozy's XDG `~/.config/git/config` (narrows `safe.directory` to the workspace root, adds `core.checkStat = minimal`) — key edits, not a file overwrite, so cozy's `user.name`/`gc.auto`/`core.fsync` there survive. So durable config still goes in XDG (`~/.config/git/config`), not `/etc/gitconfig` (brew git ignores its sysconfdir). But `~/.gitconfig` overrides XDG for single-valued keys, so what `sbx` sets there can't be reclaimed via XDG — it's re-healed on shell start: `git-safe-directory.nu` re-asserts `safe.directory = *`; `git-global-ignore.nu` mirrors `~/.config/git/ignore` into the active `core.excludesFile` (which `sbx` sets, shadowing git's XDG-default ignore). Verified on a live sbx sandbox 2026-07.
- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- Homebrew fetches latest versions at build time — use `brew pin` or specify versions if reproducibility matters
