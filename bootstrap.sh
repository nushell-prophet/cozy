#!/usr/bin/env bash
# Host entry to the same installer the Dockerfile runs.
# Usage: ./bootstrap.sh [--local]
#   --local : forwarded to bootstrap.nu, which then calls toolkit/vendor.nu --local
#             (rsync from sibling repos instead of github tarball clone).
set -euo pipefail
cd "$(dirname "$0")"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
export PATH="$HOME/.local/bin:$PATH"
sandbox-toolkit/install/ensure-nu.sh
nu sandbox-toolkit/install/bootstrap.nu "$@"

# Why: on macOS, `nu` without XDG_CONFIG_HOME reads
# ~/Library/Application Support/nushell/ — but bootstrap.nu deploys dotfiles
# to ~/.config/nushell/, so they'd be invisible to nu. Export XDG_CONFIG_HOME
# in the user's shell rc. Mirrors the `# >>> cozy env >>>` block
# bootstrap.nu writes to /etc/sandbox-persistent.sh in Docker.
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
