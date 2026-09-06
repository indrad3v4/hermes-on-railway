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

PROVIDER_KEYS=""
for VAR in NOUS_PORTAL_TOKEN NOUS_API_KEY \
           HF_TOKEN FIRECRAWL_API_KEY GITHUB_TOKEN; do
    if [ -n "${!VAR}" ]; then
        echo "${VAR}=${!VAR}" >> "$ENV_FILE"
        PROVIDER_KEYS="${PROVIDER_KEYS} ${VAR}"
    fi
done

# Excluded from .env: OPENROUTER_API_KEY ANTHROPIC_API_KEY STEPFUN_API_KEY
#                     OPENAI_API_KEY COMETAPI_API_KEY COMETAPI_KEY

if [ -n "$PROVIDER_KEYS" ]; then
    echo "   Detected provider keys:${PROVIDER_KEYS}"
else
    echo "   WARNING: No Nous provider key detected (NOUS_PORTAL_TOKEN or NOUS_API_KEY)."
    echo "            Set NOUS_PORTAL_TOKEN or NOUS_API_KEY in Railway Variables."
fi

echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> "$ENV_FILE"
if [ -n "$TELEGRAM_ALLOWED_USERS" ]; then
    echo "TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" >> "$ENV_FILE"
    echo "   TELEGRAM_ALLOWED_USERS: configured"
else
    echo "   TELEGRAM_ALLOWED_USERS: not set (any user can interact)"
fi

# ── Git/GitHub agent tooling self-healing ────────────────────────────────
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
        echo "   git credentials configured for $GH_LOGIN"
    else
        echo "   ⚠ GH_TOKEN/GITHUB_TOKEN present but invalid — git credentials NOT configured"
    fi
fi

# ── Telegram proxy ──────────────────────────────────────────────────────────
if [ -n "$TELEGRAM_PROXY" ]; then
    echo "TELEGRAM_PROXY=$TELEGRAM_PROXY" >> "$ENV_FILE"
    echo "   TELEGRAM_PROXY: configured"
else
    echo "   TELEGRAM_PROXY: not set"
fi

# ── state.db pre-flight: non-destructive integrity check ────────────────
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
        echo "   ✗ HALTING. Run recovery in OPERATIONS.md §5, then redeploy."
        echo "     Backup saved at: $BACKUP"
        exit 1
    fi
fi

# ── Verify installation ─────────────────────────────────────────────────
echo "→ Verifying Hermes..."
hermes --version 2>&1 || { echo "ERROR: Hermes not found"; exit 1; }

# ── HF cache durability ────────────────────────────────────────────────
export HF_HOME="${HF_HOME:-$HERMES_HOME/hf-cache}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HERMES_HOME/hf-cache/hub}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-$HERMES_HOME/hf-cache/hub}"

# ── browser-use CLI: repair symlink ─────────────────────────────────────────
export UV_TOOL_BIN_DIR="$HERMES_HOME/bin"
if ! command -v browser-use &>/dev/null && ! [ -x "$HERMES_HOME/bin/browser-use" ]; then
    echo "→ Repairing browser-use CLI symlink in $HERMES_HOME/bin..."
    uv tool install --force browser-use --quiet 2>&1 || \
        echo "   ⚠ browser-use reinstall failed (non-fatal)"
fi

# ── Launch headless Chromium CDP on 127.0.0.1:9222 ──────────────────────
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
    echo "   ⚠ Chromium CDP did not come up within 20s"
    tail -5 /tmp/chromium-cdp.log 2>/dev/null || true
fi

# ── Write browser.cdp_url into config.yaml ──────────────────────────────
if [ "${CDP_READY}" -eq 1 ]; then
    echo "→ Writing browser.cdp_url to config.yaml..."
    /opt/hermes/venv/bin/python - <<PYEOF
import sys, os, re

config_path = os.path.join(os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes')), 'config.yaml')
cdp_url = f"http://127.0.0.1:{os.environ.get('CDP_PORT', '9222')}"
cdp_line = f"  cdp_url: {cdp_url}\n"

try:
    with open(config_path, 'r') as f:
        content = f.read()
except FileNotFoundError:
    content = ''

lines = content.splitlines(keepends=True)
in_browser = False
browser_section_start = None
cdp_url_line_idx = None
browser_end_idx = None

for idx, line in enumerate(lines):
    stripped = line.rstrip('\n')
    if re.match(r'^browser:\s*$', stripped):
        in_browser = True
        browser_section_start = idx
        continue
    if in_browser:
        if stripped and not stripped.startswith(' ') and not stripped.startswith('#'):
            browser_end_idx = idx
            in_browser = False
            continue
        if re.match(r'^  cdp_url:', stripped):
            cdp_url_line_idx = idx

if browser_section_start is None:
    if content and not content.endswith('\n'):
        content += '\n'
    content += 'browser:\n' + cdp_line
elif cdp_url_line_idx is not None:
    lines[cdp_url_line_idx] = cdp_line
    content = ''.join(lines)
else:
    lines.insert(browser_section_start + 1, cdp_line)
    content = ''.join(lines)

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, 'w') as f:
    f.write(content)
print(f'   browser.cdp_url = {cdp_url}')
PYEOF
    echo "   ✓ browser.cdp_url configured"
else
    echo "   ⚠ Skipping browser.cdp_url write — Chromium CDP not ready"
fi

# ── Railway-safe feature gating ─────────────────────────────────────────
echo "→ Applying Railway-safe defaults..."
export HERMES_DISABLE_BROWSER="${HERMES_DISABLE_BROWSER:-false}"
export HERMES_DISABLE_COMPUTER_USE="${HERMES_DISABLE_COMPUTER_USE:-false}"
export HERMES_DISABLE_BROWSER_CDP="${HERMES_DISABLE_BROWSER_CDP:-false}"
export HERMES_BROWSER_CDP_URL="${HERMES_BROWSER_CDP_URL:-http://127.0.0.1:${CDP_PORT}}"
export HERMES_DISABLE_MOA="${HERMES_DISABLE_MOA:-true}"
export HERMES_MOA_MAX_RETRIES="${HERMES_MOA_MAX_RETRIES:-1}"
export HERMES_DISABLE_SELF_IMPROVEMENT="${HERMES_DISABLE_SELF_IMPROVEMENT:-true}"
export HERMES_SELF_IMPROVEMENT_INTERVAL="${HERMES_SELF_IMPROVEMENT_INTERVAL:-0}"
export HERMES_DISABLE_TIRITH="${HERMES_DISABLE_TIRITH:-true}"
if [ -n "${HERMES_MEMORY_MAX_CHARS}" ]; then
    echo "   HERMES_MEMORY_MAX_CHARS: ${HERMES_MEMORY_MAX_CHARS}"
fi

# ── Auxiliary title generation ─────────────────────────────────────────────
# PROBLEM (2026-09-06): title_generation fires a separate LLM call before
# every response using the auxiliary model slot. On Nous Portal this call
# returns a truncated ChatCompletion (choices=None) that Hermes can't parse,
# logging:
#   "Auxiliary title_generation: LLM returned invalid response"
# The call still blocks for 30-40s (full timeout) before the main response
# is returned, causing "hi" → 42s latency on every message.
#
# FIX: disable the auxiliary title generation entirely.
# Conversation titles will fall back to the first-message preview.
# Re-enable by setting HERMES_DISABLE_TITLE_GENERATION=false in Railway vars.
export HERMES_DISABLE_TITLE_GENERATION="${HERMES_DISABLE_TITLE_GENERATION:-true}"
export HERMES_TITLE_GENERATION_TIMEOUT="${HERMES_TITLE_GENERATION_TIMEOUT:-0}"

echo "   title_gen=OFF (auxiliary model fix: choices=None bug)"
echo "   Railway-safe defaults applied"

# ── Tool-loop circuit breaker ─────────────────────────────────────────────
export HERMES_TOOL_LOOP_HARD_STOP="${HERMES_TOOL_LOOP_HARD_STOP:-true}"
export HERMES_TOOL_LOOP_HARD_STOP_EXACT_FAILURE="${HERMES_TOOL_LOOP_HARD_STOP_EXACT_FAILURE:-5}"
export HERMES_TOOL_LOOP_HARD_STOP_IDEMPOTENT="${HERMES_TOOL_LOOP_HARD_STOP_IDEMPOTENT:-5}"

# ── Root gateway opt-in ─────────────────────────────────────────────────
export HERMES_ALLOW_ROOT_GATEWAY="${HERMES_ALLOW_ROOT_GATEWAY:-1}"

# ── Telegram init timeout ────────────────────────────────────────────────
export HERMES_TELEGRAM_INIT_TIMEOUT="${HERMES_TELEGRAM_INIT_TIMEOUT:-15}"

# ── API server (healthcheck endpoint) ───────────────────────────────────
export API_SERVER_ENABLED="${API_SERVER_ENABLED:-true}"
export API_SERVER_HOST="${API_SERVER_HOST:-0.0.0.0}"
if [ -z "${API_SERVER_KEY:-}" ]; then
    export API_SERVER_KEY=$(python3 -c \
        "import os; print(os.urandom(24).hex())" 2>/dev/null || echo "hermes-railway-default-key-2026")
    echo "   API_SERVER_KEY: auto-generated"
else
    echo "   API_SERVER_KEY: set via Railway Variables"
fi
echo "API_SERVER_ENABLED=${API_SERVER_ENABLED}" >> "$ENV_FILE"
echo "API_SERVER_HOST=${API_SERVER_HOST}" >> "$ENV_FILE"
echo "API_SERVER_KEY=${API_SERVER_KEY}" >> "$ENV_FILE"

# ── Telegram polling conflict mitigation ────────────────────────────────
if [ -f "$HERMES_HOME/telegram_offset" ]; then
    echo "→ Clearing stale Telegram offset file..."
    rm -f "$HERMES_HOME/telegram_offset"
fi

# ── Rate-limit resilience & drain timeout ───────────────────────────────
export HERMES_DRAIN_TIMEOUT_SECONDS="${HERMES_DRAIN_TIMEOUT_SECONDS:-30}"
export HERMES_RATE_LIMIT_BACKOFF_BASE="${HERMES_RATE_LIMIT_BACKOFF_BASE:-2}"
export HERMES_RATE_LIMIT_MAX_RETRIES="${HERMES_RATE_LIMIT_MAX_RETRIES:-2}"
echo "   RL: backoff=${HERMES_RATE_LIMIT_BACKOFF_BASE}s retries=${HERMES_RATE_LIMIT_MAX_RETRIES} drain=${HERMES_DRAIN_TIMEOUT_SECONDS}s"

# ── Primary model restore (sticky-fallback prevention) ──────────────────
echo "→ Restoring primary model..."
/opt/hermes/venv/bin/python - <<'PYEOF'
from pathlib import Path
import re, os

config_path = Path(os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))) / 'config.yaml'
if not config_path.exists():
    print("   config.yaml not found — skipping (fresh install)")
    raise SystemExit(0)

text = config_path.read_text()

desired_model_block = (
    "model:\n"
    "  default: deepseek/deepseek-v4-flash-0731\n"
    "  provider: nous\n"
)

pattern = r'(?m)^model:\n(?:(?:[ \t]+.*|)\n)*'
match = re.search(pattern, text)

if match:
    current_block = match.group(0)
    if current_block.strip() == desired_model_block.strip():
        print("   ✓ primary model already correct")
        raise SystemExit(0)
    new_text = text[:match.start()] + desired_model_block + text[match.end():]
else:
    new_text = desired_model_block + "\n" + text

config_path.write_text(new_text)
print("   ✓ primary model restored: deepseek/deepseek-v4-flash-0731 (provider=nous)")
PYEOF

# ── Fix: rename 'a2a' → 'hermes-telegram' (v0.21.0) ─────────────────────────
echo "→ Fixing toolset name: a2a → hermes-telegram..."
/opt/hermes/venv/bin/python - <<'PYEOF'
from pathlib import Path
import re, os

config_path = Path(os.environ.get('HERMES_HOME', os.path.expanduser('~/.hermes'))) / 'config.yaml'
if not config_path.exists():
    raise SystemExit(0)

text = config_path.read_text()
new_text = re.sub(r'^([ \t]+-[ \t]+)a2a([ \t]*)$', r'\1hermes-telegram\2', text, flags=re.MULTILINE)

if new_text != text:
    config_path.write_text(new_text)
    print("   ✓ a2a → hermes-telegram")
else:
    print("   ✓ toolset already hermes-telegram")
PYEOF

# ── Startup diagnostic (no secrets) ─────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────"
echo "│  HERMES STARTUP DIAGNOSTIC"
echo "├─────────────────────────────────────────────────────"
if [ -n "$NOUS_PORTAL_TOKEN" ]; then
    echo "│  Provider : Nous Portal (NOUS_PORTAL_TOKEN set)"
elif [ -n "$NOUS_API_KEY" ]; then
    echo "│  Provider : Nous API (NOUS_API_KEY set)"
else
    echo "│  Provider : ⚠ NONE — no Nous key found"
fi
for EXCLUDED in OPENROUTER_API_KEY OPENAI_API_KEY STEPFUN_API_KEY COMETAPI_API_KEY COMETAPI_KEY; do
    if [ -n "${!EXCLUDED}" ]; then
        echo "│  ⚠ EXCLUDED KEY: $EXCLUDED (NOT passed to Hermes)"
    fi
done
SQLITE_VER=$(/opt/hermes/venv/bin/python -c "import sqlite3; print(sqlite3.sqlite_version)" 2>/dev/null || echo "unknown")
echo "│  SQLite   : $SQLITE_VER"
if [ -f "$DB" ]; then
    DB_SIZE=$(du -sh "$DB" 2>/dev/null | cut -f1 || echo "?")
    echo "│  state.db : present ($DB_SIZE)"
else
    echo "│  state.db : not present (fresh start)"
fi
DISK_FREE=$(df -h "$HERMES_HOME" 2>/dev/null | tail -1 | awk '{print $4}' || echo "?")
echo "│  Disk free: $DISK_FREE on $HERMES_HOME"
echo "│  API srv  : :8642/health (API_SERVER_ENABLED=${API_SERVER_ENABLED})"
echo "│  Hard stop: HERMES_TOOL_LOOP_HARD_STOP=${HERMES_TOOL_LOOP_HARD_STOP}"
echo "│  TG init  : ${HERMES_TELEGRAM_INIT_TIMEOUT}s timeout"
echo "│  Gateway  : polling mode (one replica)"
echo "│  RL fix   : drain=${HERMES_DRAIN_TIMEOUT_SECONDS}s backoff=${HERMES_RATE_LIMIT_BACKOFF_BASE}s retries=${HERMES_RATE_LIMIT_MAX_RETRIES}"
echo "│  Primary  : deepseek/deepseek-v4-flash-0731 (restored at startup)"
echo "│  Fallback : stepfun→poolside→meituan→upstage"
echo "│  Toolset  : hermes-telegram (a2a renamed)"
echo "│  Title gen: DISABLED (auxiliary choices=None fix)"
if [ "${CDP_READY:-0}" -eq 1 ]; then
    echo "│  Browser  : Chromium CDP ✓ http://127.0.0.1:${CDP_PORT} (pid ${CHROMIUM_PID})"
else
    echo "│  Browser  : Chromium CDP ✗ not ready"
fi
echo "└─────────────────────────────────────────────────────"
echo ""

# ── Start gateway ───────────────────────────────────────────────────────
echo "→ Starting Hermes Telegram gateway (polling mode)..."
exec hermes gateway run
