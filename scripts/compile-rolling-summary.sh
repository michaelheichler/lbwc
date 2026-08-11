#!/usr/bin/env bash

set -u

PHASES_DIR="${1:-.lbwc-planning/phases}"
OUTPUT_PATH="${2:-.lbwc-planning/ROLLING-CONTEXT.md}"


SUMMARY_FILES=""

if [ -d "$PHASES_DIR" ]; then
  while IFS= read -r f; do
    STATUS=$(sed -n '/^---$/,/^---$/p' "$f" 2>/dev/null | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' | tr -d '"' || true)
    if [ "$STATUS" = "complete" ] || [ "$STATUS" = "completed" ]; then
      SUMMARY_FILES="${SUMMARY_FILES}${f}
"
    fi
  done < <(find "$PHASES_DIR" -maxdepth 2 -name "*-SUMMARY.md" 2>/dev/null | sort)
fi

SUMMARY_FILES="${SUMMARY_FILES%
}"

TOTAL_COUNT=0
if [ -d "$PHASES_DIR" ]; then
  TOTAL_COUNT=$(find "$PHASES_DIR" -maxdepth 2 -name "*-SUMMARY.md" 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$TOTAL_COUNT" -le 1 ]; then
  TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"
  {
    echo "# Rolling Context"
    echo "No prior completed phases."
  } > "$TMPFILE" || { echo "WARNING: write failed" >&2; exit 0; }
  mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv failed" >&2; exit 0; }
  echo "$OUTPUT_PATH"
  exit 0
fi

if [ -z "$SUMMARY_FILES" ]; then
  TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"
  {
    echo "# Rolling Context"
    echo "No prior completed phases."
  } > "$TMPFILE" || { echo "WARNING: write failed" >&2; exit 0; }
  mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv failed" >&2; exit 0; }
  echo "$OUTPUT_PATH"
  exit 0
fi


CONTEXT_LINES=""
ACCEPTED_COUNT=0

while IFS= read -r SUMMARY_FILE; do
  [ -z "$SUMMARY_FILE" ] && continue
  [ -f "$SUMMARY_FILE" ] || continue

  FM_PHASE=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^phase:' | head -1 | sed 's/^phase:[[:space:]]*//' | tr -d '"' || true)
  FM_PLAN=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^plan:' | head -1 | sed 's/^plan:[[:space:]]*//' | tr -d '"' || true)
  FM_TITLE=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^title:' | head -1 | sed 's/^title:[[:space:]]*//' | tr -d '"' || true)
  FM_DEVIATIONS=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^deviations:' | head -1 | sed 's/^deviations:[[:space:]]*//' | tr -d '"' || true)
  FM_COMMITS=$(sed -n '/^---$/,/^---$/p' "$SUMMARY_FILE" 2>/dev/null | grep '^commit_hashes:' | head -1 | sed 's/^commit_hashes:[[:space:]]*//' | tr -d '[]"' | cut -d',' -f1 | tr -d ' ' || true)

  FM_PHASE="${FM_PHASE:-?}"
  FM_PLAN="${FM_PLAN:-?}"
  FM_TITLE="${FM_TITLE:-Untitled}"
  FM_DEVIATIONS="${FM_DEVIATIONS:-0}"
  FM_COMMITS="${FM_COMMITS:-none}"

  WHAT_BUILT=$(awk '/^## What Was Built/{found=1; count=0; next} found && /^## /{exit} found && NF>0{print; count++; if(count>=3) exit}' "$SUMMARY_FILE" 2>/dev/null | head -3 || true)
  BUILT_LINE1=$(echo "$WHAT_BUILT" | sed -n '1p' | sed 's/^[[:space:]]*//' | sed 's/^[-*] //' || true)
  [ -z "$BUILT_LINE1" ] && BUILT_LINE1="(no details)"

  FILES_LIST=$(awk '/^## Files Modified/{found=1; next} found && /^## /{exit} found && /^- /{print}' "$SUMMARY_FILE" 2>/dev/null | head -5 | sed 's/^- //' | tr '\n' ',' | sed 's/,$//' || true)
  [ -z "$FILES_LIST" ] && FILES_LIST="(none listed)"

  ENTRY="## Phase ${FM_PHASE} Plan ${FM_PLAN}: ${FM_TITLE}
Built: ${BUILT_LINE1}
Files: ${FILES_LIST}
Deviations: ${FM_DEVIATIONS}
Commit: ${FM_COMMITS}"

  if [ -n "$CONTEXT_LINES" ]; then
    CONTEXT_LINES="${CONTEXT_LINES}
${ENTRY}"
  else
    CONTEXT_LINES="$ENTRY"
  fi

  ACCEPTED_COUNT=$((ACCEPTED_COUNT + 1))
done <<EOF
$SUMMARY_FILES
EOF


TMPFILE=$(mktemp 2>/dev/null) || TMPFILE="${OUTPUT_PATH}.tmp"

{
  echo "# Rolling Context"
  echo "Compiled from ${ACCEPTED_COUNT} completed phase plan(s). Cap: 200 lines."
  echo ""
  printf '%s\n' "$CONTEXT_LINES"
} | head -200 > "$TMPFILE" 2>/dev/null || { echo "WARNING: write to tmpfile failed" >&2; exit 0; }

mv "$TMPFILE" "$OUTPUT_PATH" 2>/dev/null || { echo "WARNING: mv to output failed" >&2; exit 0; }

echo "$OUTPUT_PATH"
exit 0
