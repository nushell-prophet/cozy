# ai-sandbox

Modern, beginner-friendly terminal environment for AI-assisted development, running inside `docker sandbox`. Includes Nushell, Zellij, Helix, Lazygit, Broot, and Claude Code — all configured to work out of the box.

## Base Image

`docker/sandbox-templates:claude-code` — Ubuntu-based, includes git, curl, Python, Node.js, Go, ripgrep, jq, gh CLI.

## Added Tools

- **Nushell**, **Helix** (`hx`), **Lazygit**, **Zellij**, **Broot**, **fzf**, **Carapace** — via Homebrew (`brew install`)
- **Rust** (rustc, cargo, rustup) — installed as `agent` user via rustup

## Build & Run

```sh
docker build -t nushell-ai-sandbox:v1 ~/git/ai-sandbox
docker sandbox run --load-local-template -t nushell-ai-sandbox:v1 claude ~/path/to/project
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

## Notes

- Workspace is mounted at its original macOS path (e.g. `/Users/user/temp/docker/`), not at `/workspace` or `/home/agent`
- Only the workspace folder from `docker sandbox run` is synced — `exec` from a different folder doesn't mount it
- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- Homebrew fetches latest versions at build time — use `brew pin` or specify versions if reproducibility matters
