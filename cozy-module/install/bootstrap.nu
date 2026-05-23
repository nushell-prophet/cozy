# Bootstrap installer for cozy.
#
# One entry point that sets up the sandbox (or host) end-to-end:
# brew tools, XDG git config, vendored modules under ~/repos/, dotfiles,
# Claude skills, broot, topiary, and Claude Code with the nushell MCP.
#
# Re-run = clean setup. Idempotency is not a goal.
#
# Mode auto-detection (no flags needed):
#   /etc/sandbox-persistent.sh present → run setup-docker-system (apt
#                                        installs, pbcopy, env).
#   /tmp/vendor present                → use Docker-staged vendor as-is.
#   else                               → use committed cozy_root/vendor/.
#
# Flags:
#   --local      Force-refresh vendor/ from sibling repos via
#                `toolkit/vendor.nu --local` (rsync) before mirroring it
#                under ~/repos/. Without this flag, vendor/ is used as-is —
#                no GitHub fetching, no rsync.
#   --force      Skip the host-install safety check that refuses to clobber
#                existing user configs under XDG_CONFIG_HOME, ~/.claude/,
#                ~/.visidatarc, and ~/repos/. Also needed to recover from
#                a partial first-run failure (stamp file not yet written).

use topiary.nu
use claude.nu

# Cozy repo root, derived from this file's location:
# sandbox-toolkit/install/bootstrap.nu  →  three dirnames up
const cozy_root = path self | path dirname | path dirname | path dirname

export def main [
    --local # force-refresh vendor/ from sibling repos via vendor.nu --local
    --force # skip the host-install safety check that refuses to clobber existing user configs
] {
    # Step 0 — Docker-sandbox system setup, gated on the marker file the
    # base image ships (/etc/sandbox-persistent.sh — what we append claude
    # env exports to below). Present in docker-build AND in-sandbox re-runs,
    # absent on macOS host install — exactly the partition we want.
    if ('/etc/sandbox-persistent.sh' | path exists) {
        setup-docker-system
    } else if not $force {
        # Host install: refuse to clobber existing user configs. Skipped in
        # Docker (clean sandbox) and on re-runs (via ~/.cozy-installed stamp).
        check-no-clobber
    }

    # Step 1 — brew installs
    if (which brew | is-empty) {
        error make {msg: "brew not found — install Homebrew first: https://brew.sh"}
    }
    ^brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd jj git-lfs
    ^brew cleanup --prune=all

    # Step 2 — XDG git config. user.name/email is written here so `toolkit
    # push-to-machine --commit-changes` (step 4) can commit; writing to XDG
    # rather than /etc/gitconfig avoids sudo and works for both apt-git
    # (build) and brew-git (runtime). It's also safe on a real host: git
    # precedence has ~/.gitconfig (global) overriding XDG, so a user's
    # personal email wins; XDG only kicks in when nothing else is set.
    let git_xdg = $nu.home-dir | path join '.config' 'git'
    mkdir $git_xdg
    '[user]
	name = Agent
	email = agent@sandbox
[safe]
	directory = *
[gc]
	auto = 0
[core]
	fsync = all
	fsyncMethod = fsync
' | save -f ($git_xdg | path join 'config')
    ".DS_Store\nThumbs.db\ndesktop.ini\n" | save -f ($git_xdg | path join 'ignore')

    # Step 3 — populate ~/repos/ with vendored modules
    populate-repos --local=$local

    # Sandbox-specific config (feature parity with Dockerfile):
    # nushell autoload scripts and visidata config.
    # Wipe the autoload dir first: cozy owns it, any file not deployed by
    # the current run is stale (e.g. an entry removed upstream). Without
    # this, re-runs accumulated removed-upstream autoload files
    # indefinitely (originally fixed for docker, missing on host until M2).
    let autoload_dst = $nu.home-dir | path join '.config' 'nushell' 'autoload'
    if ($autoload_dst | path exists) { rm -rf $autoload_dst }
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

    # Step 8 — topiary install (binary + grammar + config).
    # topiary.nu reads ~/git/topiary-nushell, but the vendor flow lands the
    # grammar repo at ~/repos/topiary-nushell/. Bridge with a symlink so
    # topiary install picks up the vendored copy instead of cloning from
    # GitHub. No clone fallback per fail-fast: if vendored dir is missing,
    # topiary install should fail loudly so the build flow is fixed at its
    # source.
    let vendored = $nu.home-dir | path join 'repos' 'topiary-nushell'
    let link = $nu.home-dir | path join 'git' 'topiary-nushell'
    if ($vendored | path exists) and ($link | path type) != 'symlink' {
        mkdir ($link | path dirname)
        ^ln -s $vendored $link
    }
    topiary install

    # Step 9 — Claude Code + nushell MCP
    claude install
    ^claude mcp add --scope user --transport stdio nushell -- (which nu | get path.0) --mcp

    # Stamp: tells check-no-clobber on re-runs that cozy owns these dirs
    # now, so its guard doesn't trip on cozy's own deployed files. Written
    # last so a partial failure leaves no stamp — user has to pass --force
    # to recover, which is a reasonable speed bump.
    '' | save -f ($nu.home-dir | path join '.cozy-installed')

    # If setup-docker-system just appended env exports to /etc/sandbox-persistent.sh
    # but the user's interactive shell predates this run, those exports won't be
    # in their bash env yet — tools like helix, jj, etc. would launch without
    # HELIX_RUNTIME/JJ_CONFIG/etc. Detect via missing XDG_DATA_HOME (the marker
    # we baked) and tell them to re-login. env.nu has a fallback so nu itself
    # won't crash, but the broader env still needs the refresh.
    if ('/etc/sandbox-persistent.sh' | path exists) and ($env.XDG_DATA_HOME? | is-empty) {
        print ""
        print "Note: env exports were written to /etc/sandbox-persistent.sh but your"
        print "      current shell predates the bootstrap. Run `exec bash -l` to start"
        print "      a fresh login shell before launching nu."
    }
}

# Host-install safety guard. Refuses to proceed if XDG_CONFIG_HOME dirs or
# other deploy targets already contain user files — without this, a Mac
# user with their own helix/zellij/nushell configs would silently lose them
# at step 3.5 (autoload wipe) or step 4 (push-to-machine, which writes
# config.nu/env.nu/config.toml/etc. with --force). Skipped on re-runs via
# ~/.cozy-installed stamp, and entirely with --force.
#
# Conservative by design: checks dirs (not individual files in
# paths-docker.csv) so the user is asked even when their custom files
# wouldn't actually conflict. --force is the escape hatch.
def check-no-clobber [] {
    let stamp = $nu.home-dir | path join '.cozy-installed'
    if ($stamp | path exists) { return }

    let xdg_config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join '.config')
    let candidates = [
        ($xdg_config | path join 'nushell')
        ($xdg_config | path join 'helix')
        ($xdg_config | path join 'zellij')
        ($xdg_config | path join 'lazygit')
        ($xdg_config | path join 'broot')
        ($xdg_config | path join 'jj')
        ($xdg_config | path join 'git')
        ($nu.home-dir | path join '.claude')
        ($nu.home-dir | path join '.visidatarc')
        ($nu.home-dir | path join 'repos')
    ]
    let existing = $candidates | where {|p|
        ($p | path exists) and (
            ($p | path type) != 'dir' or (ls --all $p | is-not-empty)
        )
    }
    if ($existing | is-empty) { return }

    print "cozy host install would clobber existing entries:"
    for p in $existing { print $"  ($p)" }
    print ""
    print "Back them up or move aside, then re-run with --force to proceed."
    exit 1
}

# Docker-only: what the USER root layers in the Dockerfile used to do.
# Sudo is kept only for genuinely root-owned paths: apt itself and the apt
# sources files under /etc/apt/. Agent has passwordless sudo at build time,
# same assumption already made by topiary.nu and rust.nu.
def setup-docker-system [] {
    # Wipe only the colliding artifacts in ~/.config/nushell — `nu`
    # auto-creates default config.nu/env.nu on first launch, and on a
    # re-run those defaults can collide with the dotfiles deploy in step 4
    # (or with bootstrap's own autoload write between steps 3 and 4). The
    # docstring at the top of this file says "Re-run = clean setup" —
    # this is what makes that true for the nushell config dir.
    #
    # Not `rm -rf $nu_config` because: history.sqlite3* and plugin.msgpackz
    # live in the same dir and are user state, not collidable config. The
    # whole-dir wipe destroyed shell history every re-run.
    let nu_config = $nu.home-dir | path join '.config' 'nushell'
    for f in ['config.nu' 'env.nu'] {
        let p = $nu_config | path join $f
        if ($p | path exists) { rm $p }
    }
    # Autoload dir wipe is in main (runs on host too) — see step before
    # the autoload copy. Not duplicated here.

    # Rewrite Canonical apt sources from http:// to https:// before any apt
    # call. The sandbox VM refuses direct egress to :80 but allows :443, so
    # HTTPS sources work everywhere (docker build, fresh sandbox install,
    # cozy:v1 re-run) without a proxy. Idempotent — re-applies on every
    # bootstrap so a base-image refresh can't strand us back on plain http.
    # Covers both deb822 (.sources, Ubuntu 24.04+) and one-line (.list, legacy).
    let apt_sources_files = (
        ['/etc/apt/sources.list']
        | append (ls /etc/apt/sources.list.d/ | get name)
        | where { |p| $p | path exists }
    )
    for f in $apt_sources_files {
        let content = open --raw $f
        let updated = $content | str replace --all --regex 'http://(ports|archive|security)\.ubuntu\.com' 'https://$1.ubuntu.com'
        if $updated != $content {
            $updated | ^sudo tee $f | ignore
        }
    }

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

    # Runtime env exports (the sandbox shell sources this file on each login).
    # /etc/sandbox-persistent.sh is agent-writable on the base image — matches
    # the original Dockerfile's USER-agent `>>` approach, no sudo needed.
    # The XDG/HELIX/LANG block mirrors the Dockerfile's ENV directives so
    # in-sandbox installs against the base image get the same runtime env
    # cozy:v1 has baked in (XDG_DATA_HOME is what dotfiles' env.nu reads —
    # without it `nu` fails to start with "Cannot find column XDG_DATA_HOME").
    let env_exports = 'export GIT_AUTHOR_NAME="Claude"
export GIT_AUTHOR_EMAIL="claude@anthropic.com"
export GIT_COMMITTER_NAME="Claude"
export GIT_COMMITTER_EMAIL="claude@anthropic.com"
export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export HELIX_RUNTIME="/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime"
export LANG="C.UTF-8"
'
    # Wrap with markers so re-runs replace the block in place instead of
    # `save --append`-ing a duplicate copy on every bootstrap invocation.
    let block = $"# >>> cozy env >>>\n($env_exports)# <<< cozy env <<<\n"
    let target = '/etc/sandbox-persistent.sh'
    let existing = if ($target | path exists) { open --raw $target } else { '' }
    let marker_re = '(?ms)# >>> cozy env >>>.*?# <<< cozy env <<<\n?'
    let updated = if ($existing =~ $marker_re) {
        # Why: str replace --regex treats `$name` in the replacement as a
        # capture-group backref (regex crate convention), which would eat
        # the literal `$HOME` in our exports. Escape `$` -> `$$` so the
        # replacement keeps `$HOME` etc. intact.
        let escaped = $block | str replace --all '$' '$$'
        $existing | str replace --regex $marker_re $escaped
    } else {
        $existing + $block
    }
    $updated | save --force $target
}

# Place vendored modules under ~/repos/<repo>/<module>/.
# Source priority:
#   1. /tmp/vendor (Dockerfile COPY staged it) — used as-is, unless --local.
#   2. cozy_root/vendor/ — committed in the repo, regenerated via vendor.nu
#      only when empty (first-ever run) or --local forces a refresh from
#      sibling repos. Avoids re-downloading tarballs on every clone.
def populate-repos [--local] {
    let repos_dir = $nu.home-dir | path join 'repos'
    mkdir $repos_dir

    # Deposit cozy/sandbox-toolkit/ and cozy/docker-files/ at ~/repos/cozy/.
    # In docker the Dockerfile COPYed them there already, so cozy_root IS
    # ~/repos/cozy/ and the equality check skips this. On host cozy_root
    # points at the workspace mount, so we mirror just those two subdirs
    # (avoiding vendor/, docs.docker.com/, .git/, etc.).
    let cozy_dst = $repos_dir | path join 'cozy'
    if ($cozy_root | path expand) != ($cozy_dst | path expand) {
        mkdir $cozy_dst
        for sub in [sandbox-toolkit docker-files] {
            let dst = $cozy_dst | path join $sub
            if ($dst | path exists) { rm -rf $dst }
            ^cp -r ($cozy_root | path join $sub) $dst
        }
    }

    let vendor_src = if not $local and ('/tmp/vendor' | path exists) {
        '/tmp/vendor'
    } else {
        let dir = $cozy_root | path join 'vendor'
        let populated = ($dir | path exists) and ((glob ($dir | path join '*')) | is-not-empty)
        if $local or not $populated {
            let arg = if $local { ['--local'] } else { [] }
            ^nu --no-config-file ($cozy_root | path join 'toolkit' 'vendor.nu') ...$arg
        }
        $dir
    }
    for entry in (glob ($vendor_src | path join '*')) {
        let dst = $repos_dir | path join ($entry | path basename)
        if ($dst | path exists) { rm -rf $dst }
        ^cp -r $entry $repos_dir
    }
}
