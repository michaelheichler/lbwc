#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

[ -d "$PLANNING_DIR" ] || exit 0

[ -t 0 ] || { while IFS= read -r -t 2 _ss_line; do :; done; }

rm -f "$PLANNING_DIR/.context-usage" 2>/dev/null || true

WORKTREES_DIR=".lbwc-worktrees"
if [ -d "$WORKTREES_DIR" ] && [ -f "$SCRIPT_DIR/worktree-cleanup.sh" ]; then
  NOW=$(date +%s 2>/dev/null || echo 0)
  STALE_SECS=7200
  for wt_dir in "$WORKTREES_DIR"/*/; do
    [ -d "$wt_dir" ] || continue
    if [ "$(uname)" = "Darwin" ]; then
      WT_MTIME=$(stat -f %m "$wt_dir" 2>/dev/null || echo 0)
    else
      WT_MTIME=$(stat -c %Y "$wt_dir" 2>/dev/null || echo 0)
    fi
    WT_AGE=$((NOW - WT_MTIME))
    if [ "$WT_AGE" -gt "$STALE_SECS" ]; then
      WT_NAME=$(basename "$wt_dir")
      WT_PHASE=$(echo "$WT_NAME" | cut -d'-' -f1)
      WT_PLAN=$(echo "$WT_NAME" | cut -d'-' -f2)
      LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPT_DIR/worktree-cleanup.sh" "$WT_PHASE" "$WT_PLAN" >/dev/null 2>&1 || true
    fi
  done
fi

exit 0
