#!/usr/bin/env bash

set -euo pipefail

UAT_FILE="${1:?Usage: finalize-uat-status.sh <uat-file-path>}"
if ! SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P 2>/dev/null)"; then
  SCRIPT_DIR=$(pwd -P)
fi

if [ ! -f "$UAT_FILE" ]; then
  echo "Error: UAT file not found: $UAT_FILE" >&2
  exit 1
fi

if ! awk '
  NR == 1 {
    if ($0 !~ /^---[[:space:]]*$/) exit 1
    in_fm = 1
    next
  }
  in_fm && /^---[[:space:]]*$/ { found = 1; exit 0 }
  END { if (!found) exit 1 }
' "$UAT_FILE"; then
  echo "finalize-uat-status: missing YAML frontmatter block" >&2
  exit 1
fi

RESULTS=$(awk '
  /^### (P[0-9]+(-T[0-9]+)?|PR[0-9]+-T[0-9]+|D[0-9]+)(:|[[:space:]])/ {
    if (in_test && saw_result == 0) print "__missing__"
    in_test = 1
    saw_result = 0
    next
  }
  in_test && /^- \*\*Result:\*\*/ {
    saw_result = 1
    val = $0
    sub(/^- \*\*Result:\*\*[[:space:]]*/, "", val)
    gsub(/[[:space:]]+$/, "", val)
    gsub(/^[^a-zA-Z{]+/, "", val)
    gsub(/[^a-zA-Z}]+$/, "", val)
    upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lower = "abcdefghijklmnopqrstuvwxyz"
    lval = ""
    for (i = 1; i <= length(val); i++) {
      c = substr(val, i, 1)
      pos = index(upper, c)
      if (pos > 0) c = substr(lower, pos, 1)
      lval = lval c
    }
    val = lval
    if (val == "" || val == "{pass|skip|issue}") {
      print "empty"
    } else if (val ~ /^pass/) {
      print "pass"
    } else if (val ~ /^skip/) {
      print "skip"
    } else if (val ~ /^issue/ || val ~ /^fail/ || val ~ /^partial/) {
      print "issue"
    } else {
      print "__unknown__:" val
    }
    next
  }
  /^### / {
    if (in_test && saw_result == 0) print "__missing__"
    in_test = 0
    saw_result = 0
  }
  END {
    if (in_test && saw_result == 0) print "__missing__"
  }
' "$UAT_FILE")

PASSED=0
SKIPPED=0
ISSUES=0
EMPTY=0
TOTAL=0
UNKNOWN=0
MISSING=0

while IFS= read -r result; do
  [ -z "$result" ] && continue
  case "$result" in
    __unknown__:*)
      printf 'finalize-uat-status: unrecognized Result value: %s\n' "${result#__unknown__:}" >&2
      UNKNOWN=$((UNKNOWN + 1))
      continue
      ;;
    __missing__)
      printf 'finalize-uat-status: missing Result line in test block\n' >&2
      MISSING=$((MISSING + 1))
      continue
      ;;
  esac
  TOTAL=$((TOTAL + 1))
  case "$result" in
    pass)  PASSED=$((PASSED + 1)) ;;
    skip)  SKIPPED=$((SKIPPED + 1)) ;;
    issue) ISSUES=$((ISSUES + 1)) ;;
    empty) EMPTY=$((EMPTY + 1)) ;;
  esac
done <<< "$RESULTS"

if [ "$UNKNOWN" -gt 0 ] || [ "$MISSING" -gt 0 ]; then
  echo "finalize-uat-status: refusing to rewrite frontmatter due to malformed Result values" >&2
  exit 1
fi

if [ "$TOTAL" -eq 0 ] || [ "$EMPTY" -gt 0 ]; then
  STATUS="in_progress"
elif [ "$ISSUES" -gt 0 ]; then
  STATUS="issues_found"
else
  STATUS="complete"
fi

if [ "$STATUS" = "in_progress" ]; then
  TODAY=""
else
  TODAY=$(date +%Y-%m-%d)
fi

awk -v status="$STATUS" -v completed="$TODAY" -v passed="$PASSED" \
    -v skipped="$SKIPPED" -v issues="$ISSUES" -v total="$TOTAL" '
  BEGIN {
    in_fm = 0; fm_done = 0
    saw_status = 0; saw_completed = 0; saw_passed = 0
    saw_skipped = 0; saw_issues = 0; saw_total = 0
  }
  NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; print; next }
  in_fm && /^---[[:space:]]*$/ {
    if (!saw_status) {
      printf "status: %s\n", status
    }
    if (!saw_completed && completed != "") {
      printf "completed: %s\n", completed
    } else if (!saw_completed) {
      printf "completed:\n"
    }
    if (!saw_passed) {
      printf "passed: %s\n", passed
    }
    if (!saw_skipped) {
      printf "skipped: %s\n", skipped
    }
    if (!saw_issues) {
      printf "issues: %s\n", issues
    }
    if (!saw_total) {
      printf "total_tests: %s\n", total
    }
    in_fm = 0; fm_done = 1; print; next
  }
  in_fm {
    if ($0 ~ /^status[[:space:]]*:/) {
      saw_status = 1
      printf "status: %s\n", status
    } else if ($0 ~ /^completed[[:space:]]*:/) {
      saw_completed = 1
      if (completed != "") printf "completed: %s\n", completed
      else printf "completed:\n"  # clear stale date for in_progress
    } else if ($0 ~ /^passed[[:space:]]*:/) {
      saw_passed = 1
      printf "passed: %s\n", passed
    } else if ($0 ~ /^skipped[[:space:]]*:/) {
      saw_skipped = 1
      printf "skipped: %s\n", skipped
    } else if ($0 ~ /^issues[[:space:]]*:/) {
      saw_issues = 1
      printf "issues: %s\n", issues
    } else if ($0 ~ /^total_tests[[:space:]]*:/) {
      saw_total = 1
      printf "total_tests: %s\n", total
    } else {
      print
    }
    next
  }
  { print }
' "$UAT_FILE" > "${UAT_FILE}.tmp" && mv "${UAT_FILE}.tmp" "$UAT_FILE"

if [ -f "$SCRIPT_DIR/reconcile-state-md.sh" ]; then
  bash "$SCRIPT_DIR/reconcile-state-md.sh" --changed "$UAT_FILE" >/dev/null 2>&1 || true
fi

echo "status=${STATUS} passed=${PASSED} skipped=${SKIPPED} issues=${ISSUES} total=${TOTAL}"
