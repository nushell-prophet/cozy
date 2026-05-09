#!/usr/bin/env bash
# Host entry to the same installer the Dockerfile runs.
# Usage: ./bootstrap.sh [--local]
#   --local : forwarded to bootstrap.nu, which then calls toolkit/vendor.nu --local
#             (rsync from sibling repos instead of github tarball clone).
set -euo pipefail
cd "$(dirname "$0")"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
command -v nu   >/dev/null || brew install nushell
exec nu sandbox-toolkit/install/bootstrap.nu "$@"
