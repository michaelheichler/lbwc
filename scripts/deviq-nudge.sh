#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NUDGES_FILE="$PLUGIN_ROOT/config/deviq-nudges.json"
INDEX_FILE="$PLUGIN_ROOT/references/deviq-corpus/index.json"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
STATE_FILE="$PLANNING_DIR/deviq/.nudge-last"
COOLDOWN_SECONDS=120

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$NUDGES_FILE" ] || exit 0
[ -f "$INDEX_FILE" ] || exit 0
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

CONTENT=$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // .tool_input.new_string // "") | select(type == "string")' 2>/dev/null) || exit 0
[ -n "$CONTENT" ] || exit 0

if [ -f "$STATE_FILE" ]; then
  LAST=$(cat "$STATE_FILE" 2>/dev/null)
  case "$LAST" in
    ''|*[!0-9]*) LAST=0 ;;
  esac
  NOW=$(date +%s)
  [ $((NOW - LAST)) -ge "$COOLDOWN_SECONDS" ] || exit 0
fi

NUDGES=$(jq -c '.[]' "$NUDGES_FILE" 2>/dev/null) || exit 0
[ -n "$NUDGES" ] || exit 0

ARTICLE=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  PATTERN=$(printf '%s' "$entry" | jq -r '.pattern // ""' 2>/dev/null) || continue
  [ -n "$PATTERN" ] || continue
  if printf '%s' "$CONTENT" | grep -Eiq -- "$PATTERN" 2>/dev/null; then
    ARTICLE=$(printf '%s' "$entry" | jq -r '.article // ""' 2>/dev/null)
    [ -n "$ARTICLE" ] && break
  fi
done <<< "$NUDGES"

[ -n "$ARTICLE" ] || exit 0

TITLE=$(jq -r --arg id "$ARTICLE" '.[] | select(.id == $id) | .title' "$INDEX_FILE" 2>/dev/null)
[ -n "$TITLE" ] || exit 0

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || exit 0
date +%s > "$STATE_FILE" 2>/dev/null

CONTEXT="DevIQ: this resembles $TITLE ($ARTICLE). Run scripts/deviq-lookup.sh --show $ARTICLE for the practice."
jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}' 2>/dev/null

exit 0
