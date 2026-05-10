# Bootstrap installer for cozy.
#
# One entry point that sets up the sandbox (or host) end-to-end:
# brew tools, XDG git config, vendored modules under ~/repos/, dotfiles,
# Claude skills, broot, topiary, and Claude Code with the nushell MCP.
#
# Re-run = clean setup. Idempotency is not a goal.
#
# Modes:
#   --in-docker  Invoked from the Dockerfile RUN layer. Vendor was already
#                COPYied to /tmp/vendor; sandbox-toolkit + docker-files were
#                COPYied directly to ~/repos/cozy/.
#   --local      Host only. Forwards to `toolkit/vendor.nu --local` to rsync
#                from sibling repos instead of fetching GitHub tarballs.

use topiary.nu
use claude.nu

# Cozy repo root, derived from this file's location:
# sandbox-toolkit/install/bootstrap.nu  →  three dirnames up
const cozy_root = path self | path dirname | path dirname | path dirname

export def main [
    --in-docker # invoked from Dockerfile RUN (vendor already staged at /tmp/vendor)
    --local     # use sibling repos via vendor.nu --local (host only)
] {
    # Step 0 — Docker-sandbox system setup. Auto-detect via the marker file
    # the base image ships (/etc/sandbox-persistent.sh — what we append
    # claude env exports to below). When present, run setup-docker-system
    # whether or not --in-docker was passed, so in-sandbox re-runs work the
    # same as docker-build invocations. Skipped on macOS host install
    # because the marker isn't there.
    if ('/etc/sandbox-persistent.sh' | path exists) { setup-docker-system }

    # Step 1 — brew installs (two groups for build-cache reuse, matches Dockerfile)
    if (which brew | is-empty) {
        error make { msg: "brew not found — install Homebrew first: https://brew.sh" }
    }
    ^brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd
    ^brew cleanup --prune=all
    ^brew install jj git-lfs
    ^brew cleanup --prune=all

    # Step 2 — XDG git config. user.name/email is written here so `toolkit
    # push-to-machine --commit-changes` (step 4) can commit; writing to XDG
    # rather than /etc/gitconfig avoids sudo and works for both apt-git
    # (build) and brew-git (runtime). It's also safe on a real host: git
    # precedence has ~/.gitconfig (global) overriding XDG, so a user's
    # personal email wins; XDG only kicks in when nothing else is set.
    let git_xdg = $nu.home-dir | path join '.config' 'git'
    mkdir $git_xdg
    "[user]\n\tname = Agent\n\temail = agent@sandbox\n[safe]\n\tdirectory = *\n[gc]\n\tauto = 0\n[core]\n\tfsync = all\n\tfsyncMethod = fsync\n" | save -f ($git_xdg | path join 'config')
    ".DS_Store\nThumbs.db\ndesktop.ini\n" | save -f ($git_xdg | path join 'ignore')

    # Step 3 — populate ~/repos/ with vendored modules
    populate-repos --in-docker=$in_docker --local=$local

    # Sandbox-specific config (feature parity with Dockerfile):
    # nushell autoload scripts and visidata config.
    let autoload_dst = $nu.home-dir | path join '.config' 'nushell' 'autoload'
    mkdir $autoload_dst
    for f in (glob ($cozy_root | path join 'docker-files' 'nushell-autoload' '*.nu')) {
        ^cp $f $autoload_dst
    }
    ^cp ($cozy_root | path join 'docker-files' '.visidatarc') ($nu.home-dir | path join '.visidatarc')

    # Steps 4 & 5 — deploy dotfiles and Claude skills from ~/repos/dotfiles.
    # Spawn nu so toolkit.nu's `use`/cwd-relative paths work as in the existing
    # Dockerfile. Always pass `--docker` because cozy only vendors
    # paths-docker.csv (see toolkit/vendor.yml) — host install is feature
    # parity and uses the same paths file as the docker install.
    cd ($nu.home-dir | path join 'repos' 'dotfiles')
    ^nu --no-config-file --commands 'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker --commit-changes'
    ^nu --no-config-file --commands 'use toolkit.nu; toolkit install-skills --all'

    # Step 6 — append global Claude instructions to ~/.claude/CLAUDE.md
    let claude_md = $nu.home-dir | path join '.claude' 'CLAUDE.md'
    mkdir ($claude_md | path dirname)
    "\n" | save --append $claude_md
    open --raw ($cozy_root | path join 'docker-files' 'global-claude.md') | save --append $claude_md

    # Step 7 — broot init (moved here from Dockerfile so host gets it too)
    let xdg_config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join '.config')
    ^broot --write-default-conf ($xdg_config | path join 'broot')
    ^broot --set-install-state installed

    # Step 8 — topiary install (binary + grammar + config)
    topiary install

    # Step 9 — Claude Code + nushell MCP
    claude install
    ^claude mcp add --scope user --transport stdio nushell -- /home/linuxbrew/.linuxbrew/bin/nu --mcp
}

# Docker-only: what the USER root layers in the Dockerfile used to do.
# Sudo is kept only for genuinely root-owned paths: apt itself, and the apt
# proxy file (APT_CONFIG env-var indirection wouldn't work because sudo
# strips it before invoking apt). Agent has passwordless sudo at build time,
# same assumption already made by topiary.nu and rust.nu.
def setup-docker-system [] {
    # Wipe any pre-existing ~/.config/nushell — `nu` auto-creates default
    # config.nu/env.nu/history.* on first launch, and on a re-run those
    # defaults can collide with the dotfiles deploy in step 4 (or with
    # bootstrap's own autoload write between steps 3 and 4). The
    # docstring at the top of this file says "Re-run = clean setup" —
    # this is what makes that true for the nushell config dir.
    let nu_config = $nu.home-dir | path join '.config' 'nushell'
    if ($nu_config | path exists) { rm -rf $nu_config }

    # Apt proxy first — must exist before `apt-get update` so apt routes
    # through host.docker.internal:3128 (Docker Desktop's HTTP proxy).
    # Direct egress to ports.ubuntu.com:80 is refused inside the sandbox
    # network, so without the proxy in place `apt-get update` fails.
    # The file lives under /etc/apt/apt.conf.d/ rather than via APT_CONFIG
    # env-var indirection because sudo strips APT_CONFIG before invoking apt.
    let proxy_conf = 'Acquire::http::Proxy "http://host.docker.internal:3128/";
Acquire::https::Proxy "http://host.docker.internal:3128/";
'
    $proxy_conf | ^sudo tee /etc/apt/apt.conf.d/90proxy | ignore

    # apt deps: gcc/libc6-dev for tree-sitter-nu compile in `topiary install`,
    # procps/file as general runtime tools.
    ^sudo apt-get update
    ^sudo apt-get install -y --no-install-recommends procps file gcc libc6-dev
    ^sudo rm -rf /var/lib/apt/lists/*

    # Why: Docker sandbox has no system clipboard. This shim uses OSC 52 escape
    # sequences to push copied text to the host terminal's clipboard. Consumed by
    # helix, lazygit, broot, nushell keybindings, and nu-goodies commands.
    # Goes to ~/.local/bin (already on PATH via Dockerfile ENV) so we don't
    # need sudo for /usr/local/bin.
    let local_bin = $nu.home-dir | path join '.local' 'bin'
    mkdir $local_bin
    ^install -m 755 ($cozy_root | path join 'docker-files' 'pbcopy') ($local_bin | path join 'pbcopy')

    # Claude runtime env vars (sourced by sandbox shell).
    # /etc/sandbox-persistent.sh is agent-writable on the base image — matches
    # the original Dockerfile's USER-agent `>>` approach, no sudo needed.
    let claude_envs = 'export GIT_AUTHOR_NAME="Claude"
export GIT_AUTHOR_EMAIL="claude@anthropic.com"
export GIT_COMMITTER_NAME="Claude"
export GIT_COMMITTER_EMAIL="claude@anthropic.com"
export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"
'
    $claude_envs | save --append /etc/sandbox-persistent.sh
}

# Place vendored modules under ~/repos/<repo>/<module>/.
# --in-docker: prefer the /tmp/vendor staging the Dockerfile sets up. Falls
# back to vendor.nu when /tmp/vendor is absent (in-sandbox manual re-runs).
def populate-repos [--in-docker --local] {
    let repos_dir = $nu.home-dir | path join 'repos'
    mkdir $repos_dir
    mkdir ($nu.home-dir | path join 'workspace')

    let staged = if ('/tmp/vendor' | path exists) { glob /tmp/vendor/* } else { [] }
    if $in_docker and ($staged | is-not-empty) {
        # Vendor staged at /tmp/vendor by Docker COPY. sandbox-toolkit and
        # docker-files were COPYied directly to ~/repos/cozy/ — nothing to do
        # for them here.
        for entry in $staged {
            ^cp -r $entry $repos_dir
        }
        return
    }

    # No staged vendor — regenerate cozy/vendor/ via vendor.nu, then mirror.
    let vendor_arg = if $local { ['--local'] } else { [] }
    ^nu --no-config-file ($cozy_root | path join 'toolkit' 'vendor.nu') ...$vendor_arg
    for entry in (glob ($cozy_root | path join 'vendor' '*')) {
        ^cp -r $entry $repos_dir
    }
}
