#!/usr/bin/env bash
# recover-state-db.sh — forensic-safe repair of Hermes state.db
#
# Origin: incident 2026-08-15 — Railway volume corruption left state.db
# with page-level damage (freelist). Reads of allocated pages worked
# (718 messages countable), every write allocating a free page failed
# with "database disk image is malformed". Hermes looped on
# "run hermes doctor" after every message.
#
# What this script does, in order:
#   1. Preserves evidence (never mutates the original until verified)
#   2. integrity_check on the live file (read-only open — WAL-safe)
#   3. If healthy → exit 0, nothing to do (idempotent)
#   4. If corrupt → VACUUM INTO rescue (rebuilds from valid b-tree
#      pages, discards the corrupt freelist, preserves all messages)
#   5. Verifies the rescue BEFORE swapping (integrity + row counts)
#   6. Atomic swap via rename; running gateway keeps its handle to the
#      old inode — restart the Railway service afterwards
#   7. Falls back to newest state.db.bak* if rescue fails
#
# Usage (Railway console):
#   bash recover-state-db.sh           # check + repair if needed
#   bash recover-state-db.sh --check   # check only, never modify
#
# Remote run:
#   curl -fsSL https://raw.githubusercontent.com/indrad3v4/hermes-on-railway/main/scripts/recover-state-db.sh | bash

set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DB="$HERMES_HOME/state.db"
RESCUED="$HERMES_HOME/state_rescued.db"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ ! -f "$DB" ]; then
    echo "no state.db at $DB — nothing to repair"
    exit 0
fi

echo "== state.db forensic check =="
ls -la "$DB"* 2>/dev/null || true

# Step 1: integrity check (read-only, safe alongside a running gateway)
python3 - "$DB" <<'PYEOF'
import sqlite3, sys
try:
    con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    rows = list(con.execute('PRAGMA integrity_check'))
    for r in rows[:20]:
        print('integrity:', r[0])
    if len(rows) > 20:
        print(f'... and {len(rows)-20} more corruption lines')
    sys.exit(0 if rows[0][0] == 'ok' else 1)
except Exception as e:
    print('integrity: ERROR:', e)
    sys.exit(1)
PYEOF

if [ $? -eq 0 ]; then
    echo "state.db is healthy — nothing to do"
    exit 0
fi

if [ $CHECK_ONLY -eq 1 ]; then
    echo "corruption detected (check-only mode, no changes made)"
    exit 1
fi

TS=$(date +%Y%m%d_%H%M%S)
echo ""
echo "== corruption detected — starting rescue =="

# Step 2: VACUUM INTO rescue (live snapshot, WAL-safe, no need to stop gateway)
rm -f "$RESCUED"
python3 - "$DB" "$RESCUED" <<'PYEOF'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    con = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    con.execute(f"VACUUM INTO '{dst}'")
    con.close()
except Exception as e:
    print('vacuum failed:', e)
    sys.exit(1)
# verify the rescue before we trust it
chk = sqlite3.connect(f"file:{dst}?mode=ro", uri=True)
integrity = chk.execute('PRAGMA integrity_check').fetchone()[0]
print('rescued integrity:', integrity)
if integrity != 'ok':
    sys.exit(1)
try:
    msgs = chk.execute('SELECT COUNT(*) FROM messages').fetchone()[0]
    sess = chk.execute('SELECT COUNT(*) FROM sessions').fetchone()[0]
    print(f'rescued contents: {msgs} messages, {sess} sessions')
except Exception as e:
    print('count failed:', e)
chk.close()
PYEOF

if [ $? -eq 0 ]; then
    # Step 3: atomic swap with evidence preservation
    cp "$DB" "$HERMES_HOME/state.db.corrupt-$TS"
    rm -f "$HERMES_HOME/state.db-wal" "$HERMES_HOME/state.db-shm"
    mv "$RESCUED" "$DB"
    echo ""
    echo "✓ state.db rescued in place"
    echo "  corrupt original preserved: state.db.corrupt-$TS"
    echo ""
    echo "NEXT: restart the Railway service (dashboard → Restart), then verify:"
    echo "  hermes chat -q 'reply with ok'"
    echo "  hermes chat -q 'reply with ok again'   # second write = real test"
    echo "  hermes doctor"
    exit 0
fi

# Step 4: rescue failed — fall back to newest backup
BACKUP=$(ls -t "$HERMES_HOME"/state.db.bak* 2>/dev/null | head -1)
rm -f "$RESCUED"
if [ -n "$BACKUP" ]; then
    cp "$DB" "$HERMES_HOME/state.db.corrupt-$TS"
    rm -f "$HERMES_HOME/state.db-wal" "$HERMES_HOME/state.db-shm"
    cp "$BACKUP" "$DB"
    echo "✓ restored from backup: $BACKUP"
    echo "  corrupt original preserved: state.db.corrupt-$TS"
    echo "NEXT: restart the Railway service, then hermes doctor"
    exit 0
fi

echo "✗ rescue failed and no backup found."
echo "  Corrupt file left untouched at: $DB"
echo "  Options: ask for the row-by-row copy fallback script, or accept"
echo "  fresh state (memories in ~/.hermes/memories survive regardless)."
exit 1
