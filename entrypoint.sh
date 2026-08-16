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
           OPENAI_API_KEY HF_TOKEN GEMINI_API_KEY DEEPSEEK_API_KEY \
           FIRECRAWL_API_KEY GITHUB_TOKEN; do
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

# ── state.db pre-flight: auto-repair before the gateway opens it ────────
# Incident 2026-08-15: full/corrupt state volume left state.db with page-
# level corruption (freelist). Reads worked, every write failed, Hermes
# looped on "run hermes doctor". This block detects and repairs that
# failure class on every boot. Never blocks boot — worst case we start
# with a fresh db.
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
        echo "   ⚠ state.db corrupt — attempting VACUUM INTO rescue (preserves messages)..."
        if python3 - "$DB" "$HERMES_HOME/state_rescued.db" <<'PYEOF'
import sqlite3, sys
try:
    con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    con.execute(f"VACUUM INTO '{sys.argv[2]}'")
    con.close()
    chk = sqlite3.connect(f"file:{sys.argv[2]}?mode=ro", uri=True)
    ok = chk.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    n = chk.execute('SELECT COUNT(*) FROM messages').fetchone()[0]
    chk.close()
    print(f'   rescue integrity ok, {n} messages preserved')
    sys.exit(0 if ok else 1)
except Exception as e:
    print(f'   rescue failed: {e}')
    sys.exit(1)
PYEOF
        then
            cp "$DB" "$HERMES_HOME/state.db.corrupt-$TS" || true
            rm -f "$HERMES_HOME/state.db-wal" "$HERMES_HOME/state.db-shm"
            mv "$HERMES_HOME/state_rescued.db" "$DB"
            echo "   ✓ state.db rescued in place (corrupt copy: state.db.corrupt-$TS)"
        else
            BACKUP=$(ls -t "$HERMES_HOME"/state.db.bak* 2>/dev/null | head -1)
            cp "$DB" "$HERMES_HOME/state.db.corrupt-$TS" || true
            rm -f "$HERMES_HOME/state.db-wal" "$HERMES_HOME/state.db-shm"
            if [ -n "$BACKUP" ]; then
                cp "$BACKUP" "$DB"
                echo "   ✓ restored from backup: $BACKUP"
            else
                rm -f "$DB"
                echo "   ⚠ no rescue, no backup — starting with fresh state.db"
                echo "     (sessions/messages lost; memories in ~/.hermes/memories survive)"
            fi
        fi
    fi
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

# ── Root gateway opt-in ─────────────────────────────────────────────────
# Hermes v0.20.1+ refuses to run the gateway as root when it detects the
# official-image layout (/opt/hermes). On Railway the container runs as
# root by default and the volume ($HERMES_HOME) is root-owned anyway —
# there is no non-root user to break, so the risk the guard warns about
# does not apply. Opt in explicitly.
export HERMES_ALLOW_ROOT_GATEWAY="${HERMES_ALLOW_ROOT_GATEWAY:-1}"

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
