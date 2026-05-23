#!/usr/bin/env bash
# Ensure `nu` can parse bootstrap.nu. Tries latest first (brew install
# nushell); if latest can't parse it (nushell is pre-1.0 and syntax drifts
# between releases), falls back to the pinned version in `.nushell-version`
# by downloading the matching github release into ~/.local/bin/nu — both
# bootstrap.sh and the Dockerfile put that dir first on PATH, so the pinned
# binary shadows brew's `nu` once it lands.
set -euo pipefail

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

echo "nu $(nu --version 2>/dev/null || echo unknown) can't parse bootstrap.nu — falling back to pinned $VERSION" >&2

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
