# Debian-based cozy image for the non-sbx run paths: plain `docker run` and
# Apple `container`. `sbx` still uses sbx-kit/ (in-sandbox build) and never
# touches this file.
#
# Why Debian over docker/sandbox-templates:shell — the template is tuned for
# agents (a pre-made `agent` user with *permanent* passwordless sudo), which is
# more privilege than cozy needs to run. cozy only needs sudo at *build* time
# (apt, brew's chown, tree-sitter compile). So we start from plain Debian, grant
# the agent passwordless sudo for the build, then revoke it in a final layer —
# the running container has an unprivileged agent. Build root, run rootless.
#
# One qualification on "run rootless", because the image cannot fix it: ENV PATH
# below leads with three agent-writable directories (~/.local/bin, ~/.cargo/bin
# and the whole agent-owned linuxbrew prefix), and an ENV is image-wide, not
# per-user. So any unqualified command name in a `docker exec -u root` resolves
# to bytes the agent controls. Putting brew on PATH for the agent is the point
# of the image, so the only real mitigation is not to run rootful execs here.

FROM debian:12-slim

# ---- build-time root layer: base deps + agent user with temporary sudo ----

# Deps the build needs before bootstrap runs: sudo (build-only, revoked below),
# ca-certificates+curl+git for the Homebrew installer and its fetches,
# build-essential+procps+file because Homebrew on Linux requires a working
# toolchain, rsync for `toolkit install-skills` (Step 5). bootstrap's Step 0
# apt-installs gcc/libc6-dev/procps/file again (harmless re-install) for the
# tree-sitter-nu compile in `topiary install`. All of these ship in the
# docker/sandbox-templates base but not in debian:12-slim.
#
# ripgrep+jq are agent tools the template bundled and slim lacks — kept on apt
# (not brew) so the change stays local to this image; the shared brew list in
# bootstrap.nu Step 1 is untouched. bookworm's rg 13 / jq 1.6 are adequate as
# leaf tools (nushell is cozy's primary data tool); brew would only buy newer
# versions at the cost of touching every install path.
#
# Rewrite apt sources http://→https:// first — same rationale as bootstrap's
# Step 0: the sandbox VM refuses egress to :80 but allows :443, so http sources
# stall on a fresh sandbox / docker-in-sandbox build. Slim ships no CA bundle
# yet (ca-certificates is one of the packages we're about to install), so this
# first apt disables TLS peer verification — apt still verifies package
# integrity via the repo's gpg signatures, independent of TLS. Once
# ca-certificates lands, every later https fetch (brew, bootstrap Step 0)
# verifies normally. Handles both the deb822 (.sources) and legacy (.list) layouts.
RUN set -e; \
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
        [ -f "$f" ] && sed -i 's|http://|https://|g' "$f" || true; \
    done; \
    apt_opts="-o Acquire::https::Verify-Peer=false -o Acquire::https::Verify-Host=false"; \
    apt-get $apt_opts update; \
    apt-get $apt_opts install -y --no-install-recommends \
        sudo ca-certificates curl git build-essential procps file rsync \
        ripgrep jq; \
    rm -rf /var/lib/apt/lists/*

# uid/gid 1000 = the conventional first non-root user. Passwordless sudo is
# granted ONLY for the build via a sudoers drop-in; the final layer deletes it
# so the running agent cannot escalate. Same build-time-sudo assumption that
# bootstrap.nu's setup-docker-system, topiary.nu and rust.nu already make.
RUN groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent-build \
    && chmod 0440 /etc/sudoers.d/agent-build

# bootstrap Step 0 (setup-docker-system) is gated on this marker OR /.dockerenv.
# BuildKit does not create /.dockerenv during RUN, so ship the marker to make
# Step 0 fire at build. Agent-writable only for the build — bootstrap appends
# the cozy env block to it; the final root layer takes ownership back, because
# root shells source this file too. Interactive shells source it via the
# bash.bashrc line below.
RUN install -o agent -g agent -m 0644 /dev/null /etc/sandbox-persistent.sh \
    && printf '\n[ -f /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh\n' \
        >> /etc/bash.bashrc

USER agent

# Cache-prime Homebrew as its own layer. run-install.sh auto-installs brew when
# it's missing, so this layer is optional for correctness — it exists so editing
# cozy-module/ doesn't re-download brew.
RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/agent/.local/bin:/home/agent/.cargo/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

ENV HELIX_RUNTIME=/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    TERM_PROGRAM=WezTerm \
    LANG=C.UTF-8

# Not `ENV HOME=/home/agent` because: an ENV is image-wide, not per-user, so it
# wins over the passwd lookup for *every* user — `docker exec -u root … bash -l`
# would then read /home/agent/.profile and /home/agent/.bashrc, agent-owned
# files from /etc/skel, as uid 0. Same primitive as the agent-writable
# /etc/sandbox-persistent.sh the final layer takes ownership of. Both the
# builder and the runtime derive HOME from the passwd entry for `USER agent`
# instead; the assert makes a builder that doesn't fail here rather than silently
# turning the XDG paths below into garbage. Values spelled literally for the
# same reason — with no ENV HOME there is no $HOME to expand at ENV time.
# (sbx-kit/spec.yaml:20-27 already spells them out; toolkit/check.nu normalizes
# $HOME to /home/agent before comparing, so both forms pass the drift guard.)
RUN [ "$HOME" = /home/agent ] || { \
        echo "HOME is [$HOME], expected /home/agent — this builder does not set HOME from the passwd entry" >&2; \
        exit 1; \
    }

ENV XDG_CONFIG_HOME=/home/agent/.config \
    XDG_DATA_HOME=/home/agent/.local/share \
    XDG_CACHE_HOME=/home/agent/.cache

# Why: recent Homebrew prompts "Do you want to proceed?" on brew install when
# it would also upgrade outdated deps. The build has no TTY, so brew hangs
# forever. NONINTERACTIVE=1 only covers the brew installer script, not package
# installs — HOMEBREW_NO_ASK is the one that silences the install prompt.
# NO_AUTO_UPDATE skips the implicit `brew update` before each install: faster
# builds and the bottle versions stay fixed to whatever the formula API serves.
ENV HOMEBREW_NO_ASK=1 \
    HOMEBREW_NO_AUTO_UPDATE=1

# Cache-prime latest nushell too — ensure-nu.sh (called by run-install.sh)
# installs it when `nu` is absent, checks that it can load bootstrap.nu, and
# falls back to the pinned version if pre-1.0 syntax has drifted in latest.
RUN brew install nushell

# Stage cozy repo bits for bootstrap.nu:
#  - vendor/  → /tmp/vendor/        (bootstrap fans it out under ~/repos/)
#  - cozy-module/ + docker-files/ → ~/repos/cozy/{cozy-module,docker-files}/
#    so bootstrap.nu can resolve cozy_root from `path self`.
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent cozy-module/ /home/agent/repos/cozy/cozy-module/
COPY --chown=agent:agent docker-files/ /home/agent/repos/cozy/docker-files/

# The whole boot tail lives in one shared script — ensure brew (no-op here,
# cached above) → ensure-nu.sh compatibility gate → nu bootstrap.nu. Same script the
# sbx kit and a host checkout run, so the paths can't drift in ordering.
RUN /home/agent/repos/cozy/cozy-module/install/run-install.sh

COPY --chown=agent:agent docker-files/workspace-README.md /home/agent/workspace/README.md

# ---- final root layer: login PATH + revoke the build-time privilege ----
# Kept last so tweaking either doesn't invalidate the cached brew layers.
#
# login env: a login shell (`bash -l`, and the non-interactive `bash -lc` that
# `cozy verify` reads env through) runs /etc/profile, not /etc/bash.bashrc. So
# two things must be re-supplied there. (1) PATH: /etc/profile rebuilds it from
# scratch and drops the ENV PATH additions above, so `nu` and every brew tool
# vanish — brew shellenv puts linuxbrew's bin/sbin back and we prepend the
# per-user bins like the ENV PATH does. (2) The cozy env block (XDG_*,
# HELIX_RUNTIME, LANG) lives in /etc/sandbox-persistent.sh, which
# /etc/bash.bashrc sources for interactive shells but a login shell never
# sees — so source it here too, or verify's env checks false-fail on a base
# image that bakes no ENV. profile.d is sourced by /etc/profile unconditionally, so both
# interactive and non-interactive login shells get it. The sbx base wired all
# this for us; on plain Debian the profile.d drop-in does. Non-login shells
# still get PATH from the ENV directive, and the env block from /etc/bash.bashrc
# (interactive) or BASH_ENV (non-interactive — see the ENV below).
#
# revoke sudo: the agent kept passwordless sudo through every RUN above (brew
# chown, apt, tree-sitter compile). Deleting the drop-in leaves the running
# container with an agent that cannot escalate — the whole point of moving off
# the permanent-sudo template. sudo the binary stays, but with no rule it's inert.
#
# chown the env file: revoking sudo is not enough while /etc/sandbox-persistent.sh
# stays agent-owned. BASH_ENV (below) and the profile.d line here are image-wide,
# not per-user, so `docker exec -u root … bash` sources that file as uid 0 — the
# agent could write a payload and wait for the operator's next rootful exec.
# Nothing writes it after bootstrap: Step 0 is the only writer and it cannot
# re-run here anyway, since it needs the sudo this layer just removed.
USER root
RUN printf '%s\n' \
        'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' \
        'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' \
        '[ -f /etc/sandbox-persistent.sh ] && . /etc/sandbox-persistent.sh' \
        > /etc/profile.d/cozy.sh \
    && chown root:root /etc/sandbox-persistent.sh \
    && rm -f /etc/sudoers.d/agent-build
USER agent

# The third shell flavour: non-interactive, non-login bash — what Claude Code's
# Bash tool and every `docker exec ... bash -c` actually run. It reads neither
# /etc/profile nor /etc/bash.bashrc, so BASH_ENV is bash's only hook for it, and
# it's how the sbx base image gets "sourced before every bash invocation" — this
# makes the Debian image match.
#
# What it carries here is machine env only (XDG_*, HELIX_RUNTIME, LANG), and in
# *this* image every one of those is already an ENV directive above — so the line
# is redundant for the image and kept for the case that isn't: run-install.sh
# bootstrapped into a foreign container, where the block is the only source and a
# `bash -c nu` would otherwise start with no XDG_DATA_HOME. It carries no identity:
# the agent's GIT_AUTHOR_*/JJ_CONFIG live in Claude Code's own settings (bootstrap
# Step 9), because a shell hook is the wrong scope for them — it reached the human's
# shells, which should stay the human's, and missed the MCP `nu`, which is no
# shell's child.
#
# BASH_ENV applies to every non-interactive bash, so `bash -lc` sources the file
# twice — once here, once via profile.d. The exports are idempotent, and the
# profile.d line is still needed for the PATH that /etc/profile rebuilds away.
ENV BASH_ENV=/etc/sandbox-persistent.sh
