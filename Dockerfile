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
    && rm -rf helix.tar.xz helix-*

ENV HELIX_RUNTIME=/usr/local/lib/helix-runtime

USER agent

RUN mkdir ~/git \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/home/agent/.cargo/bin:${PATH}"
