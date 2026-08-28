#!/bin/bash
# Pre-flight for Railway: the persistent volume can be 100% full and/or hold
# a corrupted state.db, which makes the gateway crash-loop on boot.
# This script frees space, then hands off to entrypoint.sh.
#
# POLICY (2026-08-29): state.db is NEVER deleted or overwritten automatically.
# If integrity_check fails, we back up the file and HALT with a clear message.
# Recovery requires manual operator confirmation — see OPERATIONS.md §5.

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"

# 1) Free disk space: logs, caches, temp files (never config or databases)
rm -rf "$HERMES_HOME"/logs/* "$HERMES_HOME"/cache/* "$HERMES_HOME"/tmp/* 2>/dev/null || true
find "$HERMES_HOME" -maxdepth 1 -name '*.log' -delete 2>/dev/null || true

# 2) Non-destructive state.db integrity check.
#    On failure: backup only. HALT and require manual recovery.
#    Do NOT mv/rm state.db — the data may be recoverable via VACUUM INTO.
if [ -f "$HERMES_HOME/state.db" ]; then
    INTEGRITY=$(python3 -c \
        "import sqlite3; c=sqlite3.connect('$HERMES_HOME/state.db'); \
         print(c.execute('PRAGMA integrity_check').fetchone()[0])" 2>/dev/null || echo "error")
    if [ "$INTEGRITY" != "ok" ]; then
        TS=$(date +%s)
        BACKUP="$HERMES_HOME/state.db.corrupt.$TS"
        echo "start.sh: state.db integrity_check failed (result: $INTEGRITY)"
        echo "start.sh: backing up to $BACKUP (original preserved)"
        cp "$HERMES_HOME/state.db" "$BACKUP" 2>/dev/null || true
        echo "start.sh: HALTING — manual recovery required."
        echo "          See OPERATIONS.md §5 for the recovery procedure."
        echo "          After recovery, redeploy to restart the gateway."
        exit 1
    fi
fi

exec bash /entrypoint.sh
