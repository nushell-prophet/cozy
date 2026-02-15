# Claude Code Docker Sandbox

Custom Docker sandbox template for running Claude Code on M1 Macs with extra tools.

## Base Image

`docker/sandbox-templates:claude-code` — Ubuntu-based, includes git, curl, Python, Node.js, Go, ripgrep, jq, gh CLI.

## Added Tools

- **Nushell** — via Gemfury apt repo
- **Helix** (`hx`) — from GitHub release binary, runtime at `/usr/local/lib/helix-runtime`
- **Lazygit** — from GitHub release with sha256 checksum verification
- **Rust** (rustc, cargo, rustup) — installed as `agent` user via rustup

## Build & Run

```sh
docker build -t claude-nushell:v1 ~/temp/docker
docker sandbox run --load-local-template -t claude-nushell:v1 claude ~/path/to/project
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

## Notes

- Sandbox uses microVMs — won't work inside UTM on M1 (no nested virtualization)
- Base image CVEs (e.g. in `/usr/bin/docker`) are fixed upstream — pull latest base image periodically
- lazygit/helix fetch latest release at build time — pin versions in Dockerfile if reproducibility matters
