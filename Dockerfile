FROM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# Base tools.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        python3-venv python3-pip \
        ripgrep ffmpeg gh && \
    rm -rf /var/lib/apt/lists/*

# ── Node.js 22 (web dashboard UI build) ─────────────────────────────────
# /opt/hermes/web requires node >= 22.22.0 and npm < 11.10.0 or >= 11.17.0;
# Debian's nodejs (v20) fails the engine check (EBADENGINE). Binary tarball
# is deterministic and avoids the NodeSource apt repo.
RUN curl -fsSL https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-x64.tar.xz | \
        tar -xJ -C /usr/local --strip-components=1 && \
    node -v && npm -v

# ── Hermes Agent: deterministic clone-and-install ───────────────────────
# Replaces the install.sh approach: the installer exits non-zero on
# Railway's builder (optional Node/browser deps), and Docker layer caching
# made the resulting venv-less image permanent (builds served the broken
# cached layer forever). A direct clone + venv install either works or
# fails loudly — no silent partial installs.
#
# HERMES_REF can be pinned to a tag/commit for full reproducibility.
ARG HERMES_REF=main
RUN git clone --depth 1 --branch "$HERMES_REF" \
    https://github.com/NousResearch/hermes-agent.git /opt/hermes

RUN python3 -m venv /opt/hermes/venv && \
    /opt/hermes/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/hermes/venv/bin/pip install --no-cache-dir -e '/opt/hermes[messaging]'

# ── Pin python-telegram-bot to 22.6 ─────────────────────────────────────
# Upstream bug NousResearch/hermes-agent#85272: the messaging extra pins
# python-telegram-bot 22.8, which routes the Telegram adapter through the
# deferred SDK import path where TypeHandler is never rebound from
# typing.Any → "Any cannot be instantiated" → gateway boots with no
# connected platforms. This install runs AFTER the extra, so 22.6 wins.
# TODO: unpin after upstream PR #85421 merges and HERMES_REF is bumped.
RUN /opt/hermes/venv/bin/pip install --no-cache-dir \
        'python-telegram-bot[webhooks]==22.6' && \
    /opt/hermes/venv/bin/pip show python-telegram-bot | head -2

RUN ln -sf /opt/hermes/venv/bin/hermes /usr/local/bin/hermes && \
    /usr/local/bin/hermes --version

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
