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

# ── Start gateway ───────────────────────────────────────────────────────
echo "→ Starting Hermes Telegram gateway (polling mode)..."
exec hermes gateway run
