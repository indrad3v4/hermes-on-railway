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

COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /start.sh /entrypoint.sh

ENTRYPOINT ["bash", "/start.sh"]
