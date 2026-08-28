FROM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# Base tools.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        ripgrep ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# ── uv + uv-managed Python ──────────────────────────────────────────────
# Debian trixie's system Python 3.13.5 links libsqlite3 3.46.1, which is
# vulnerable to the WAL-reset corruption bug (sqlite.org/wal.html#walresetbug)
# — the likely root cause of the 2026-08-15 state.db corruption incident.
# uv-managed CPython (python-build-standalone) ships a patched SQLite
# (>= 3.51.3) statically linked. This mirrors what the official Hermes
# installer does (old image: Python 3.11.16 + SQLite 3.53.1).
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# ── Hermes Agent: deterministic clone-and-install ───────────────────────
# HERMES_REF can be pinned to a tag/commit for full reproducibility.
ARG HERMES_REF=main
RUN git clone --depth 1 --branch "$HERMES_REF" \
    https://github.com/NousResearch/hermes-agent.git /opt/hermes

RUN uv python install 3.12 && \
    uv venv --python 3.12 /opt/hermes/venv && \
    uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        -e '/opt/hermes[messaging]'

# ── Bake local ML/doc packages into venv ────────────────────────────────
# faster-whisper: local STT (voice notes) — was lost on redeploy (a180c22).
# librosa: voice_prosody.py affect analysis (energy/F0/register).
# pymupdf + python-docx: triz RAG ingest (PDF/DOCX) (58d9f23).
# cometapi: official CometAPI SDK for vision_analyze.py (vision-insight) — added 2026-08-20.
RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        pymupdf python-docx faster-whisper librosa cometapi

# ── Pin python-telegram-bot to 22.6 ─────────────────────────────────────
# Upstream bug NousResearch/hermes-agent#85272: the messaging extra pins
# python-telegram-bot 22.8, which routes the Telegram adapter through the
# deferred SDK import path where TypeHandler is never rebound from
# typing.Any → "Any cannot be instantiated" → gateway boots with no
# connected platforms. This install runs AFTER the extra, so 22.6 wins.
# TODO: unpin after upstream PR #85421 merges and HERMES_REF is bumped.
RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        'python-telegram-bot[webhooks]==22.6' && \
    /opt/hermes/venv/bin/pip show python-telegram-bot | head -2

# ── Build-time guard: never deploy a WAL-reset-vulnerable runtime ───────
# Fails the build loudly if the venv's linked SQLite is older than the
# 3.51.3 fix. A silent skip here means silent db corruption later.
RUN /opt/hermes/venv/bin/python -c \
    "import sqlite3; v=tuple(map(int, sqlite3.sqlite_version.split('.'))); \
     assert v >= (3, 51, 3), f'Vulnerable SQLite {sqlite3.sqlite_version} — WAL-reset bug'; \
     print('SQLite', sqlite3.sqlite_version, 'OK (WAL-reset patched)')"

RUN ln -sf /opt/hermes/venv/bin/hermes /usr/local/bin/hermes && \
    /usr/local/bin/hermes --version

# ── Apply local patches to upstream code ────────────────────────────────
# 1. video-note.patch: Telegram adapter previously IGNORED round video
#    messages (кружок) — restores video_note handling.
# 2. stt-local-files-only.patch (2026-08-28): path-based STT models
#    (stt.local.model: /opt/hermes-models/turbo) failed with "Repo id must
#    be in the form ..." — pass local_files_only=True for directory paths so
#    voice transcription uses the local turbo model instead of erroring out.
COPY patches/ /opt/patches/
RUN git -C /opt/hermes apply /opt/patches/video-note.patch && \
    echo "Applied: video-note.patch" && \
    git -C /opt/hermes apply /opt/patches/stt-local-files-only.patch && \
    echo "Applied: stt-local-files-only.patch"

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
