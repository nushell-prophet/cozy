# ai-sandbox

Customized Docker sandbox image for Claude Code. Extends the base `docker/sandbox-templates:claude-code` with Nushell, Helix, and a curated set of terminal tools.

## Architecture

```
Dockerfile
├── Base: docker/sandbox-templates:claude-code (Ubuntu, git, curl, Python, Node.js, Go, rg, jq, gh)
├── apt: procps, file
├── Homebrew tools: nushell, helix, lazygit, zellij, broot, fzf, carapace, git-delta, jj, visidata
├── Dotfiles: cloned from github.com/nushell-prophet/my-dotfiles at build time
│   └── toolkit push-to-machine deploys configs for helix, lazygit, zellij, broot, nushell, claude
├── Vendored Nushell modules: nu-goodies, dotnu, numd, claude-nu, nu-cmd-stack, nushell-kv
│   └── vendor/ dir (default) or git clone (with --build-arg MODULES_SOURCE=clone)
└── Nushell autoload scripts: copied into ~/.config/nushell/autoload/
```

## Build & Run

```sh
docker build -t nushell-ai-sandbox:v1 .
docker sandbox run --load-local-template -t nushell-ai-sandbox:v1 claude ~/path/to/project
```

Requires Docker Desktop 4.58+ on macOS.

## Key Paths Inside the Sandbox

| Path | Purpose |
|---|---|
| `/home/agent/ws` | Symlink to the mounted workspace |
| `/home/agent/git/` | Vendored Nushell modules and dotfiles clone |
| `~/.config/nushell/autoload/` | Nushell scripts sourced on every interactive session |
| `~/.claude/settings.json` | Claude Code settings (overwritten by sandbox create; MCP server config is self-healing via autoload) |
| `/etc/sandbox-persistent.sh` | Persistent env vars across bash invocations (`CLAUDE_ENV_FILE`) |

## Rules

- All images are local-only. Do NOT push to Docker Hub or any registry.
- Workspace is mounted at its original macOS path (e.g. `/Users/user/project/`), not `/workspace`.
- After Dockerfile changes: rebuild image, then recreate sandbox (stop + rm + run).

## Vendored Modules

The `vendor/` directory contains snapshots of Nushell modules. To build with live clones instead:

```sh
docker build --build-arg MODULES_SOURCE=clone -t nushell-ai-sandbox:v1 .
```

To refresh vendored snapshots, update the repos under `vendor/` and rebuild.

## Nushell Autoload

Scripts in `nushell-autoload/` are copied to `~/.config/nushell/autoload/` at build time. They handle:
- Carapace completions bridge
- Broot shell wrapper (`br`)
- Module imports
- MCP server registration (self-healing after sandbox recreate)
- Hook configuration

## Notes

- Only the workspace folder from `docker sandbox run` is synced — `exec` from a different folder doesn't mount it
- Sandbox uses microVMs — no nested virtualization (won't work inside UTM on M1)
- Homebrew fetches latest versions at build time — use `brew pin` for reproducibility
- Base image CVEs are fixed upstream — pull latest base periodically
