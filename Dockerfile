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
# Used by `toolkit push-to-machine --commit-changes` below before dotfiles
# deploys a real ~/.gitconfig. /etc/gitconfig is fine here because at build
# time `git` is /usr/bin/git (apt) which reads /etc/gitconfig.
# Runtime settings (excludes, safe.directory, gc, fsync) live in the XDG
# config below — see that block for why /etc/gitconfig is unreliable at runtime.
RUN git config --system user.name "Agent" \
    && git config --system user.email "agent@sandbox"

RUN printf 'Acquire::http::Proxy "http://host.docker.internal:3128/";\nAcquire::https::Proxy "http://host.docker.internal:3128/";\n' \
        > /etc/apt/apt.conf.d/90proxy

USER agent

RUN NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

ENV PATH="/home/agent/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

RUN brew install nushell fzf lazygit helix zellij broot git-delta visidata bat topiary fd \
    && brew cleanup --prune=all

RUN brew install jj git-lfs \
    && brew cleanup --prune=all

ENV HELIX_RUNTIME=/home/linuxbrew/.linuxbrew/opt/helix/libexec/runtime \
    HOME=/home/agent \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    TERM_PROGRAM=WezTerm \
    LANG=C.UTF-8

COPY --chown=agent:agent docker-files/.visidatarc /home/agent/.visidatarc
COPY --chown=agent:agent docker-files/nushell-autoload/ /tmp/nushell-autoload/
COPY --chown=agent:agent vendor/ /tmp/vendor/
COPY --chown=agent:agent sandbox-toolkit/ /tmp/sandbox-toolkit/
COPY --chown=agent:agent docker-files/global-claude.md /tmp/global-claude.md

RUN mkdir ~/repos

ENV XDG_CONFIG_HOME=$HOME/.config \
    XDG_DATA_HOME=$HOME/.local/share \
    XDG_CACHE_HOME=$HOME/.cache

RUN broot --write-default-conf $XDG_CONFIG_HOME/broot \
    && broot --set-install-state installed

# Per-user git config at the XDG path (~/.config/git/).
# Why XDG, not /etc/gitconfig: brew git (often added later, either by users or
# by future Dockerfile changes) has sysconfdir /home/linuxbrew/.linuxbrew/etc
# and ignores /etc/gitconfig entirely — so any --system setting silently
# becomes a no-op the moment brew git lands on PATH.
# Why XDG, not --global (~/.gitconfig): docker sandbox create overwrites
# ~/.gitconfig on every start. ~/.config/git/ is not touched.
# XDG is read by every git binary regardless of sysconfdir.
#
# - ignore: git's default global ignore (no core.excludesFile binding needed)
# - safe.directory '*': trust host-owned mounts (uid mismatch via VirtioFS)
# - gc.auto=0, core.fsync*: harden against VirtioFS torn-pack corruption.
#   VirtioFS doesn't atomically flush pack writes across the VM/host boundary,
#   so `git gc` / auto-repack can leave packs visible to the host as
#   "unknown object type 0" corruption. Disable auto-gc and force fsync so
#   writes don't return until the VM commits to disk.
RUN mkdir -p ~/.config/git \
    && printf '.DS_Store\nThumbs.db\ndesktop.ini\n' > ~/.config/git/ignore \
    && printf '[safe]\n\tdirectory = *\n[gc]\n\tauto = 0\n[core]\n\tfsync = all\n\tfsyncMethod = fsync\n' > ~/.config/git/config

ARG MODULES_SOURCE=vendor
RUN if [ "$MODULES_SOURCE" = "clone" ]; then \
      git clone https://github.com/nushell-prophet/cozy.git ~/repos/cozy \
      && git clone https://github.com/nushell-prophet/nu-goodies.git ~/repos/nu-goodies \
      && git clone https://github.com/nushell-prophet/nu-kv.git ~/repos/nu-kv \
      && git clone https://github.com/nushell-prophet/dotnu.git ~/repos/dotnu \
      && git clone https://github.com/nushell-prophet/numd.git ~/repos/numd \
      && git clone https://github.com/nushell-prophet/claude-nu.git ~/repos/claude-nu \
      && git clone https://github.com/nushell-prophet/nu-cmd-stack.git ~/repos/nu-cmd-stack \
      && git clone https://github.com/nushell-prophet/my-dotfiles.git ~/repos/dotfiles \
      && git clone https://github.com/vyadh/nutest.git ~/repos/nutest \
      && git clone https://github.com/blindFS/topiary-nushell.git ~/repos/topiary-nushell \
      && git clone https://github.com/nushell-prophet/nushell-skills.git ~/repos/nushell-skills \
      && git clone https://github.com/maxim-uvarov/my-claude-skills.git ~/repos/my-claude-skills \
      && git clone https://github.com/nushell-prophet/nu-multiproof.git ~/repos/nu-multiproof; \
    else \
      cp -r /tmp/vendor/* ~/repos/; \
    fi \
    && mkdir -p ~/workspace ~/.config/nushell/autoload \
    && if [ "$MODULES_SOURCE" != "clone" ]; then mkdir -p ~/repos/cozy && cp -r /tmp/sandbox-toolkit ~/repos/cozy/sandbox-toolkit; fi \
    && cp /tmp/nushell-autoload/*.nu ~/.config/nushell/autoload/ \
    && rm -rf /tmp/vendor/ /tmp/nushell-autoload/ /tmp/sandbox-toolkit/

RUN cd ~/repos/dotfiles \
    && nu -c 'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker --commit-changes' \
    && printf '\n' >> ~/.claude/CLAUDE.md && cat /tmp/global-claude.md >> ~/.claude/CLAUDE.md \
    && rm /tmp/global-claude.md

# Deploy Claude skills from dedicated skill repos into ~/.claude/skills/
# my-claude-skills: personal skills (elegance-first, intent-audit, jj-ai-guide, keep-a-changelog, spec-extract)
# nushell-skills: public nushell skills (nushell-completions, nushell-style) — copied second so canonical versions win
RUN mkdir -p ~/.claude/skills/ \
    && cp -r ~/repos/my-claude-skills/plugins/my-skills/skills/* ~/.claude/skills/ \
    && for plugin_dir in ~/repos/nushell-skills/plugins/*/skills/*; do \
         cp -r "$plugin_dir" ~/.claude/skills/; \
       done

# Set up topiary nushell grammar and config (topiary binary already installed via brew above)
# Pre-place vendored topiary-nushell so the install script skips the clone.
# In clone mode the dir is absent and topiary install clones from GitHub as before.
RUN if [ -d ~/repos/topiary-nushell ]; then mkdir -p ~/git && ln -s ~/repos/topiary-nushell ~/git/topiary-nushell; fi
RUN nu -c 'use ~/repos/cozy/sandbox-toolkit/install/topiary.nu; topiary install'

ARG INSTALL_CLAUDE=true
RUN if [ "$INSTALL_CLAUDE" = "true" ]; then \
      curl -fsSL https://claude.ai/install.sh | bash; \
    fi

# Register nushell MCP server in Claude Code user config (~/.claude.json).
# autoload/mcp-server.nu self-heals if sandbox create overwrites the file.
RUN if [ "$INSTALL_CLAUDE" = "true" ]; then \
      claude mcp add --scope user --transport stdio nushell -- \
        /home/linuxbrew/.linuxbrew/bin/nu --mcp; \
    fi

RUN echo 'export GIT_AUTHOR_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_AUTHOR_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_NAME="Claude"' >> /etc/sandbox-persistent.sh \
    && echo 'export GIT_COMMITTER_EMAIL="claude@anthropic.com"' >> /etc/sandbox-persistent.sh \
    && echo 'export JJ_CONFIG="$HOME/.config/jj/jj-config-claude-ai.toml"' >> /etc/sandbox-persistent.sh

COPY --chown=agent:agent README.md /home/agent/workspace/README.md
