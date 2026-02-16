FROM docker/sandbox-templates:claude-code

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        xz-utils \
    && curl -fsSL https://apt.fury.io/nushell/gpg.key \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/fury-nushell.gpg \
    && echo "deb https://apt.fury.io/nushell/ /" \
        > /etc/apt/sources.list.d/fury.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nushell \
    && rm -rf /var/lib/apt/lists/* \
    # lazygit (with sha256 checksum from checksums.txt)
    && LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz" \
    && curl -sL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/checksums.txt" \
        | grep "lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz" \
        | sed "s|lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz|lazygit.tar.gz|" \
        | sha256sum -c - \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin/ \
    && rm lazygit.tar.gz lazygit \
    # helix
    && HELIX_VERSION=$(curl -s "https://api.github.com/repos/helix-editor/helix/releases/latest" | grep -Po '"tag_name": *"\K[^"]*') \
    && curl -Lo helix.tar.xz "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-aarch64-linux.tar.xz" \
    && tar xf helix.tar.xz \
    && mv helix-*/hx /usr/local/bin/ \
    && mv helix-*/runtime /usr/local/lib/helix-runtime \
    && rm -rf helix.tar.xz helix-* \
    # zellij
    && curl -Lo zellij.tar.gz "https://github.com/zellij-org/zellij/releases/latest/download/zellij-aarch64-unknown-linux-musl.tar.gz" \
    && tar xf zellij.tar.gz zellij \
    && install zellij /usr/local/bin/ \
    && rm zellij.tar.gz zellij \
    # broot
    && curl -Lo /usr/local/bin/broot "https://dystroy.org/broot/download/aarch64-linux/broot" \
    && chmod +x /usr/local/bin/broot \
    # carapace
    && CARAPACE_VERSION=$(curl -s "https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*') \
    && curl -Lo carapace.tar.gz "https://github.com/carapace-sh/carapace-bin/releases/download/v${CARAPACE_VERSION}/carapace-bin_linux_arm64.tar.gz" \
    && tar xf carapace.tar.gz -C /usr/local/bin carapace \
    && rm carapace.tar.gz

ENV HELIX_RUNTIME=/usr/local/lib/helix-runtime

USER agent

RUN mkdir ~/git \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && mkdir -p ~/.cargo \
    && printf '[net]\nretry = 5\ngit-fetch-with-cli = true\n\n[http]\ntimeout = 120\n\n[registries.crates-io]\nprotocol = "sparse"\n' > ~/.cargo/config.toml

ENV PATH="/home/agent/.cargo/bin:${PATH}" \
    XDG_CONFIG_HOME=/home/agent/.config \
    XDG_DATA_HOME=/home/agent/.local/share \
    XDG_CACHE_HOME=/home/agent/.cache

RUN git clone https://github.com/nushell-prophet/my-dotfiles.git ~/git/dotfiles \
    && cd ~/git/dotfiles \
    && nu -c 'use toolkit.nu; toolkit push-to-machine --force --create-dirs --docker'
