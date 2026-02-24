FROM docker/sandbox-templates:claude-code

USER root

RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        procps \
        file \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 pbcopy /usr/local/bin/pbcopy

USER agent

RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

RUN brew install nushell fzf lazygit helix zellij broot carapace git-delta visidata \
    && brew cleanup --prune=all

RUN brew install jj \
    && brew cleanup --prune=all

ENV HELIX_RUNTIME=/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime \
    HOME=/home/agent \
    TERM_PROGRAM=WezTerm

COPY --chown=agent:agent .visidatarc /home/agent/.visidatarc
COPY --chown=agent:agent nushell-autoload/ /tmp/nushell-autoload/
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent toolkit.nu /home/agent/toolkit.nu

RUN mkdir ~/git

ENV XDG_CONFIG_HOME=$HOME/.config \
    XDG_DATA_HOME=$HOME/.local/share \
    XDG_CACHE_HOME=$HOME/.cache

RUN broot --write-default-conf $XDG_CONFIG_HOME/broot \
    && broot --set-install-state installed

ARG DOTFILES_CACHE_BUST
RUN git clone https://github.com/nushell-prophet/my-dotfiles.git ~/git/dotfiles \
    && cd ~/git/dotfiles \
    && nu -c 'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker'

ARG MODULES_SOURCE=vendor
RUN if [ "$MODULES_SOURCE" = "clone" ]; then \
      git clone https://github.com/nushell-prophet/nu-goodies.git ~/git/nu-goodies \
      && git clone https://github.com/nushell-prophet/nu-kv.git ~/git/nushell-kv \
      && git clone https://github.com/nushell-prophet/dotnu.git ~/git/dotnu \
      && git clone https://github.com/nushell-prophet/numd.git ~/git/numd \
      && git clone https://github.com/nushell-prophet/claude-nu.git ~/git/claude-nu \
      && git clone https://github.com/nushell-prophet/nu-cmd-stack.git ~/git/nu-cmd-stack; \
    else \
      cp -r /tmp/vendor/* ~/git/; \
    fi \
    && cp /tmp/nushell-autoload/*.nu ~/.config/nushell/autoload/ \
    && rm -rf /tmp/vendor/ /tmp/nushell-autoload/
    # MCP server config: autoload/mcp-server.nu patches settings.json on first interactive nu
    # (sandbox create overwrites ~/.claude/settings.json with defaults)

RUN echo 'export GIT_AUTHOR_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_AUTHOR_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \

COPY --chown=agent:agent global-claude.md /home/agent/.claude/CLAUDE.md
