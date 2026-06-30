FROM docker/sandbox-templates:shell

USER agent

# Install Homebrew. bootstrap.nu IS a nushell script, so brew (which provides
# nu) must exist before we can hand off. Host install assumes brew is already
# present.
RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/agent/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

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
ENV HOMEBREW_NO_ASK=1

# Pre-install latest nushell as a cached layer. ensure-nu.sh below smoke-
# tests it against bootstrap.nu and falls back to the pinned version if
# pre-1.0 syntax has drifted in latest.
RUN brew install nushell

# Stage cozy repo bits for bootstrap.nu:
#  - vendor/  → /tmp/vendor/        (bootstrap fans it out under ~/repos/)
#  - cozy-module/ + docker-files/ → ~/repos/cozy/{cozy-module,docker-files}/
#    so bootstrap.nu can resolve cozy_root from `path self`.
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent cozy-module/ /home/agent/repos/cozy/cozy-module/
COPY --chown=agent:agent docker-files/ /home/agent/repos/cozy/docker-files/

# Smoke-test latest nu against bootstrap.nu; download pinned (.nushell-version)
# into ~/.local/bin/nu if latest can't parse it — guards against pre-1.0 drift.
RUN /home/agent/repos/cozy/cozy-module/install/ensure-nu.sh

# All install logic lives in bootstrap.nu — same code path the host install uses.
# Docker mode uses sudo only where unavoidable (apt itself, /etc/apt proxy
# file); pbcopy goes to ~/.local/bin and git identity into XDG ~/.config/git/.
RUN nu /home/agent/repos/cozy/cozy-module/install/bootstrap.nu

COPY --chown=agent:agent docker-files/workspace-README.md /home/agent/workspace/README.md
