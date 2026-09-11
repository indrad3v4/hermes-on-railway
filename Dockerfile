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
# Pin the upstream revision used as the debugging baseline. HERMES_REF may
# be overridden with a branch, tag, or commit SHA by the build environment.
ARG HERMES_REF=9e0dc4319ae2d59c60f5226b5c0af58d17755bfa
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /opt/hermes && \
    git -C /opt/hermes fetch --depth 1 origin "$HERMES_REF" && \
    git -C /opt/hermes checkout --detach FETCH_HEAD

RUN uv python install 3.12 && \
    uv venv --python 3.12 /opt/hermes/venv && \
    uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        -e '/opt/hermes[messaging]'

RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        pymupdf python-docx faster-whisper librosa browser-use

# ── Code-visualization arsenal ──────────────────────────────────────────
# Indra's rule: every reply's core message is rendered by CODE (never an
# image model). /opt is ephemeral per container, so the arsenal must be baked
# into the image or it silently disappears (that already happened once).
# graphviz `dot` unlocks diagrams/graphviz/pydot. Kept to wheels-only +
# pure-python so the build needs no compiler; heavy 3D stacks (vtk/pyvista/
# open3d/mayavi) are deliberately out until a real need shows up.
RUN apt-get update && \
    apt-get install -y --no-install-recommends graphviz && \
    rm -rf /var/lib/apt/lists/*
RUN uv pip install --python /opt/hermes/venv/bin/python --no-cache \
        matplotlib seaborn pandas networkx graphviz pydot \
        diagrams schemdraw svgwrite drawsvg pygal \
        plotly kaleido altair vl-convert-python \
        tabulate prettytable fpdf2 img2pdf svglib \
        wordcloud squarify pywaffle xlsxwriter openpyxl \
        imageio imageio-ffmpeg geopandas folium && \
    /opt/hermes/venv/bin/python -c "import matplotlib, networkx, plotly, diagrams, geopandas; print('viz arsenal OK')"

# ── Bake the STT model into the image ───────────────────────────────────
# stt.local.model → /opt/hermes-models/turbo (path-based → loaded locally, no HF
# download at runtime). /opt is ephemeral per container AND the 4.6 GB volume
# cannot hold the 1.6 GB model, so bake it into the image — it then survives
# redeploys because the image is rebuilt from this Dockerfile each deploy.
RUN mkdir -p /opt/hermes-models && \
    /opt/hermes/venv/bin/python -c "from faster_whisper.utils import download_model; \
        download_model('turbo', output_dir='/opt/hermes-models/turbo')" && \
    ls -la /opt/hermes-models/turbo

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

# Repository-managed Firebrowsing assets. Runtime restore maps these into the
# persistent Hermes home without modifying the upstream Hermes checkout.
COPY firebrowsing/ /opt/firebrowsing/
COPY restore-firebrowsing.sh /restore-firebrowsing.sh
RUN chmod +x /restore-firebrowsing.sh

# Repository-managed skills (author-owned files only; book corpora stay on the
# volume — see restore-skills.sh).
COPY skills/ /opt/hermes-skills/
COPY agent-scripts/ /opt/hermes-agent-scripts/
COPY restore-skills.sh /restore-skills.sh
RUN chmod +x /restore-skills.sh

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "-c", "/restore-firebrowsing.sh && /restore-skills.sh && exec /start.sh"]
