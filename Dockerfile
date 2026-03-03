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

RUN brew install nushell fzf lazygit helix zellij broot carapace git-delta visidata bat \
    && brew cleanup --prune=all

RUN brew install jj \
    && brew cleanup --prune=all

ENV HELIX_RUNTIME=/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime \
    HOME=/home/agent \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    TERM_PROGRAM=WezTerm

COPY --chown=agent:agent .visidatarc /home/agent/.visidatarc
COPY --chown=agent:agent nushell-autoload/ /tmp/nushell-autoload/
COPY --chown=agent:agent vendor/ /tmp/vendor/

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
      git clone https://github.com/nushell-prophet/ai-sandbox-toolkit.git ~/git/ai-sandbox-toolkit \
      && git clone https://github.com/nushell-prophet/nu-goodies.git ~/git/nu-goodies \
      && git clone https://github.com/nushell-prophet/nu-kv.git ~/git/nushell-kv \
      && git clone https://github.com/nushell-prophet/dotnu.git ~/git/dotnu \
      && git clone https://github.com/nushell-prophet/numd.git ~/git/numd \
      && git clone https://github.com/nushell-prophet/claude-nu.git ~/git/claude-nu \
      && git clone https://github.com/nushell-prophet/nu-cmd-stack.git ~/git/nu-cmd-stack \
      && git clone https://github.com/vyadh/nutest.git ~/git/nutest; \
    else \
      cp -r /tmp/vendor/* ~/git/; \
    fi \
    && mkdir -p ~/workspace \
    && ln -s ~/git/ai-sandbox-toolkit ~/workspace/ai-sandbox-toolkit \
    && cp /tmp/nushell-autoload/*.nu ~/.config/nushell/autoload/ \
    && rm -rf /tmp/vendor/ /tmp/nushell-autoload/

# Register nushell MCP server in Claude Code user config (~/.claude.json).
# autoload/mcp-server.nu self-heals if sandbox create overwrites the file.
RUN claude mcp add --scope user --transport stdio nushell -- \
        /home/linuxbrew/.linuxbrew/bin/nu --mcp

RUN echo 'export GIT_AUTHOR_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_AUTHOR_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"' >> /etc/sandbox-persistent.sh

COPY --chown=agent:agent global-claude.md /home/agent/.claude/CLAUDE.md
COPY --chown=agent:agent README.md /home/agent/workspace/README.md
