# cozy

Modern, beginner-friendly terminal environment for AI agents, running inside `docker sandbox`. Tested with Claude Code; other agents can be configured via `docker sandbox`.

## Architecture

```
Dockerfile
├── Base: docker/sandbox-templates:claude-code (Ubuntu, git, curl, Python, Node.js, Go, rg, jq, gh)
├── apt: procps, file
├── Homebrew tools: nushell, helix, lazygit, zellij, broot, fzf, git-delta, git-lfs, jj, visidata, bat
├── Dotfiles: cloned from github.com/nushell-prophet/my-dotfiles at build time
│   └── toolkit push-to-machine deploys configs for helix, lazygit, zellij, broot, nushell, claude
├── Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nu-kv, nutest
│   └── vendor/ dir (default) or git clone (with --build-arg MODULES_SOURCE=clone)
└── Nushell autoload scripts: copied into ~/.config/nushell/autoload/
```

## Build & Run

```sh
docker build -t cozy:v1 .
docker sandbox create -t cozy:v1 claude ~/path/to/project
```

Requires Docker Desktop 4.58+ on macOS.

## Sandbox Management

```sh
docker sandbox ls
docker sandbox exec -it <name> nu        # shell into sandbox with nushell
docker sandbox exec -it -w /home/agent <name> nu  # start from home dir
docker sandbox stop <name>
docker sandbox rm <name>
```

## Rebuilding

After Dockerfile changes: rebuild image, then recreate sandbox (delete + run).

## Rules

- Do NOT suggest pushing images or tags to Docker Hub or any registry. All images are local-only.
- Keep command output visible — don't use quiet/silent flags (`-qq`, `-s`, `--quiet`) in scripts. Users should see what's happening during installation and setup.

## Notes

- Workspace is mounted at its original macOS path (e.g. `/Users/user/temp/docker/`), not at `/workspace` or `/home/agent`
- Only the workspace folder from `docker sandbox run` is synced — `exec` from a different folder doesn't mount it
- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- Homebrew fetches latest versions at build time — use `brew pin` or specify versions if reproducibility matters
