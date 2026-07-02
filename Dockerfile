# This Dockerfile is legacy and unmaintained. It was required by `docker
# sandbox`, which is now deprecated, so I've replaced it with `sbx`. `sbx` can
# probably consume Dockerfiles too, but for my workflow -- running this
# environment against a fixed set of folders -- a one-time build via sbx-kit/
# is simpler.

FROM docker/sandbox-templates:shell

USER agent

# Cache-prime Homebrew as its own layer. run-install.sh (the uncached tail
# below) auto-installs brew when it's missing, so this layer is optional for
# correctness — it exists so editing cozy-module/ doesn't re-download brew.
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
# NO_AUTO_UPDATE skips the implicit `brew update` before each install: faster
# builds and the bottle versions stay fixed to whatever the formula API serves.
ENV HOMEBREW_NO_ASK=1 \
    HOMEBREW_NO_AUTO_UPDATE=1

# Cache-prime latest nushell too — ensure-nu.sh (called by run-install.sh)
# installs it when `nu` is absent, smoke-tests it against bootstrap.nu, and
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
# cached above) → ensure-nu.sh smoke test → nu bootstrap.nu. Same script the
# sbx kit and a host checkout run, so the paths can't drift in ordering.
RUN /home/agent/repos/cozy/cozy-module/install/run-install.sh

COPY --chown=agent:agent docker-files/workspace-README.md /home/agent/workspace/README.md
