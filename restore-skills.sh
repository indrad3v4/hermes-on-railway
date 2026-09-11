#!/bin/bash
set -euo pipefail

# Restore repository-managed Hermes skills into the persistent HERMES_HOME.
#
# Same contract as restore-firebrowsing.sh: the repo is the source of truth for
# skill FILES, and a changed image backs up the live copy before replacing it, so
# a redeploy can never silently destroy a live customization.
#
# The book corpora (skills/*/*/corpus/*) are deliberately NOT shipped in the image
# — they are large and contain third-party book text. They live on the volume only.

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
SRC="/opt/hermes-skills"

restore_one() {
    local src="$1" dst="$2" mode="0644"
    [ -f "$src" ] || return 0
    case "$src" in *.py|*.sh) mode="0755" ;; esac
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
    install -m "$mode" "$src" "$dst"
    echo "   restored: $dst"
}

if [ ! -d "$SRC" ]; then
    echo "→ Repo skills not present in image; skipping"
    exit 0
fi

echo "→ Restoring repository-managed skills..."
while IFS= read -r -d '' f; do
    rel="${f#"$SRC"/}"
    restore_one "$f" "$HERMES_HOME/skills/$rel"
done < <(find "$SRC" -type f -print0)
