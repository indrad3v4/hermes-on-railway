#!/bin/bash
# Pre-flight for Railway: the persistent volume can be 100% full and/or hold
# a corrupted state.db, which makes the gateway crash-loop on boot.
# This script frees space, then hands off to entrypoint.sh.
#
# POLICY (2026-08-29): state.db is NEVER deleted automatically unless the
# operator explicitly sets HERMES_WIPE_STATE_DB=1 in Railway Variables.
# If integrity_check fails without that flag, we back up and HALT.
# See OPERATIONS.md §5 for the full recovery procedure.

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"

# 1) Free disk space: logs, caches, temp files (never config or databases)
rm -rf "$HERMES_HOME"/logs/* "$HERMES_HOME"/cache/* "$HERMES_HOME"/tmp/* 2>/dev/null || true
find "$HERMES_HOME" -maxdepth 1 -name '*.log' -delete 2>/dev/null || true

# 2) Non-destructive state.db integrity check.
#    On failure: backup only, then HALT — unless HERMES_WIPE_STATE_DB=1.
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

        if [ "${HERMES_WIPE_STATE_DB:-0}" = "1" ]; then
            echo "start.sh: HERMES_WIPE_STATE_DB=1 detected — deleting corrupt state.db"
            echo "start.sh: ⚠ IMPORTANT: remove HERMES_WIPE_STATE_DB from Railway Variables after boot"
            rm -f "$HERMES_HOME/state.db"
            echo "start.sh: state.db removed. Starting fresh."
        else
            echo "start.sh: HALTING — manual recovery required."
            echo "          To wipe and start fresh: set HERMES_WIPE_STATE_DB=1 in Railway Variables"
            echo "          then redeploy. Remove the variable again after successful boot."
            echo "          See OPERATIONS.md §5 for the full recovery procedure."
            exit 1
        fi
    fi
fi

# Reminder: if HERMES_WIPE_STATE_DB is still set on a clean boot, warn loudly
if [ "${HERMES_WIPE_STATE_DB:-0}" = "1" ]; then
    echo "start.sh: ⚠ WARNING — HERMES_WIPE_STATE_DB=1 is still set in Railway Variables."
    echo "          Remove it now to prevent accidental data loss on the next restart."
fi

exec bash /entrypoint.sh
