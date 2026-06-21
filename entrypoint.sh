#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"

echo "=== Hermes on Railway — Entrypoint ==="

# ── Fail fast if Telegram token is missing ──────────────────────────────
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "ERROR: TELEGRAM_BOT_TOKEN is not set."
    echo "       Add it to your Railway Variables (from @BotFather)."
    echo "       Without it, the Telegram gateway cannot start."
    exit 1
fi

# ── Ensure ~/.hermes exists ─────────────────────────────────────────────
mkdir -p "$HERMES_HOME"

# ── Write secrets to .env ───────────────────────────────────────────────
echo "→ Writing secrets to .env..."
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Detect which provider keys are set (log names only, never values)
PROVIDER_KEYS=""
for VAR in OPENROUTER_API_KEY ANTHROPIC_API_KEY STEPFUN_API_KEY \
           OPENAI_API_KEY HF_TOKEN GEMINI_API_KEY DEEPSEEK_API_KEY; do
    if [ -n "${!VAR}" ]; then
        echo "${VAR}=${!VAR}" >> "$ENV_FILE"
        PROVIDER_KEYS="${PROVIDER_KEYS} ${VAR}"
    fi
done

if [ -n "$PROVIDER_KEYS" ]; then
    echo "   Detected provider keys:${PROVIDER_KEYS}"
else
    echo "   WARNING: No provider API key detected. Hermes default model may not work."
fi

# Telegram credentials
echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> "$ENV_FILE"
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" >> "$ENV_FILE"
    echo "   TELEGRAM_ALLOWED_USERS: configured"
else
    echo "   TELEGRAM_ALLOWED_USERS: not set (any user can interact)"
fi

# ── Verify installation ─────────────────────────────────────────────────
echo "→ Verifying Hermes..."
hermes --version 2>&1 || { echo "ERROR: Hermes not found"; exit 1; }

# ── Railway-safe feature gating ─────────────────────────────────────────
# Disable heavy/optional features that cause instability on Railway.
# These env vars are read by Hermes at runtime; if a var is not
# recognized, it is silently ignored (no-op).
echo "→ Applying Railway-safe defaults..."

# Browser / computer-use: already skipped at install, but also gate at runtime
export HERMES_DISABLE_BROWSER="${HERMES_DISABLE_BROWSER:-true}"
export HERMES_DISABLE_COMPUTER_USE="${HERMES_DISABLE_COMPUTER_USE:-true}"
export HERMES_DISABLE_BROWSER_CDP="${HERMES_DISABLE_BROWSER_CDP:-true}"

# Mixture-of-agents: disable to avoid 429 retry storms on free-tier models
export HERMES_DISABLE_MOA="${HERMES_DISABLE_MOA:-true}"
export HERMES_MOA_MAX_RETRIES="${HERMES_MOA_MAX_RETRIES:-1}"

# Self-improvement / background review loops: disable to reduce memory churn
export HERMES_DISABLE_SELF_IMPROVEMENT="${HERMES_DISABLE_SELF_IMPROVEMENT:-true}"
export HERMES_SELF_IMPROVEMENT_INTERVAL="${HERMES_SELF_IMPROVEMENT_INTERVAL:-0}"

# Security tools: disable tirith to avoid timeout noise
export HERMES_DISABLE_TIRITH="${HERMES_DISABLE_TIRITH:-true}"

# Memory: keep default limit but log if overridden
if [ -n "${HERMES_MEMORY_MAX_CHARS}" ]; then
    echo "   HERMES_MEMORY_MAX_CHARS: ${HERMES_MEMORY_MAX_CHARS}"
fi

echo "   Railway-safe defaults applied (browser=off, moa=off, self-improvement=off, tirith=off)"

# ── Telegram polling conflict mitigation ────────────────────────────────
# On Railway restarts, a stale getUpdates session may still be held open
# on Telegram's servers. Delete any cached offset file so the new session
# starts fresh and does not fight the old one.
if [ -f "$HERMES_HOME/telegram_offset" ]; then
    echo "→ Clearing stale Telegram offset file..."
    rm -f "$HERMES_HOME/telegram_offset"
fi

# ── Start gateway ───────────────────────────────────────────────────────
echo "→ Starting Hermes Telegram gateway (polling mode)..."
exec hermes gateway run
