#!/usr/bin/env bash
# Lightweight watcher for ROCmFPX/ROCmFPX#10 — q38rocm migration blockers.
# Prints a status line whenever run; designed for cron or manual checks.
# Exit 0 = no change, exit 1 = new activity detected.
set -euo pipefail

STATE_FILE="${HOME}/.cache/q38rocm-issue10.state"
ISSUE_URL="https://api.github.com/repos/ROCmFPX/ROCmFPX/issues/10"

mkdir -p "$(dirname "$STATE_FILE")"

SNAPSHOT=$(gh api "$ISSUE_URL" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"{d['state']}|{d['comments']}|{d['updated_at']}\")
" 2>/dev/null || echo "unreachable|0|")

if [ ! -f "$STATE_FILE" ]; then
    echo "$SNAPSHOT" > "$STATE_FILE"
    echo "[watch] baseline stored: $SNAPSHOT"
    exit 0
fi

PREV=$(cat "$STATE_FILE")
if [ "$SNAPSHOT" != "$PREV" ]; then
    echo "$SNAPSHOT" > "$STATE_FILE"
    echo "⚡ ROCmFPX#10 CHANGED: was [$PREV] now [$SNAPSHOT]"
    echo "   → https://github.com/ROCmFPX/ROCmFPX/issues/10"
    echo "   → migration checklist: docs/UPSTREAM_TRACKING.md §5"
    exit 1
fi

echo "[watch] no change: $SNAPSHOT"
exit 0
