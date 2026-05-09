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
    # Step 1 — brew installs (two groups for build-cache reuse, matches Dockerfile)
    if (which brew | is-empty) {
        error make { msg: "brew not found — install Homebrew first: https://brew.sh" }
    }
    ^brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd
    ^brew cleanup --prune=all
    ^brew install jj git-lfs
    ^brew cleanup --prune=all

    # Step 2 — XDG git config (per Dockerfile lines 82–84)
    let git_xdg = $nu.home-dir | path join '.config' 'git'
    mkdir $git_xdg
    "[safe]\n\tdirectory = *\n[gc]\n\tauto = 0\n[core]\n\tfsync = all\n\tfsyncMethod = fsync\n" | save -f ($git_xdg | path join 'config')
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
    # Spawn nu so toolkit.nu's `use`/cwd-relative paths work as in the existing Dockerfile.
    cd ($nu.home-dir | path join 'repos' 'dotfiles')
    let push_cmd = if $in_docker {
        'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker --commit-changes'
    } else {
        'use toolkit.nu; toolkit push-to-machine --force --create-dirs --commit-changes'
    }
    ^nu --no-config-file --commands $push_cmd
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

# Place vendored modules under ~/repos/<repo>/<module>/.
def populate-repos [--in-docker --local] {
    let repos_dir = $nu.home-dir | path join 'repos'
    mkdir $repos_dir
    mkdir ($nu.home-dir | path join 'workspace')

    if $in_docker {
        # Vendor was staged at /tmp/vendor by Docker COPY. sandbox-toolkit and
        # docker-files were COPYied directly to ~/repos/cozy/ — nothing to do
        # for them here.
        for entry in (glob /tmp/vendor/*) {
            ^cp -r $entry $repos_dir
        }
        return
    }

    # Host: regenerate vendor/ via vendor.nu, then mirror into ~/repos/.
    let vendor_arg = if $local { ['--local'] } else { [] }
    ^nu --no-config-file ($cozy_root | path join 'toolkit' 'vendor.nu') ...$vendor_arg
    for entry in (glob ($cozy_root | path join 'vendor' '*')) {
        ^cp -r $entry $repos_dir
    }
}
