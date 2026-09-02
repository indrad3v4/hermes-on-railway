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
mkdir -p "$HERMES_HOME/bin"

# ── Write secrets to .env ───────────────────────────────────────────────
echo "→ Writing secrets to .env..."
: > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Nous Portal / Nous API — primary and only provider for this deployment.
# NOUS_PORTAL_TOKEN: issued at portal.nousresearch.com (OAuth)
# NOUS_API_KEY: issued at nousresearch.com/api (direct API)
# At least one must be set for Hermes to reach Nous models.
PROVIDER_KEYS=""
for VAR in NOUS_PORTAL_TOKEN NOUS_API_KEY \
           HF_TOKEN FIRECRAWL_API_KEY GITHUB_TOKEN; do
    if [ -n "${!VAR}" ]; then
        echo "${VAR}=${!VAR}" >> "$ENV_FILE"
        PROVIDER_KEYS="${PROVIDER_KEYS} ${VAR}"
    fi
done

# Safety: keys that would enable non-Nous providers are intentionally
# excluded from the .env export cycle. If they exist in Railway Variables
# they remain available to Railway infrastructure but are NOT passed to
# Hermes runtime. This prevents automatic fallback to CometAPI, OpenRouter,
# OpenAI, or StepFun.
# Excluded: OPENROUTER_API_KEY ANTHROPIC_API_KEY STEPFUN_API_KEY
#           OPENAI_API_KEY COMETAPI_API_KEY COMETAPI_KEY

if [ -n "$PROVIDER_KEYS" ]; then
    echo "   Detected provider keys:${PROVIDER_KEYS}"
else
    echo "   WARNING: No Nous provider key detected (NOUS_PORTAL_TOKEN or NOUS_API_KEY)."
    echo "            Hermes cannot reach Nous Portal models without at least one of these."
    echo "            Set NOUS_PORTAL_TOKEN or NOUS_API_KEY in Railway Variables."
fi

# Telegram credentials
echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> "$ENV_FILE"
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" >> "$ENV_FILE"
    echo "   TELEGRAM_ALLOWED_USERS: configured"
else
    echo "   TELEGRAM_ALLOWED_USERS: not set (any user can interact)"
fi

# ── Git/GitHub agent tooling self-healing ────────────────────────────────
# /root (overlay) is wiped on redeploy — gh stays (Dockerfile), but git
# config + credentials die with it. Recreate from GH_TOKEN/GITHUB_TOKEN so
# agent git workflows keep working in every fresh container.
if [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
    GHTOK="${GITHUB_TOKEN:-$GH_TOKEN}"
    GH_LOGIN=$(curl -s -H "Authorization: Bearer $GHTOK" \
        https://api.github.com/user \
        | python3 -c "import sys,json;print(json.load(sys.stdin).get('login',''))" 2>/dev/null || true)
    if [ -n "$GH_LOGIN" ]; then
        git config --global user.name "$GH_LOGIN"
        git config --global user.email "$GH_LOGIN@users.noreply.github.com"
        git config --global credential.helper store
        printf 'https://x-access-token:%s@github.com\n' "$GHTOK" > "$HOME/.git-credentials"
        chmod 600 "$HOME/.git-credentials"
        echo "   git credentials configured for $GH_LOGIN (token: ${GITHUB_TOKEN:+GITHUB_TOKEN}${GH_TOKEN:+GH_TOKEN})"
    else
        echo "   ⚠ GH_TOKEN/GITHUB_TOKEN present but invalid — git credentials NOT configured"
    fi
fi

# ── Telegram proxy (fix: Railway network may block api.telegram.org) ────
# If api.telegram.org is unreachable, Hermes loops on DNS-over-HTTPS
# fallback with "Any cannot be instantiated" errors.
# Set TELEGRAM_PROXY in Railway Variables (e.g. socks5://host:port or
# http://host:port) to route Telegram traffic through a proxy.
if [ -n "$TELEGRAM_PROXY" ]; then
    echo "TELEGRAM_PROXY=$TELEGRAM_PROXY" >> "$ENV_FILE"
    echo "   TELEGRAM_PROXY: configured (routing via proxy)"
else
    echo "   TELEGRAM_PROXY: not set — if Telegram is unreachable, set this variable"
fi

# ── state.db pre-flight: non-destructive integrity check ────────────────
# Policy (2026-08-29): never auto-delete or auto-overwrite state.db.
# On corruption: backup only, then HALT with a clear message.
# Recovery to a new DB requires manual operator confirmation.
# See OPERATIONS.md §5 for the recovery procedure.
DB="$HERMES_HOME/state.db"
if [ -f "$DB" ]; then
    echo "→ state.db pre-flight check..."
    if python3 - "$DB" <<'PYEOF'
import sqlite3, sys
try:
    con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    ok = con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    con.close()
except Exception:
    ok = False
sys.exit(0 if ok else 1)
PYEOF
    then
        echo "   state.db: healthy"
    else
        TS=$(date +%Y%m%d_%H%M%S)
        BACKUP="$HERMES_HOME/state.db.corrupt-$TS"
        echo "   ✗ state.db integrity check FAILED."
        echo "   → Backing up to: $BACKUP"
        cp "$DB" "$BACKUP" 2>/dev/null || true
        echo "   ✗ HALTING. state.db is corrupt and requires manual recovery."
        echo "     Do NOT delete state.db automatically — data may be recoverable."
        echo "     Run the recovery procedure in OPERATIONS.md §5, then redeploy."
        echo "     Backup saved at: $BACKUP"
        exit 1
    fi
fi

# ── Verify installation ─────────────────────────────────────────────────
echo "→ Verifying Hermes..."
hermes --version 2>&1 || { echo "ERROR: Hermes not found"; exit 1; }

# ── HF cache durability ────────────────────────────────────────────────
# /root/.cache is EPHEMERAL (overlay) — wiped on every redeploy, so the
# faster-whisper STT model (1.5 GB) re-downloads after every deploy.
# Point HF caches at the durable volume so the model survives redeploys.
export HF_HOME="${HF_HOME:-$HERMES_HOME/hf-cache}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HERMES_HOME/hf-cache/hub}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$HERMES_HOME/hf-cache/hub}"

# ── browser-use CLI: repair symlink into /root/.hermes/bin ───────────────
# The Dockerfile installs browser-use as a uv tool at build time, but
# /root/.hermes/bin lives on a durable Railway volume that is mounted
# AFTER the image layers are built. Re-run the install at container start
# so the CLI entry-point is always present on the volume-backed path.
export UV_TOOL_BIN_DIR="$HERMES_HOME/bin"
if ! command -v browser-use &>/dev/null && ! [ -x "$HERMES_HOME/bin/browser-use" ]; then
    echo "→ Repairing browser-use CLI symlink in $HERMES_HOME/bin..."
    uv tool install --force browser-use --quiet 2>&1 || \
        echo "   ⚠ browser-use reinstall failed (non-fatal — Chromium still available)"
fi

# ── Launch headless Chromium CDP on 127.0.0.1:9222 ──────────────────────
# Hermes web_browsing tools require a running CDP endpoint.
# We background Chromium before starting the gateway and wait for it.
CDP_PORT=${HERMES_BROWSER_CDP_PORT:-9222}
CDP_DATA_DIR=/tmp/bu-cdp

echo "→ Starting headless Chromium CDP on 127.0.0.1:${CDP_PORT}..."
mkdir -p "$CDP_DATA_DIR"

chromium \
    --headless=new \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=${CDP_PORT} \
    --user-data-dir="$CDP_DATA_DIR" \
    --no-first-run \
    --disable-extensions \
    &>/tmp/chromium-cdp.log &
CHROMIUM_PID=$!

# Wait up to 20 s for CDP /json/version to respond
CDP_READY=0
for i in $(seq 1 20); do
    if curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" -o /dev/null 2>/dev/null; then
        CDP_READY=1
        echo "   ✓ Chromium CDP ready in ${i}s (pid $CHROMIUM_PID)"
        break
    fi
    sleep 1
done

if [ "$CDP_READY" -eq 0 ]; then
    echo "   ⚠ Chromium CDP did not come up within 20s — browser tools may be unavailable"
    echo "     Last log lines:"
    tail -5 /tmp/chromium-cdp.log 2>/dev/null || true
    # Non-fatal: gateway still starts; browsing tools will report unavailable
fi

# ── Railway-safe feature gating ─────────────────────────────────────────
# Disable heavy/optional features that cause instability on Railway.
# These env vars are read by Hermes at runtime; if a var is not
# recognized, it is silently ignored (no-op).
echo "→ Applying Railway-safe defaults..."

# Browser / computer-use: CDP is now running — enable browser tools.
# Allow override via Railway Variables (set to true to re-disable).
export HERMES_DISABLE_BROWSER="${HERMES_DISABLE_BROWSER:-false}"
export HERMES_DISABLE_COMPUTER_USE="${HERMES_DISABLE_COMPUTER_USE:-false}"
export HERMES_DISABLE_BROWSER_CDP="${HERMES_DISABLE_BROWSER_CDP:-false}"

# Write CDP endpoint so Hermes tools know where to connect
export HERMES_BROWSER_CDP_URL="${HERMES_BROWSER_CDP_URL:-http://127.0.0.1:${CDP_PORT}}"

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

# ── Tool-loop circuit breaker (unattended gateway) ──────────────────────
# Official docs (2026): hard_stop_enabled defaults to false, which is
# safe for interactive CLI sessions but dangerous for headless gateway
# deployments — the agent can loop forever on repeated tool failures.
# Enable the circuit breaker so Railway's restart policy can kick in.
# Override with HERMES_TOOL_LOOP_HARD_STOP=false if you want warnings-only.
export HERMES_TOOL_LOOP_HARD_STOP="${HERMES_TOOL_LOOP_HARD_STOP:-true}"
export HERMES_TOOL_LOOP_HARD_STOP_EXACT_FAILURE="${HERMES_TOOL_LOOP_HARD_STOP_EXACT_FAILURE:-5}"
export HERMES_TOOL_LOOP_HARD_STOP_IDEMPOTENT="${HERMES_TOOL_LOOP_HARD_STOP_IDEMPOTENT:-5}"

echo "   Railway-safe defaults applied (browser=ON cdp=ON, moa=off, self-improvement=off, tirith=off, hard_stop=on)"

# ── Root gateway opt-in ─────────────────────────────────────────────────
# Hermes v0.20.1+ refuses to run the gateway as root when it detects the
# official-image layout (/opt/hermes). On Railway the container runs as
# root by default and the volume ($HERMES_HOME) is root-owned anyway —
# there is no non-root user to break, so the risk the guard warns about
# does not apply. Opt in explicitly.
export HERMES_ALLOW_ROOT_GATEWAY="${HERMES_ALLOW_ROOT_GATEWAY:-1}"

# ── Telegram init timeout ────────────────────────────────────────────────
# Allow up to 15 seconds for the Telegram adapter to establish its first
# connection before Hermes declares the gateway unhealthy.
export HERMES_TELEGRAM_INIT_TIMEOUT="${HERMES_TELEGRAM_INIT_TIMEOUT:-15}"

# ── API server (healthcheck endpoint) ───────────────────────────────────
# Exposes :8642/health for Railway health monitoring and external tools.
# API_SERVER_KEY must be >= 8 chars (Hermes requirement). Generate from
# urandom if not set in Railway Variables.
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
if [ -z "${API_SERVER_KEY:-}" ]; then
    export API_SERVER_KEY=$(python3 -c \
        "import os; print(os.urandom(24).hex())" 2>/dev/null || echo "hermes-railway-default-key-2026")
    echo "   API_SERVER_KEY: auto-generated (not set in Railway Variables)"
else
    echo "   API_SERVER_KEY: set via Railway Variables"
fi
# Write API server settings to .env so Hermes runtime picks them up
echo "API_SERVER_ENABLED=${API_SERVER_ENABLED}" >> "$ENV_FILE"
echo "API_SERVER_HOST=${API_SERVER_HOST}" >> "$ENV_FILE"
echo "API_SERVER_KEY=${API_SERVER_KEY}" >> "$ENV_FILE"

# ── Telegram polling conflict mitigation ────────────────────────────────
# On Railway restarts, a stale getUpdates session may still be held open
# on Telegram's servers. Delete any cached offset file so the new session
# starts fresh and does not fight the old one.
if [ -f "$HERMES_HOME/telegram_offset" ]; then
    echo "→ Clearing stale Telegram offset file..."
    rm -f "$HERMES_HOME/telegram_offset"
fi

# ── Startup diagnostic (no secrets) ─────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────"
echo "│  HERMES STARTUP DIAGNOSTIC"
echo "├─────────────────────────────────────────────────────"

# Provider
if [ -n "$NOUS_PORTAL_TOKEN" ]; then
    echo "│  Provider : Nous Portal (NOUS_PORTAL_TOKEN set)"
elif [ -n "$NOUS_API_KEY" ]; then
    echo "│  Provider : Nous API (NOUS_API_KEY set)"
else
    echo "│  Provider : ⚠ NONE — no Nous key found"
fi

# Non-Nous providers — warn loudly if they are present in env
for EXCLUDED in OPENROUTER_API_KEY OPENAI_API_KEY STEPFUN_API_KEY COMETAPI_API_KEY COMETAPI_KEY; do
    if [ -n "${!EXCLUDED}" ]; then
        echo "│  ⚠ EXCLUDED KEY IN RAILWAY ENV: $EXCLUDED (NOT passed to Hermes)"
    fi
done

# SQLite version
SQLITE_VER=$(/opt/hermes/venv/bin/python -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null || echo "unknown")
echo "│  SQLite   : $SQLITE_VER"

# state.db
if [ -f "$DB" ]; then
    DB_SIZE=$(du -sh "$DB" 2>/dev/null | cut -f1 || echo "?")
    echo "│  state.db : present ($DB_SIZE)"
else
    echo "│  state.db : not present (fresh start)"
fi

# Disk space
DISK_FREE=$(df -h "$HERMES_HOME" 2>/dev/null | tail -1 | awk '{print $4}' || echo "?")
echo "│  Disk free: $DISK_FREE on $HERMES_HOME"

# API server
echo "│  API srv  : :8642/health (API_SERVER_ENABLED=${API_SERVER_ENABLED})"

# Tool-loop circuit breaker
echo "│  Hard stop: HERMES_TOOL_LOOP_HARD_STOP=${HERMES_TOOL_LOOP_HARD_STOP} (exact=${HERMES_TOOL_LOOP_HARD_STOP_EXACT_FAILURE}, idempotent=${HERMES_TOOL_LOOP_HARD_STOP_IDEMPOTENT})"

# Telegram init timeout
echo "│  TG init  : ${HERMES_TELEGRAM_INIT_TIMEOUT}s timeout"
echo "│  Gateway  : polling mode (one replica)"

# CDP status
if [ "${CDP_READY:-0}" -eq 1 ]; then
    echo "│  Browser  : Chromium CDP ✓ http://127.0.0.1:${CDP_PORT} (pid ${CHROMIUM_PID})"
else
    echo "│  Browser  : Chromium CDP ✗ not ready (tools will be unavailable)"
fi

# TODO(arch): Official nousresearch/hermes-agent:latest now uses s6-overlay
# as PID 1 (not tini). When migrating to the official base image, remove
# the tini ENTRYPOINT from Dockerfile and update entrypoint.sh accordingly.
# Ref: https://hermes-agent.nousresearch.com/docs/user-guide/docker/
echo "│  Init sys : tini (tech debt: migrate to s6 on official image)"

echo "└─────────────────────────────────────────────────────"
echo ""

# ── Start gateway ───────────────────────────────────────────────────────
echo "→ Starting Hermes Telegram gateway (polling mode)..."
exec hermes gateway run
