#!/bin/bash
# Pre-flight for Railway: the persistent volume can be 100% full and/or hold
# a corrupted state.db, which makes the gateway crash-loop on boot.
# This script frees space and quarantines a broken DB, then hands off to the
# original entrypoint.sh (untouched).

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"

# 1) Free disk space: logs, caches, temp files (never config or databases)
rm -rf "$HERMES_HOME"/logs/* "$HERMES_HOME"/cache/* "$HERMES_HOME"/tmp/* 2>/dev/null || true
find "$HERMES_HOME" -maxdepth 1 -name '*.log' -delete 2>/dev/null || true

# 2) If the session DB is corrupted, move it aside so Hermes can start fresh.
#    config.yaml / .env / auth files are left untouched.
if [ -f "$HERMES_HOME/state.db" ]; then
  if ! python3 -c "import sqlite3; c = sqlite3.connect('$HERMES_HOME/state.db'); print(c.execute('PRAGMA integrity_check').fetchone()[0])" 2>/dev/null | grep -q '^ok$'; then
    echo "start.sh: state.db failed integrity_check - moving it aside"
    mv "$HERMES_HOME/state.db" "$HERMES_HOME/state.db.corrupt.$(date +%s)" || true
    rm -f "$HERMES_HOME/state.db-wal" "$HERMES_HOME/state.db-shm" || true
  fi
fi

exec bash /entrypoint.sh
