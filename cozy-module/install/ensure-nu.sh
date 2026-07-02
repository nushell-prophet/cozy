#!/usr/bin/env bash
# Ensure `nu` can parse bootstrap.nu. Tries latest first (brew install
# nushell); if latest can't parse it (nushell is pre-1.0 and syntax drifts
# between releases), falls back to the pinned version in `.nushell-version`
# by downloading the matching github release into ~/.local/bin/nu —
# run-install.sh exports that dir first on PATH (and the Dockerfile/kit ENV
# keep it there at runtime), so the pinned binary shadows brew's `nu` once
# it lands.
set -euo pipefail

# Why: brew's "Do you want to proceed?" prompt (fires when an install would
# also upgrade outdated deps) hangs forever without a TTY. The Dockerfile and
# kit set these via ENV; exported here too so the host path is covered before
# the brew install below.
export HOMEBREW_NO_ASK=1 HOMEBREW_NO_AUTO_UPDATE=1

cd "$(dirname "$0")"
VERSION="$(tr -d '[:space:]' < .nushell-version)"
BOOTSTRAP="$PWD/bootstrap.nu"

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v nu >/dev/null; then
    command -v brew >/dev/null || { echo "neither nu nor brew available — install Homebrew first: https://brew.sh" >&2; exit 1; }
    brew install nushell
fi

# Smoke test: does current nu parse bootstrap.nu? `use` triggers a full
# parse + evaluation of top-level decls, and bootstrap.nu's top level is
# pure (consts + nested `use topiary.nu`/`use claude.nu`), so this is
# effectively parse-only.
if nu -c "use '$BOOTSTRAP'" >/dev/null 2>&1; then
    exit 0
fi

# Loud banner, not a one-line note: the fallback isn't a build detail, it
# changes the whole environment. ~/.local/bin is first on PATH, so the pinned
# nu shadows brew's nu for EVERY nu the sandbox runs — easy to miss in a long
# build log, so make it impossible to miss.
current_nu="$(nu --version 2>/dev/null || echo unknown)"
{
    echo
    echo "================================================================"
    echo "  cozy: FALLING BACK TO PINNED NUSHELL"
    echo "----------------------------------------------------------------"
    echo "  Latest nu ($current_nu) cannot parse bootstrap.nu."
    echo "  Installing pinned nu $VERSION into ~/.local/bin/nu."
    echo
    echo "  ~/.local/bin is FIRST on PATH, so this pinned nu shadows"
    echo "  brew's nu for the ENTIRE environment — every nu in this"
    echo "  sandbox is $VERSION, not the latest, until bootstrap.nu"
    echo "  parses under latest nu again."
    echo
    echo "  Fix: update bootstrap.nu for the new nu syntax, re-vendor,"
    echo "  rebuild, then bump .nushell-version. Until then you are on"
    echo "  the pinned nu by design."
    echo "================================================================"
    echo
} >&2

# Architecture / OS detection — same triples brew uses to pick bottles.
case "$(uname -s)" in
    Linux)  os="unknown-linux-gnu" ;;
    Darwin) os="apple-darwin" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
target="${arch}-${os}"

url="https://github.com/nushell/nushell/releases/download/${VERSION}/nu-${VERSION}-${target}.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/nu.tar.gz"
tar -xzf "$tmp/nu.tar.gz" -C "$tmp"
install -m 755 "$tmp/nu-${VERSION}-${target}/nu" "$HOME/.local/bin/nu"

# If pinned can't parse it either, bootstrap.nu has an actual bug — fail
# loudly instead of letting a broken environment install silently.
if ! nu -c "use '$BOOTSTRAP'" >/dev/null 2>&1; then
    echo "even pinned nu $VERSION can't parse bootstrap.nu — likely a real bug" >&2
    exit 1
fi

echo "cozy: pinned nu $VERSION installed and verified — this environment now runs the pinned nushell, not brew's latest." >&2
