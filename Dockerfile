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

COPY --chmod=755 docker-files/pbcopy /usr/local/bin/pbcopy

RUN printf 'Acquire::http::Proxy "http://host.docker.internal:3128/";\nAcquire::https::Proxy "http://host.docker.internal:3128/";\n' \
        > /etc/apt/apt.conf.d/90proxy

USER agent

RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/agent/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

RUN brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary \
    && brew cleanup --prune=all

RUN brew install jj git-lfs \
    && brew cleanup --prune=all

ENV HELIX_RUNTIME=/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime \
    HOME=/home/agent \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    TERM_PROGRAM=WezTerm

COPY --chown=agent:agent docker-files/.visidatarc /home/agent/.visidatarc
COPY --chown=agent:agent nushell-autoload/ /tmp/nushell-autoload/
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent docker-files/global-claude.md /tmp/global-claude.md

RUN mkdir ~/repos

ENV XDG_CONFIG_HOME=$HOME/.config \
    XDG_DATA_HOME=$HOME/.local/share \
    XDG_CACHE_HOME=$HOME/.cache

RUN broot --write-default-conf $XDG_CONFIG_HOME/broot \
    && broot --set-install-state installed

# Workspace is mounted from the host, so it's owned by a different uid.
# Git refuses to operate on repos with mismatched ownership (CVE-2022-24765).
# Wildcard is safe here — the sandbox is single-user and isolated.
RUN git config --global user.name "Agent" && git config --global user.email "agent@sandbox" \
    && git config --global --add safe.directory '*' \
    && git config --global core.excludesFile ~/.gitignore \
    && printf '.DS_Store\nThumbs.db\ndesktop.ini\n' > ~/.gitignore

ARG MODULES_SOURCE=vendor
RUN if [ "$MODULES_SOURCE" = "clone" ]; then \
      git clone https://github.com/nushell-prophet/cozy-docker-sandbox-toolkit.git ~/repos/cozy-docker-sandbox-toolkit \
      && git clone https://github.com/nushell-prophet/nu-goodies.git ~/repos/nu-goodies \
      && git clone https://github.com/nushell-prophet/nu-kv.git ~/repos/nu-kv \
      && git clone https://github.com/nushell-prophet/dotnu.git ~/repos/dotnu \
      && git clone https://github.com/nushell-prophet/numd.git ~/repos/numd \
      && git clone https://github.com/nushell-prophet/claude-nu.git ~/repos/claude-nu \
      && git clone https://github.com/nushell-prophet/nu-cmd-stack.git ~/repos/nu-cmd-stack \
      && git clone https://github.com/nushell-prophet/my-dotfiles.git ~/repos/dotfiles \
      && git clone https://github.com/vyadh/nutest.git ~/repos/nutest; \
    else \
      cp -r /tmp/vendor/* ~/repos/; \
    fi \
    && mkdir -p ~/workspace ~/.config/nushell/autoload \
    && ln -s ~/repos/cozy-docker-sandbox-toolkit ~/workspace/cozy-docker-sandbox-toolkit \
    && cp /tmp/nushell-autoload/*.nu ~/.config/nushell/autoload/ \
    && rm -rf /tmp/vendor/ /tmp/nushell-autoload/

RUN cd ~/repos/dotfiles \
    && nu -c 'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker --commit-changes' \
    && printf '\n' >> ~/.claude/CLAUDE.md && cat /tmp/global-claude.md >> ~/.claude/CLAUDE.md \
    && rm /tmp/global-claude.md

# Set up topiary nushell grammar and config (topiary binary already installed via brew above)
# Pre-place vendored topiary-nushell so the install script skips the clone.
# In clone mode the dir is absent and topiary install clones from GitHub as before.
RUN if [ -d ~/repos/topiary-nushell ]; then mkdir -p ~/git && ln -s ~/repos/topiary-nushell ~/git/topiary-nushell; fi
RUN nu -c 'use ~/repos/cozy-docker-sandbox-toolkit/install/topiary.nu; topiary install'

RUN curl -fsSL https://claude.ai/install.sh | bash

# Register nushell MCP server in Claude Code user config (~/.claude.json).
# autoload/mcp-server.nu self-heals if sandbox create overwrites the file.
RUN claude mcp add --scope user --transport stdio nushell -- \
        /home/linuxbrew/.linuxbrew/bin/nu --mcp

RUN echo 'export GIT_AUTHOR_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_AUTHOR_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"' >> /etc/sandbox-persistent.sh

COPY --chown=agent:agent README.md /home/agent/workspace/README.md
