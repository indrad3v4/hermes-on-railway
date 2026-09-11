#!/bin/bash
# handoff_watch.sh — no-agent session-handoff nudge (TRIZ #1, №22 обратная связь).
# Silent tick (no output) while nothing needs doing; prints ONE line when a live
# session has grown past the threshold with no fresh handoff. Zero model cost.
set -uo pipefail
PY=/opt/hermes/venv/bin/python3
SCRIPT=/root/.hermes/scripts/session_handoff.py
THRESHOLD="${HANDOFF_THRESHOLD:-40}"

OUT=$("$PY" "$SCRIPT" --threshold "$THRESHOLD" 2>/dev/null)
RC=$?
if [ "$RC" -eq 0 ] && [ -n "$OUT" ]; then
    printf '%s\n' "$OUT"
    printf '  → /handoff отдать контекст, потом /new; вернуться через /brief\n'
fi
exit 0
