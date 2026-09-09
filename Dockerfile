FROM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# Base tools + headless Chromium.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        ripgrep ffmpeg \
        chromium chromium-driver && \
    rm -rf /var/lib/apt/lists/*

# ── uv + uv-managed Python ──────────────────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# ── Hermes Agent ────────────────────────────────────────────────────────
# Pin the upstream revision in Railway variables/build args. Default is the
# known-good revision from 2026-09-09 used while debugging thread pressure.
ARG HERMES_REF=9e0dc4319ae2d59c60f5226b5c0af58d17755bfa
RUN git clone --depth 1 --branch "$HERMES_REF" \
    https://github.com/NousResearch/hermes-agent.git /opt/hermes

RUN uv python install 3.12 && \
    uv venv --python 3.12 /opt/hermes/venv && \
    uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        -e '/opt/hermes[messaging]'

RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        pymupdf python-docx faster-whisper librosa browser-use

ENV UV_TOOL_BIN_DIR=/root/.hermes/bin
RUN UV_TOOL_BIN_DIR=/root/.hermes/bin uv tool install --force browser-use || true

RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        'python-telegram-bot[webhooks]==22.6' && \
    /opt/hermes/venv/bin/pip show python-telegram-bot | head -2

RUN /opt/hermes/venv/bin/python -c \
    "import sqlite3; v=tuple(map(int, sqlite3.sqlite_version.split('.'))); \
     assert v >= (3, 51, 3), f'Vulnerable SQLite {sqlite3.sqlite_version} — WAL-reset bug'; \
     print('SQLite', sqlite3.sqlite_version, 'OK (WAL-reset patched)')"

RUN /opt/hermes/venv/bin/python -c \
    "import importlib.util; \
     assert importlib.util.find_spec('cometapi') is None, \
     'cometapi SDK found in venv — remove it (CometAPI must not be active)'; \
     print('cometapi: not present in venv (OK)')"

RUN ln -sf /opt/hermes/venv/bin/hermes /usr/local/bin/hermes && \
    /usr/local/bin/hermes --version

COPY patches/ /opt/patches/
RUN git -C /opt/hermes apply /opt/patches/video-note.patch && \
    echo "Applied: video-note.patch" && \
    git -C /opt/hermes apply /opt/patches/stt-local-files-only.patch && \
    echo "Applied: stt-local-files-only.patch" && \
    git -C /opt/hermes apply /opt/patches/context-read-bounded.patch && \
    echo "Applied: context-read-bounded.patch"

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
