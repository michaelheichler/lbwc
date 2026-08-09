#!/usr/bin/env bash
set -euo pipefail

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

if [[ -f "$PLANNING_DIR/.compaction-marker" ]]; then
  _cm_ts=$(cat "$PLANNING_DIR/.compaction-marker" 2>/dev/null || echo 0)
  _cm_now=$(date +%s 2>/dev/null || echo 0)
  if (( _cm_now - _cm_ts < 60 )); then
    exit 0
  fi
fi

META="$PLANNING_DIR/codebase/META.md"

IS_HOOK=false
[ -t 1 ] || IS_HOOK=true

_diag() { if [[ "$IS_HOOK" == true ]]; then echo "$@" >&2; else echo "$@"; fi; }

if [[ ! -f "$META" ]]; then
  _diag "status: no_map"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  _diag "status: no_git"
  exit 0
fi

git_hash=$(grep '^git_hash:' "$META" | awk '{print $2}' || true)
file_count=$(grep '^file_count:' "$META" | awk '{print $2}' || true)
mapped_at=$(grep '^mapped_at:' "$META" | awk '{print $2}' || true)

if [[ -z "$git_hash" || -z "$mapped_at" || ! "$file_count" =~ ^[1-9][0-9]*$ ]]; then
  _diag "status: no_map"
  exit 0
fi

if ! git cat-file -e "$git_hash" 2>/dev/null; then
  _diag "status: stale"
  _diag "staleness: 100%"
  _diag "changed: unknown"
  _diag "total: $file_count"
  _diag "since: $mapped_at"
  if [[ "$IS_HOOK" == true ]]; then
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Codebase map is stale (100% files changed). Run /lbwc:map --incremental to refresh.\"}}"
  fi
  exit 0
fi

changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')

staleness=$(( changed * 100 / file_count ))

if [[ "$staleness" -gt 30 ]]; then
  status="stale"
else
  status="fresh"
fi

_diag "status: $status"
_diag "staleness: ${staleness}%"
_diag "changed: $changed"
_diag "total: $file_count"
_diag "since: $mapped_at"

if [[ "$status" == "stale" ]] && [[ "$IS_HOOK" == true ]]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Codebase map is stale (${staleness}% files changed). Run /lbwc:map --incremental to refresh.\"}}"
fi
