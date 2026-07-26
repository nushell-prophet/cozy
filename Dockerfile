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
    HOME=/home/agent \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    TERM_PROGRAM=WezTerm \
    LANG=C.UTF-8

ENV XDG_CONFIG_HOME=$HOME/.config \
    XDG_DATA_HOME=$HOME/.local/share \
    XDG_CACHE_HOME=$HOME/.cache

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
# per-user bins like the ENV PATH does. (2) The cozy env block (GIT_AUTHOR_*,
# GIT_COMMITTER_*, JJ_CONFIG, ...) lives only in /etc/sandbox-persistent.sh,
# which /etc/bash.bashrc sources for interactive shells but a login shell never
# sees — so source it here too, or verify's five git-identity/jj env checks
# false-fail. profile.d is sourced by /etc/profile unconditionally, so both
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

# The uncovered shell flavour: non-interactive, non-login bash — what Claude
# Code's Bash tool and every `docker exec ... bash -c` actually run. It reads
# neither /etc/profile nor /etc/bash.bashrc, so without this the cozy env block was
# invisible exactly where the agent works: commits landed as the XDG-config
# identity `Agent <agent@sandbox>` instead of Claude. BASH_ENV is bash's hook for
# that case, and it's how the sbx base image gets "sourced before every bash
# invocation" — this makes the Debian image match. Set after the build RUNs on
# purpose: build-time bash must not inherit GIT_AUTHOR_*, or bootstrap's own
# commits would be attributed to Claude.
#
# BASH_ENV applies to every non-interactive bash, so `bash -lc` now sources the
# file twice — once here, once via profile.d. The exports are idempotent, and the
# profile.d line is still needed for the PATH that /etc/profile rebuilds away.
ENV BASH_ENV=/etc/sandbox-persistent.sh
