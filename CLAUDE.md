# cozy

Modern, beginner-friendly terminal environment for AI agents, running inside `docker sandbox`. Tested with Claude Code; other agents can be configured via `docker sandbox`.

## Architecture

```
Dockerfile
├── Base: docker/sandbox-templates:shell (Ubuntu, git, curl, Python, Node.js, Go, rg, jq, gh)
├── apt: procps, file, gcc, libc6-dev
├── Homebrew tools: nushell, helix, lazygit, zellij, broot, fzf, git-delta, git-lfs, jj, visidata, bat, topiary
├── Vendored modules and dotfiles: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest, topiary-nushell, dotfiles, my-claude-skills, nushell-skills
├── sandbox-toolkit/: runtime toolkit (the `cozy` overlay) — lives in-repo, copied or cloned into ~/repos/cozy/ at build time
│   └── vendor/ dir (default) or git clone (with --build-arg MODULES_SOURCE=clone)
├── Dotfiles: vendored from dotfiles/ sibling repo, deployed via toolkit push-to-machine
│   └── configs for helix, lazygit, zellij, broot, nushell, claude
├── Claude Code: installed via official install script (https://claude.ai/install.sh), late layer
├── Nushell autoload scripts: copied into ~/.config/nushell/autoload/
├── docker-files/global-claude.md: appended to sandbox ~/.claude/CLAUDE.md (tool catalog for Claude)
└── MCP: nushell registered as stdio MCP server via `claude mcp add`
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

## Notes

- Workspace is mounted at its original host path (e.g. `/Users/user/temp/docker/`), not at `/workspace` or `/home/agent`
- Only the workspace folder from `docker sandbox run` is synced — `exec` from a different folder doesn't mount it
- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- Homebrew fetches latest versions at build time — use `brew pin` or specify versions if reproducibility matters
