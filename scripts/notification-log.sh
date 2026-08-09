#!/bin/bash
set -u

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

if [ ! -d "$PLANNING_DIR" ]; then
  exit 0
fi

INPUT=$(cat)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null)
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' 2>/dev/null)
TITLE=$(echo "$INPUT" | jq -r '.title // ""' 2>/dev/null)

jq -n \
  --arg ts "$TIMESTAMP" \
  --arg type "$TYPE" \
  --arg title "$TITLE" \
  --arg message "$MESSAGE" \
  '{timestamp: $ts, type: $type, title: $title, message: $message}' \
  >> "$PLANNING_DIR/.notification-log.jsonl" 2>/dev/null

exit 0
