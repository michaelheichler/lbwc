#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  . "$SCRIPT_DIR/summary-utils.sh"
else
  count_complete_summaries() { echo 0; }
  count_terminal_summaries() { echo 0; }
fi

count_phase_plans() {
  local dir="$1" count=0 f
  for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
    [ -f "$f" ] && count=$((count + 1))
  done
  echo "$count"
}

extract_verification_result() {
  local f="$1" in_fm=false line
  [ -f "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" = false ]; then in_fm=true; continue; else break; fi
    fi
    if [ "$in_fm" = true ] && [[ "$line" =~ ^result:[[:space:]]*(.*) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}" | tr -d '[:space:]'
      return 0
    fi
  done < "$f"
}

find_phase_dir() {
  local changed_path="$1" dir parent parent_base
  dir=$(dirname "$changed_path")
  parent=$(dirname "$dir")
  parent_base=$(basename "$parent")
  [ "$parent_base" = "phases" ] || { echo ""; return 0; }
  echo "$dir"
}

is_tracked_artifact() {
  case "$1" in
    */phases/[0-9]*-*/*-PLAN.md|*/phases/[0-9]*-*/PLAN.md|\
    */phases/[0-9]*-*/*-SUMMARY.md|*/phases/[0-9]*-*/SUMMARY.md|\
    */phases/[0-9]*-*/*-VERIFICATION.md|*/phases/[0-9]*-*/VERIFICATION.md)
      return 0
      ;;
    *) return 1 ;;
  esac
}

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -n "$FILE_PATH" ] || exit 0
is_tracked_artifact "$FILE_PATH" || exit 0
[ -f "$FILE_PATH" ] || exit 0

PHASE_DIR=$(find_phase_dir "$FILE_PATH")
[ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ] || exit 0

PLANNING_ROOT=$(dirname "$(dirname "$PHASE_DIR")")
STATE_FILE="$PLANNING_ROOT/STATE.md"
[ -f "$STATE_FILE" ] || exit 0

ARTIFACT_PHASE_NUM=$(basename "$PHASE_DIR" | sed 's/^\([0-9]*\).*/\1/' | sed 's/^0*//')
[ -n "$ARTIFACT_PHASE_NUM" ] || exit 0

STATE_PHASE_NUM=$(grep -m1 '^Phase:' "$STATE_FILE" 2>/dev/null | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | sed 's/^0*//')
[ "$STATE_PHASE_NUM" = "$ARTIFACT_PHASE_NUM" ] || exit 0

PLAN_COUNT=$(count_phase_plans "$PHASE_DIR")
[ "$PLAN_COUNT" -gt 0 ] 2>/dev/null || exit 0
TERMINAL_COUNT=$(count_terminal_summaries "$PHASE_DIR" 2>/dev/null || echo 0)
COMPLETE_COUNT=$(count_complete_summaries "$PHASE_DIR" 2>/dev/null || echo 0)
PROGRESS_PCT=$((COMPLETE_COUNT * 100 / PLAN_COUNT))

TMP="${STATE_FILE}.tmp.$$.${RANDOM:-0}"
sed \
  -e "s|^Plans: .*|Plans: ${TERMINAL_COUNT}/${PLAN_COUNT}|" \
  -e "s|^Progress: .*|Progress: ${PROGRESS_PCT}%|" \
  "$STATE_FILE" > "$TMP" 2>/dev/null && [ -s "$TMP" ] && mv "$TMP" "$STATE_FILE" || rm -f "$TMP"

case "$FILE_PATH" in
  */phases/[0-9]*-*/*-VERIFICATION.md|*/phases/[0-9]*-*/VERIFICATION.md)
    RESULT=$(extract_verification_result "$FILE_PATH" | tr '[:lower:]' '[:upper:]')
    case "$RESULT" in
      PASS) NEW_STATUS="complete" ;;
      FAIL|PARTIAL) NEW_STATUS="needs_remediation" ;;
      *) NEW_STATUS="" ;;
    esac
    if [ -n "$NEW_STATUS" ]; then
      TMP="${STATE_FILE}.tmp.$$.${RANDOM:-0}"
      sed "s|^Status: .*|Status: ${NEW_STATUS}|" "$STATE_FILE" > "$TMP" 2>/dev/null && \
        [ -s "$TMP" ] && mv "$TMP" "$STATE_FILE" || rm -f "$TMP"
    fi
    ;;
esac

exit 0
