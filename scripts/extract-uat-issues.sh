#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISSUE_PARSER="$SCRIPT_DIR/parse-uat-issues.awk"
ROUND_ID_PARSER="$SCRIPT_DIR/extract-round-issue-ids.awk"

if [ ! -f "$ISSUE_PARSER" ] || [ ! -f "$ROUND_ID_PARSER" ]; then
  echo "uat_extract_error=true" >&2
  exit 1
fi

if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  source "$SCRIPT_DIR/uat-utils.sh"
fi

INPUT_PATH="${1:?Usage: extract-uat-issues.sh <phase-dir|uat-file>}"
PHASE_DIR=""
UAT_FILE=""

if [ -d "$INPUT_PATH" ]; then
  PHASE_DIR="$INPUT_PATH"
elif [ -f "$INPUT_PATH" ]; then
  UAT_FILE="$INPUT_PATH"
  case "$INPUT_PATH" in
    */remediation/uat/round-*/R*-UAT.md)
      PHASE_DIR=$(dirname "$(dirname "$(dirname "$(dirname "$INPUT_PATH")")")")
      ;;
    *)
      PHASE_DIR=$(dirname "$INPUT_PATH")
      ;;
  esac
else
  echo "uat_extract_error=true" >&2
  exit 1
fi

if [ -z "$UAT_FILE" ]; then
  if type current_uat &>/dev/null; then
    UAT_FILE=$(current_uat "$PHASE_DIR")
  elif type latest_non_source_uat &>/dev/null; then
    UAT_FILE=$(latest_non_source_uat "$PHASE_DIR")
  else
    UAT_FILE=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
  fi
fi

if [ -z "$UAT_FILE" ] || [ ! -f "$UAT_FILE" ]; then
  echo "uat_extract_error=no_uat_file"
  exit 0
fi

PHASE_NUM=$(basename "$PHASE_DIR" | sed 's/[^0-9].*//')
if [ -z "$PHASE_NUM" ]; then
  PHASE_NUM=$(basename "$UAT_FILE" | sed 's/[^0-9].*//')
fi
if [ -z "$PHASE_NUM" ]; then
  PHASE_NUM=$(awk '
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      lower = tolower($0)
      if (lower ~ /^phase:[[:space:]]*[0-9]+[[:space:]]*$/) {
        value = $0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$UAT_FILE" 2>/dev/null || true)
fi

if type extract_status_value &>/dev/null; then
  STATUS=$(extract_status_value "$UAT_FILE")
else
  STATUS=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*status[[:space:]]*:/ {
      val=$0; sub(/^[^:]*:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)
      print tolower(val); exit
    }
  ' "$UAT_FILE" 2>/dev/null || true)
  if type normalize_uat_status &>/dev/null; then
    STATUS=$(normalize_uat_status "$STATUS")
  else
    case "$STATUS" in
      all_pass|passed|pass|all_passed|verified|no_issues) STATUS="complete" ;;
    esac
  fi
fi

if [ "$STATUS" != "issues_found" ]; then
  echo "uat_extract_status=${STATUS:-unknown}"
  exit 0
fi

ISSUES_TMP="$(mktemp "${TMPDIR:-/tmp}/lbwc-uat-issues.XXXXXX")"
ROUND_IDS_TMP="$(mktemp "${TMPDIR:-/tmp}/lbwc-uat-round-ids.XXXXXX")"
trap 'rm -f "$ISSUES_TMP" "$ROUND_IDS_TMP"' EXIT

awk -f "$ISSUE_PARSER" "$UAT_FILE" > "$ISSUES_TMP"

ISSUE_COUNT=$(wc -l < "$ISSUES_TMP" | tr -d ' ')

if [ "$ISSUE_COUNT" -eq 0 ]; then
  FM_ISSUES=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^[[:space:]]*issues[[:space:]]*:/ {
      val=$0; sub(/^[^:]*:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)
      print val; exit
    }
  ' "$UAT_FILE" 2>/dev/null || true)
  FM_ISSUES=$(printf '%s' "$FM_ISSUES" | tr -d '[:space:]')
  if [ -n "$FM_ISSUES" ] && [ "$FM_ISSUES" != "0" ]; then
    echo "uat_extract_error=inconsistent_status frontmatter_issues=${FM_ISSUES} parsed_issues=0" >&2
    echo "uat_extract_error=true"
    exit 0
  fi
fi

if type count_uat_rounds &>/dev/null; then
  MAX_ARCHIVED=$(count_uat_rounds "$PHASE_DIR" "$PHASE_NUM")
else
  MAX_ARCHIVED=0
fi
CURRENT_ROUND=""
case "$UAT_FILE" in
  */remediation/uat/round-*/R*-UAT.md)
    CURRENT_ROUND=$(basename "$UAT_FILE" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    CURRENT_ROUND="${CURRENT_ROUND:-0}"
    ;;
esac
if [ -z "$CURRENT_ROUND" ] || ! echo "$CURRENT_ROUND" | grep -qE '^[0-9]+$'; then
  CURRENT_ROUND=$((MAX_ARCHIVED + 1))
fi

: > "$ROUND_IDS_TMP"
if [ "$MAX_ARCHIVED" -gt 0 ]; then
  for rf in "${PHASE_DIR%/}/${PHASE_NUM}"-UAT-round-*.md; do
    [ -f "$rf" ] || continue
    [ "$rf" = "$UAT_FILE" ] && continue
    ROUND_NUM=$(basename "$rf" | sed "s/^${PHASE_NUM}-UAT-round-0*\\([0-9]*\\)\\.md$/\\1/")
    if [ -n "$ROUND_NUM" ] && echo "$ROUND_NUM" | grep -qE '^[0-9]+$'; then
      awk -f "$ROUND_ID_PARSER" "$rf" | while IFS= read -r rid; do
        [ -n "$rid" ] && printf '%s %s\n' "$rid" "$ROUND_NUM"
      done
    fi
  done >> "$ROUND_IDS_TMP"
  for rf in "${PHASE_DIR%/}"/remediation/uat/round-*/R*-UAT.md; do
    [ -f "$rf" ] || continue
    [ "$rf" = "$UAT_FILE" ] && continue
    ROUND_NUM=$(basename "$rf" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    if [ -n "$ROUND_NUM" ] && echo "$ROUND_NUM" | grep -qE '^[0-9]+$'; then
      awk -f "$ROUND_ID_PARSER" "$rf" | while IFS= read -r rid; do
        [ -n "$rid" ] && printf '%s %s\n' "$rid" "$ROUND_NUM"
      done
    fi
  done >> "$ROUND_IDS_TMP"
fi

echo "uat_phase=${PHASE_NUM} uat_issues_total=${ISSUE_COUNT} uat_round=${CURRENT_ROUND} uat_file=$(basename "$UAT_FILE")"

while IFS='|' read -r id severity desc; do
  [ -z "$id" ] && continue
  PAST_ROUNDS=""
  if [ -s "$ROUND_IDS_TMP" ]; then
    PAST_ROUNDS=$(grep "^${id} " "$ROUND_IDS_TMP" | awk '{print $2}' | sort -n | tr '\n' ',' | sed 's/,$//' || true)
  fi
  if [ -n "$PAST_ROUNDS" ]; then
    FAILED_IN_ROUNDS="${PAST_ROUNDS},${CURRENT_ROUND}"
  else
    FAILED_IN_ROUNDS="${CURRENT_ROUND}"
  fi
  printf '%s|%s|%s|%s\n' "$id" "$severity" "$desc" "$FAILED_IN_ROUNDS"
done < "$ISSUES_TMP"
