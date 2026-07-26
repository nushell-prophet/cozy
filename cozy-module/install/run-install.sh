#!/usr/bin/env bash
# The one boot tail shared by all three install paths — Dockerfile RUN,
# sbx-kit commands.install, and a plain host checkout:
#   ensure brew → ensure-nu.sh (installs nu if missing, pins on syntax drift)
#   → nu bootstrap.nu
# Callers differ only in how the checkout lands (COPY / git clone / you);
# the command sequence lives here and nowhere else, so the paths can't
# drift in ordering.
#
# Usage: cozy-module/install/run-install.sh [--force]
#   --force : skip the host-install safety check that refuses to clobber
#             existing user configs (see bootstrap.nu's check-no-clobber).
set -euo pipefail
cd "$(dirname "$0")"

# Brew's installer needs sudo to chown /opt/homebrew (or /usr/local/Homebrew
# on Intel macs, /home/linuxbrew/.linuxbrew on Linux). NONINTERACTIVE=1 only
# switches `sudo` to `sudo -n`, which aborts without cached creds — it does
# not bypass sudo. So on a normal macOS host we'd either prompt for a
# password or fail outright, which breaks the no-prompts flow this script
# is built around. Auto-install only on Linux with passwordless sudo (e.g.
# the sbx `shell` agent); on macOS, always fail-fast with the copy-paste
# snippet so the user's password prompt stays out of the script.
# The Dockerfile runs this same installer line as its own cached layer
# before calling this script, so there this block no-ops.
command -v brew >/dev/null || {
    if [ "$(uname)" = Linux ] && sudo -n true 2>/dev/null; then
        # Not `bash -c "$(curl …)"` because: when curl fails the substitution is
        # empty and `bash -c ''` exits 0, so a blocked host or a proxy 403 read
        # as a successful install. `set -e` never fired, and the real cause
        # surfaced two steps later at ensure-nu.sh as "neither nu nor brew
        # available — install Homebrew first", blaming the user for a network
        # failure. Download to a file so curl's own exit status is checked.
        brew_installer="$(mktemp)"
        trap 'rm -f "$brew_installer"' EXIT
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$brew_installer"
        NONINTERACTIVE=1 /bin/bash "$brew_installer"
        # The installer never touches this shell's PATH — without this line a
        # fresh Linux host installs brew and can't find it one command later.
        # `eval` of an empty string also exits 0, so assert rather than assume.
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        command -v brew >/dev/null || {
            echo "the Homebrew installer finished but brew is not on PATH" >&2
            exit 1
        }
    else
        echo "Install Homebrew first: https://brew.sh"
        echo '  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
}

export PATH="$HOME/.local/bin:$PATH"
./ensure-nu.sh
# ${1+"$@"} not "$@": under set -u, bash < 4.4 treats empty "$@" as unbound —
# and the shebang resolves to Apple's /bin/bash 3.2 on a stock Mac, so the
# README's plain no-flag install would die right here.
nu bootstrap.nu ${1+"$@"}

# Why: on macOS, `nu` without XDG_CONFIG_HOME reads
# ~/Library/Application Support/nushell/ — but bootstrap.nu deploys dotfiles
# to ~/.config/nushell/, so they'd be invisible to nu. Export XDG_CONFIG_HOME
# in the user's shell rc. Mirrors the `# >>> cozy env >>>` block
# bootstrap.nu writes to /etc/sandbox-persistent.sh in containers.
# Host-only: containers get the env from the Dockerfile ENV / kit variables /
# sandbox-persistent.sh. Same container detection as bootstrap.nu Step 0.
if [ ! -e /etc/sandbox-persistent.sh ] && [ ! -e /.dockerenv ]; then
    case "${SHELL:-}" in
        */zsh)  rcfile="$HOME/.zshrc" ;;
        */bash) rcfile="$HOME/.bash_profile" ;;
        *)      rcfile="" ;;
    esac

    if [ -n "$rcfile" ] && ! { [ -f "$rcfile" ] && grep -q '# >>> cozy env >>>' "$rcfile"; }; then
        {
            printf '\n# >>> cozy env >>>\n'
            printf 'export XDG_CONFIG_HOME="$HOME/.config"\n'
            printf '# <<< cozy env <<<\n'
        } >> "$rcfile"
        echo "Added XDG_CONFIG_HOME export to $rcfile — restart your terminal or run 'exec $SHELL -l'."
    fi
fi
