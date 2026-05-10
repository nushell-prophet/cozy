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

# bootstrap.nu IS a nushell script, so nu must exist before we can invoke it.
# Bootstrap re-runs `brew install nushell ...` itself — brew is idempotent,
# so the redundancy is cheap and step 1 stays portable.
RUN brew install nushell

# Stage cozy repo bits for bootstrap.nu:
#  - vendor/  → /tmp/vendor/        (bootstrap fans it out under ~/repos/)
#  - sandbox-toolkit/ + docker-files/ → ~/repos/cozy/{sandbox-toolkit,docker-files}/
#    so bootstrap.nu can resolve cozy_root from `path self`.
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent sandbox-toolkit/ /home/agent/repos/cozy/sandbox-toolkit/
COPY --chown=agent:agent docker-files/ /home/agent/repos/cozy/docker-files/

# All install logic lives in bootstrap.nu — same code path the host install uses.
# In docker mode, bootstrap.nu's setup-docker-system uses sudo to absorb every
# former USER root step (apt deps, pbcopy install, /etc/gitconfig, apt proxy,
# /etc/sandbox-persistent.sh) inline.
RUN nu -c 'use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu; bootstrap --in-docker'

COPY --chown=agent:agent README.md /home/agent/workspace/README.md
