FROM debian:13-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# Base tools. ripgrep/ffmpeg are installed HERE because the Hermes installer
# later runs `apt install` after the package lists were deleted and fails
# to locate them.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        python3-venv python3-pip \
        ripgrep ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Install Hermes Agent (core CLI only).
# The installer exits 1 when the optional Node/browser dependencies fail
# on Railway's builder, even though the CLI itself installed fine by then.
# Tolerate that so the image build succeeds.
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | \
    bash -s -- \
        --non-interactive \
        --skip-setup \
        --skip-browser \
        --no-skills || \
    echo "WARN: hermes installer exited non-zero (browser/Node deps skipped), continuing"

# Guarantee the hermes command exists even if the installer bailed out early
# before creating its symlink.
RUN if [ ! -e /usr/local/bin/hermes ]; then \
      if [ -e /usr/local/lib/hermes-agent/venv/bin/hermes ]; then \
        ln -s /usr/local/lib/hermes-agent/venv/bin/hermes /usr/local/bin/hermes; \
      elif [ -e /usr/local/lib/hermes-agent/hermes ]; then \
        ln -s /usr/local/lib/hermes-agent/hermes /usr/local/bin/hermes; \
      fi; \
    fi && \
    /usr/local/bin/hermes --version

# ── Pin python-telegram-bot to 22.6 ─────────────────────────────────────
# Upstream bug NousResearch/hermes-agent#85272: Hermes v0.20.x ships
# python-telegram-bot 22.8; the Telegram adapter's deferred SDK import
# (check_telegram_requirements) never rebinds TypeHandler, which stays
# typing.Any → "TypeError: Any cannot be instantiated" at handler
# registration → gateway boots with no connected platforms (cron only).
# 22.6 is the confirmed-good pin per the upstream issue.
# TODO: unpin after upstream PR #85421 merges and Hermes is updated here.
#
# NOTE: the installer can bail early on Railway (tolerated above), so the
# venv path is not guaranteed. Discover pip dynamically instead of
# hardcoding it — and fail the build loudly if no pip is found, because a
# silent skip here means Telegram stays broken (issue #1).
RUN set -e; \
    PIP=""; \
    for p in \
        /usr/local/lib/hermes-agent/venv/bin/pip \
        /root/.hermes/hermes-agent/venv/bin/pip \
        /root/.local/share/hermes/venv/bin/pip; do \
      if [ -x "$p" ]; then PIP="$p"; break; fi; \
    done; \
    if [ -z "$PIP" ]; then \
      PIP=$(find /usr/local/lib /root/.hermes /root/.local -maxdepth 6 -path '*/venv/bin/pip' -type f 2>/dev/null | head -1); \
    fi; \
    if [ -z "$PIP" ] && command -v hermes >/dev/null 2>&1; then \
      HERMES_BIN=$(readlink -f "$(command -v hermes)"); \
      CAND="$(dirname "$HERMES_BIN")/pip"; \
      [ -x "$CAND" ] && PIP="$CAND"; \
    fi; \
    if [ -z "$PIP" ]; then \
      echo "ERROR: no pip found in any Hermes venv — cannot pin python-telegram-bot." >&2; \
      exit 1; \
    fi; \
    echo "→ Using pip: $PIP"; \
    "$PIP" install --no-cache-dir 'python-telegram-bot[webhooks]==22.6'; \
    "$PIP" show python-telegram-bot | head -2

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
