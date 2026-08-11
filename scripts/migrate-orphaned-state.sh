#!/usr/bin/env bash
set -euo pipefail


PLANNING_DIR="${1:-.lbwc-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$PLANNING_DIR" ]]; then
  exit 0
fi

if [[ -f "$PLANNING_DIR/STATE.md" ]]; then
  exit 0
fi

latest_state=""
latest_mtime=-1
for f in "$PLANNING_DIR"/milestones/*/STATE.md; do
  [ -f "$f" ] || continue
  mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
  if [[ "$mtime" -gt "$latest_mtime" ]]; then
    latest_mtime="$mtime"
    latest_state="$f"
  fi
done

if [[ -z "$latest_state" ]]; then
  exit 0
fi

project_name=$(grep -m1 '^\*\*Project:\*\*' "$latest_state" 2>/dev/null | sed 's/\*\*Project:\*\* *//' || echo "Unknown")

bash "$SCRIPT_DIR/persist-state-after-ship.sh" \
  "$latest_state" "$PLANNING_DIR/STATE.md" "$project_name" 2>/dev/null || true

exit 0
