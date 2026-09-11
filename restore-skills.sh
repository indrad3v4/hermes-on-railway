#!/bin/bash
set -euo pipefail

# Restore repository-managed Hermes assets into the persistent HERMES_HOME.
#
# Same contract as restore-firebrowsing.sh: the repo is the source of truth for
# the files it manages; anything else on the volume is left alone.
#
#   /opt/hermes-skills/*        -> $HERMES_HOME/skills/*
#   /opt/hermes-agent-scripts/* -> $HERMES_HOME/scripts/*
#
# Binary/large corpora (book OCR text) are deliberately NOT in the image — they
# stay on the volume (see the repo README / token-economics report).

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
SKILLS_SRC="/opt/hermes-skills"
SCRIPTS_SRC="/opt/hermes-agent-scripts"

restore_one() {
    local src="$1" dst="$2" mode="${3:-0644}"
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
    install -m "$mode" "$src" "$dst"
    echo "   restored: $dst"
}

restore_tree() {
    local src="$1" dst_root="$2" default_mode="$3"
    [ -d "$src" ] || return 0
    while IFS= read -r -d '' f; do
        local rel="${f#"$src"/}" mode="$default_mode"
        case "$f" in
            *.sh|*.py) mode="0755" ;;
        esac
        restore_one "$f" "$dst_root/$rel" "$mode"
    done < <(find "$src" -type f -print0)
}

if [ ! -d "$SKILLS_SRC" ] && [ ! -d "$SCRIPTS_SRC" ]; then
    echo "→ Repo skills/scripts not present in image; skipping"
    exit 0
fi

echo "→ Restoring repository-managed skills..."
restore_tree "$SKILLS_SRC" "$HERMES_HOME/skills" "0644"

echo "→ Restoring repository-managed agent scripts..."
restore_tree "$SCRIPTS_SRC" "$HERMES_HOME/scripts" "0644"
