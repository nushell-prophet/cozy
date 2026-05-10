FROM docker/sandbox-templates:shell

USER root

RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        procps \
        file \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Why: Docker sandbox has no system clipboard. This shim uses OSC 52 escape
# sequences to push copied text to the host terminal's clipboard. Consumed by
# helix, lazygit, broot, nushell keybindings, and nu-goodies commands.
COPY --chmod=755 docker-files/pbcopy /usr/local/bin/pbcopy

# Build-time git identity fallback (/etc/gitconfig).
# Used by `toolkit push-to-machine --commit-changes` (called from bootstrap.nu)
# before dotfiles deploys a real ~/.gitconfig. /etc/gitconfig is fine here
# because at build time `git` is /usr/bin/git (apt) which reads /etc/gitconfig.
# Runtime XDG settings (excludes, safe.directory, gc, fsync) are written by
# bootstrap.nu — see that file for why /etc/gitconfig is unreliable at runtime.
RUN git config --system user.name "Agent" \
    && git config --system user.email "agent@sandbox"

RUN printf 'Acquire::http::Proxy "http://host.docker.internal:3128/";\nAcquire::https::Proxy "http://host.docker.internal:3128/";\n' \
        > /etc/apt/apt.conf.d/90proxy

USER agent

# Install Homebrew. Host install assumes brew is already present; in Docker
# we provide it ourselves so bootstrap.nu can `brew install` everything.
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

# Install nushell up-front: bootstrap.nu IS a nushell script, so nu must
# exist before we can invoke it. Same prerequisite that bootstrap.sh handles
# on the host. Bootstrap re-runs `brew install nushell ...` itself — brew
# is idempotent, so the redundancy is cheap and step 1 stays portable.
RUN brew install nushell

# Stage cozy repo bits for bootstrap.nu:
#  - vendor/  → /tmp/vendor/        (bootstrap fans it out under ~/repos/)
#  - sandbox-toolkit/ + docker-files/ → ~/repos/cozy/{sandbox-toolkit,docker-files}/
#    so bootstrap.nu can resolve cozy_root from `path self`.
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent sandbox-toolkit/ /home/agent/repos/cozy/sandbox-toolkit/
COPY --chown=agent:agent docker-files/ /home/agent/repos/cozy/docker-files/

# All install logic lives in bootstrap.nu — same code path the host install will use.
RUN nu -c 'use ~/repos/cozy/sandbox-toolkit/install/bootstrap.nu; bootstrap --in-docker'

RUN echo 'export GIT_AUTHOR_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_AUTHOR_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"' >> /etc/sandbox-persistent.sh

COPY --chown=agent:agent README.md /home/agent/workspace/README.md
