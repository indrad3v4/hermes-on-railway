FROM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# Base tools.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        python3-venv python3-pip \
        ripgrep ffmpeg gh build-essential && \
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

# ── SQLite 3.53.4 (WAL-reset corruption fix) ──────────────────────────────
# Debian trixie ships libsqlite3-0 3.46.1, vulnerable to the WAL-reset bug
# (https://sqlite.org/wal.html#walresetbug); Hermes warns at startup for
# state.db / delivery_ledger / cron executions.db. Compile the amalgamation
# and install over the system lib so python's sqlite3 module links >= 3.51.3.
# SONAME stays libsqlite3.so.0 (ABI-compatible); build-essential provides gcc.
RUN curl -fsSL https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip -o /tmp/sq.zip && \
    python3 -c "import zipfile; zipfile.ZipFile('/tmp/sq.zip').extractall('/tmp')" && \
    cd /tmp/sqlite-amalgamation-3530400 && \
    gcc -O2 -fPIC -shared -o libsqlite3.so.0 sqlite3.c -ldl -lpthread -lm && \
    cp libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/ && \
    ldconfig && \
    rm -rf /tmp/sq.zip /tmp/sqlite-amalgamation-* && \
    /opt/hermes/venv/bin/python -c "import sqlite3; print('SQLite:', sqlite3.sqlite_version)"

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
