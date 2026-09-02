# Hermes on Railway — Operations Runbook

This document covers day-to-day operational checks and recovery procedures
for the Hermes Telegram gateway deployed on Railway.

---

## 1. Check active provider and model

**From Railway shell** (Service → Shell):
```bash
hermes config show
hermes portal info
```

Expected output: provider should be `nous` or `nous-portal`.
Model IDs come from Nous Portal catalog — verify at https://portal.nousresearch.com.

**From startup logs** (Railway → Deployments → latest → Logs):
Look for the `HERMES STARTUP DIAGNOSTIC` block near the top of the log.
It prints provider name, SQLite version, state.db size, disk free — no secrets.

To confirm CometAPI is NOT active:
- Check that `COMETAPI_API_KEY` or `COMETAPI_KEY` does NOT appear in the
  diagnostic block under "Provider". These keys are intentionally excluded from
  Hermes runtime env even if they exist in Railway Variables.
- Run `hermes config show | grep -i comet` — should return nothing.

---

## 2. Check Telegram gateway status

**From Railway logs:**
```
Railway → your service → Deployments → latest → Logs
```
Look for:
- `Starting Hermes Telegram gateway (polling mode)...` — gateway started
- `TELEGRAM_ALLOWED_USERS: configured` — user restriction active
- Any `ERROR` or `⚠` lines in the startup diagnostic

**From Railway shell:**
```bash
hermes gateway status
# or:
curl -s http://localhost:8642/health
```

If the gateway is connected but not responding to messages:
1. Check for `context_length_exceeded` errors in logs.
2. Check for `Any cannot be instantiated` — indicates python-telegram-bot
   version conflict; the Dockerfile pins 22.6 to prevent this.
3. Try `/reset` or `/clear` in Telegram to start a fresh session.

---

## 3. Diagnose context overflow

Symptoms: bot stops replying mid-conversation, logs show
`context_length_exceeded` or `compression made no progress`.

**Steps:**
1. In Railway logs, search for `context_length_exceeded` or `compression`.
2. In Telegram, send `/reset` to start a fresh session (last message is not lost).
3. If `/reset` is unavailable, send `/clear` to wipe context.
4. To prevent recurrence: keep conversations focused; avoid sending very large
   file contents or long code blocks in a single message.

Hermes applies sliding-window compression automatically; the gateway will
notify you in Telegram if the context was trimmed. If compression hangs
beyond ~60 seconds, Railway's `restartPolicyType: ON_FAILURE` will restart
the service automatically (up to 5 retries).

---

## 4. Confirm CometAPI is not in runtime

```bash
# In Railway shell:
hermes config show | grep -i comet    # should return nothing
pip show cometapi 2>&1                # should return "not found"
cat ~/.hermes/.env | grep -i comet    # should return nothing
env | grep -i comet                   # should return nothing
```

If any of the above returns output, the Dockerfile or entrypoint.sh has
been modified. Review the diff and redeploy from the patched branch.

---

## 5. state.db recovery procedure

**Symptoms:** startup log shows `state.db integrity_check FAILED` and the
service halts (does not start gateway).

**Policy:** state.db is never deleted automatically. Recovery is always manual.

**Recovery steps:**

```bash
# 1. In Railway shell, inspect the backup:
ls -lh ~/.hermes/state.db.corrupt-*

# 2. Attempt VACUUM INTO rescue (recovers messages into a fresh clean DB):
python3 - << 'EOF'
import sqlite3
con = sqlite3.connect('file:$HOME/.hermes/state.db.corrupt-<TIMESTAMP>?mode=ro', uri=True)
con.execute("VACUUM INTO '$HOME/.hermes/state_rescued.db'")
con.close()
chk = sqlite3.connect('file:$HOME/.hermes/state_rescued.db?mode=ro', uri=True)
print('integrity:', chk.execute('PRAGMA integrity_check').fetchone()[0])
print('messages: ', chk.execute('SELECT COUNT(*) FROM messages').fetchone()[0])
chk.close()
EOF

# 3. If rescued DB passes integrity_check:
mv ~/.hermes/state.db ~/.hermes/state.db.original-bad
mv ~/.hermes/state_rescued.db ~/.hermes/state.db
rm -f ~/.hermes/state.db-wal ~/.hermes/state.db-shm

# 4. If rescue fails (no recoverable data), start fresh:
#    Only do this after confirming no data is recoverable.
mv ~/.hermes/state.db ~/.hermes/state.db.unrecoverable
rm -f ~/.hermes/state.db-wal ~/.hermes/state.db-shm

# 5. Trigger a new Railway deployment to restart the gateway.
```

Memories stored in `~/.hermes/memories/` are separate from state.db
and survive a state.db reset.

---

## 6. Safe Railway redeploy

1. Push changes to the `fix/telegram-nous-resilience` branch (or `main` after merge).
2. Railway detects the push and triggers an automatic rebuild.
3. **Do not force-restart** a running healthy deployment — Railway will
   send a SIGTERM and wait for graceful shutdown before starting the new container.
4. Monitor the new deployment's logs for the `HERMES STARTUP DIAGNOSTIC` block
   and confirm the gateway reaches `Starting Hermes Telegram gateway`.
5. Send a test message in Telegram to confirm the bot is responding.

To trigger a redeploy without a code change:
```
Railway → your service → Deployments → Redeploy
```

---

## 7. Post-deploy checklist

- [ ] Startup logs show `HERMES STARTUP DIAGNOSTIC` with correct Nous provider
- [ ] No `⚠ EXCLUDED KEY IN RAILWAY ENV` warnings for CometAPI in logs
- [ ] Logs reach `Starting Hermes Telegram gateway (polling mode)...`
- [ ] Bot responds to a test message in Telegram
- [ ] `hermes config show` confirms provider is Nous (not OpenRouter/CometAPI)
- [ ] `pip show cometapi` in Railway shell returns "not found"
- [ ] SQLite version in diagnostic is >= 3.51.3
- [ ] state.db healthy (no integrity error in logs)
- [ ] Disk free is > 200 MB on the Hermes volume

---

## 8. Browser CDP verification

Chromium CDP runs **inside the container only**, bound to `127.0.0.1:9222`.
It is intentionally never exposed on a public port.

### Confirm CDP is alive

```bash
curl -s http://127.0.0.1:9222/json/version
```

Expected: JSON object with `Browser`, `Protocol-Version`, `User-Agent`,
and `webSocketDebuggerUrl` fields.
If this returns nothing or connection refused, Chromium is not running —
check `/tmp/chromium-cdp.log` for the failure reason.

### Confirm browser.cdp_url is written to config

```bash
grep -A5 '^browser:' ~/.hermes/config.yaml || echo "(no browser: section found)"
```

Expected output includes:
```
browser:
  cdp_url: http://127.0.0.1:9222
```

If the line is missing, `entrypoint.sh` did not reach the CDP-ready block.
Check startup logs for `✓ Chromium CDP ready` and `✓ browser.cdp_url configured`.

### Functional browser_exec test

```bash
hermes chat -q "Use browser_exec only. Open https://example.com and return the page title. Do not use web_extract or any HTTP-fetch fallback."
```

Expected result: agent returns `Example Domain` (the actual `<title>` of
https://example.com), retrieved via `browser_exec`, **not** via `web_extract`.

If the agent still falls back to `web_extract` or says "Chrome isn't running":
1. Verify `curl -s http://127.0.0.1:9222/json/version` returns valid JSON.
2. Verify `grep -A5 '^browser:' ~/.hermes/config.yaml` shows `cdp_url`.
3. Check startup logs for `⚠ Chromium CDP did not come up` or Python errors.
4. If CDP is up but `browser_exec` still auto-launches: confirm the installed
   Hermes version supports `browser.cdp_url` — run `hermes --version` and
   compare to the `HERMES_REF` in `Dockerfile` (currently `main`).

### Runtime env cross-check

```bash
tr '\0' '\n' < /proc/1/environ | grep -E '^(BROWSER_CDP_URL|HERMES_BROWSER_CDP_URL|HERMES_DISABLE_BROWSER|HERMES_DISABLE_BROWSER_CDP)='
```

### Security reminder

**Never expose TCP 9222 (or any CDP port) on a public Railway port.**
CDP has no authentication. All access must remain on `127.0.0.1` loopback.
Do not add port 9222 to Railway's public networking configuration.
