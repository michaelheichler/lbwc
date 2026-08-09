#!/bin/bash
set -u


CMD="${1:-}"
AGENT="${2:-}"
WORKTREE_PATH="${3:-}"

if [ -z "$CMD" ] || [ -z "$AGENT" ]; then
  exit 0
fi

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
STORAGE_DIR="$PLANNING_DIR/.agent-worktrees"
MAP_FILE="${STORAGE_DIR}/${AGENT}.json"

case "$CMD" in
  set)
    if [ -z "$WORKTREE_PATH" ]; then
      exit 0
    fi
    mkdir -p "$STORAGE_DIR"
    CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{\n  "agent": "%s",\n  "worktree_path": "%s",\n  "created_at": "%s"\n}\n' \
      "$AGENT" "$WORKTREE_PATH" "$CREATED_AT" > "${MAP_FILE}.tmp"
    mv "${MAP_FILE}.tmp" "$MAP_FILE"
    exit 0
    ;;

  get)
    if [ ! -f "$MAP_FILE" ]; then
      exit 0
    fi
    jq -r '.worktree_path // ""' "$MAP_FILE" 2>/dev/null || true
    exit 0
    ;;

  clear)
    rm -f "$MAP_FILE" 2>/dev/null || true
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
