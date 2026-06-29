# cozy

Modern, beginner-friendly terminal environment for AI agents, running inside `docker sandbox`. Tested with Claude Code; other agents can be configured via `docker sandbox`.

## Architecture

The Dockerfile is thin: install Homebrew, pre-install nushell as a cached layer, COPY repo bits, then hand off to `bootstrap.nu`. All install logic lives in `cozy-module/install/bootstrap.nu`, which serves both the docker-build path and the host-install path (via `host-install.sh`).

```
Dockerfile (thin)
├── Base: docker/sandbox-templates:shell (Ubuntu, git, curl, Python, Node.js, Go, rg, jq, gh)
├── RUN install Homebrew + brew install nushell (cached layer)
├── COPY vendor/ → /tmp/vendor/; cozy-module/ + docker-files/ → ~/repos/cozy/
├── RUN ensure-nu.sh — smoke-test latest nu against bootstrap.nu, fall back to pinned version if pre-1.0 syntax drifted
└── RUN nu bootstrap.nu — all install logic below

bootstrap.nu (also entry point for host install via host-install.sh)
├── Step 0: setup-docker-system (gated on /etc/sandbox-persistent.sh) — apt deps, pbcopy shim, apt proxy, runtime env exports
├── Step 1: brew install rest of tools (fzf, helix, lazygit, zellij, broot, git-delta, visidata, bat, topiary, fd, jj, git-lfs)
├── Step 2: XDG git config (~/.config/git/{config,ignore})
├── Step 3: populate ~/repos/ from /tmp/vendor (docker) or cozy_root/vendor (host); modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, topiary-nushell, dotfiles, my-claude-skills, nushell-skills, nu-multiproof
├── Step 3.5: copy docker-files/nushell-autoload/*.nu → ~/.config/nushell/autoload/ (visidata config ships via dotfiles in Steps 4–5)
├── Steps 4–5: dotfiles deploy via `toolkit push-to-machine --docker`; install Claude skills via `toolkit install-skills --all`
├── Step 6: append docker-files/global-claude.md to ~/.claude/CLAUDE.md (tool catalog)
├── Step 7: broot init
├── Step 8: topiary install (binary + grammar via vendored topiary-nushell + config)
└── Step 9: Claude Code install + register nushell as stdio MCP via `claude mcp add`
```

## Build & Run

```sh
docker build -t cozy:v1 .
docker sandbox create -t cozy:v1 shell ~/path/to/project
#                     ^^image    ^^agent ^^workspace
```

The agent name (`claude`, `shell`, etc.) selects which agent process runs inside the sandbox — it is independent of the base image (`docker/sandbox-templates:shell`) used in the Dockerfile.

Requires Docker Desktop 4.58+ on macOS or Windows.

## Sandbox Management

```sh
docker sandbox ls
docker sandbox exec -it <name> nu        # shell into sandbox with nushell
docker sandbox exec -it -w /home/agent <name> nu  # start from home dir
docker sandbox stop <name>
docker sandbox rm <name>
```

## Local Docs

`toolkit docs` downloads Docker sandbox documentation as markdown into `docs.docker.com/` — a self-contained git repo inside `cozy/`, ignored by `.gitignore`. Re-run to sync updates; idempotent. When you need Docker sandbox docs, read from `docs.docker.com/` instead of fetching from the web.

## Rebuilding

After Dockerfile changes: rebuild image, then recreate sandbox (delete + run).

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
- Keybindings: `vendor/dotfiles/zellij/config.kdl` (README keybinding docs drift from this)
- Vendored modules: `toolkit/vendor.yml` via `toolkit/vendor.nu` (not the CLAUDE.md architecture list). `toolkit/vendor.nu` also projects it into `cozy-module/vendored-repos.nuon` — the manifest that ships into the sandbox, read by `cozy sync-repos` and `cozy-module/verify.nu`. `toolkit check` guards the manifest against `vendor.yml`; never hardcode the list
- `cozy` command surface: `cozy-module/mod.nu` exports
- Post-build verification: `cozy-module/verify.nu` — one check set, run by `cozy verify` (inside a sandbox) and `nu toolkit/test.nu test` (host, via `docker sandbox exec`). Checks take a transport closure so the same code runs both ways; expected values derive from `vendored-repos.nuon`, the `docker-files/nushell-autoload/` glob and `bootstrap.nu`'s env exports — never hand-listed
- Install step order (host + docker + kit): `cozy-module/install/bootstrap.nu` — single entry point for all build paths
- Pinned nushell fallback: `cozy-module/install/.nushell-version` — consumed by `ensure-nu.sh` when latest `nu` can't parse `bootstrap.nu`
- Kit spec for `sbx run shell --kit ./sbx-kit/`: `sbx-kit/spec.yaml` — environment + commands.install mirror the Dockerfile ENV + RUN block; the kit clones cozy in-sandbox and runs the same `bootstrap.nu`. The shared env values (Dockerfile ENV / kit / `bootstrap.nu` exports) can't share one literal across the three formats — `toolkit check` guards them against drift
- CHANGELOG entries are historical — cross-reference sequential versions for contradictions

## Notes

- Workspace is mounted at its original host path (e.g. `/Users/user/temp/docker/`), not at `/workspace` or `/home/agent`
- Only the workspace folder from `docker sandbox run` is synced — `exec` from a different folder doesn't mount it
- `docker sandbox create` overwrites `~/.gitconfig` on every start. For settings that must survive, write to `~/.config/git/config` (XDG) — not `/etc/gitconfig`, because brew git has its own sysconfdir and silently ignores it. Global ignore goes in `~/.config/git/ignore` (git's default; no `core.excludesFile` needed).
- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- Homebrew fetches latest versions at build time — use `brew pin` or specify versions if reproducibility matters
