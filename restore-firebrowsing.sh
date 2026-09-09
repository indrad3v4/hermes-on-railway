#!/bin/bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
SRC="/opt/firebrowsing"

# Restore only repository-managed Firebrowsing assets. Existing volume files are
# backed up once before replacement so a changed image cannot silently destroy
# a live customization. Matching files are left untouched.
restore_one() {
    local src="$1" dst="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            echo "   unchanged: $dst"
            return 0
        fi
        local ts backup
        ts="$(date +%Y%m%d_%H%M%S)"
        backup="${dst}.pre-redeploy-${ts}"
        cp -a "$dst" "$backup"
        echo "   backed up existing: $backup"
    fi
    install -m 0644 "$src" "$dst"
    echo "   restored: $dst"
}

if [ ! -d "$SRC" ]; then
    echo "→ Firebrowsing assets not present in image; skipping"
    exit 0
fi

echo "→ Restoring repository-managed Firebrowsing assets..."
restore_one "$SRC/SKILL.md" "$HERMES_HOME/skills/web/firebrowsing/SKILL.md"
restore_one "$SRC/scripts/browser_helpers.py" "$HERMES_HOME/scripts/browser_helpers.py"
restore_one "$SRC/scripts/firecrawl_local.py" "$HERMES_HOME/scripts/firecrawl_local.py"
restore_one "$SRC/research/improve-firebrowsing-deep-research-prompt.md" "$HERMES_HOME/skills/web/firebrowsing/research/improve-firebrowsing-deep-research-prompt.md"
