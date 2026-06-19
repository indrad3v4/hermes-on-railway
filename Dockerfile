FROM debian:13-slim

# System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git xz-utils \
        python3-venv python3-pip && \
    rm -rf /var/lib/apt/lists/*

# Install Hermes via official installer
# Flags: --non-interactive (no stdin prompts), --skip-setup (no wizard),
#         --skip-browser (no Playwright), --no-skills (clean start)
RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | \
    bash -s -- \
        --non-interactive \
        --skip-setup \
        --skip-browser \
        --no-skills

# Ensure hermes is on PATH
ENV PATH="/root/.hermes/hermes-agent/venv/bin:${PATH}"
ENV PYTHONUNBUFFERED=1
ENV HERMES_HOME=/root/.hermes

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
