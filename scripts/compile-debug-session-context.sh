#!/usr/bin/env bash

set -euo pipefail
MD_HASH="#"

SESSION_FILE="${1:-}"
CONTEXT_MODE="${2:-qa}"

if [ -z "$SESSION_FILE" ]; then
  echo "Usage: compile-debug-session-context.sh <session-file> [qa|uat]" >&2
  exit 1
fi

if [ ! -f "$SESSION_FILE" ]; then
  echo "Error: session file not found: $SESSION_FILE" >&2
  exit 1
fi

read_field() {
  local field="$1"
  awk -v field="$field" '
    /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
    in_fm && index($0, field ":") == 1 {
      val = substr($0, length(field) + 2)
      sub(/^[[:space:]]*/, "", val)
      print val
      exit
    }
  ' "$SESSION_FILE"
}

display_result_label() {
  local raw_value="${1:-}"
  case "$raw_value" in
    skipped_no_fix_required)
      echo $'skipped \xE2\x80\x94 no fix required'
      ;;
    *)
      echo "$raw_value"
      ;;
  esac
}

KNOWN_SECTIONS_RE='^## (Issue|Source Todo|Investigation|Plan|Implementation|QA|UAT|Remediation History)$'

extract_section() {
  local heading="$1"
  awk -v heading="$heading" -v bre="$KNOWN_SECTIONS_RE" '
    $0 ~ bre {
      if (in_section) exit
      if ($0 == "## " heading) { in_section = 1; next }
    }
    in_section { print }
  ' "$SESSION_FILE"
}

SESSION_ID=$(read_field "session_id")
TITLE=$(read_field "title")
STATUS=$(read_field "status")
QA_ROUND=$(read_field "qa_round")
QA_LAST=$(read_field "qa_last_result")
UAT_ROUND=$(read_field "uat_round")
UAT_LAST=$(read_field "uat_last_result")
QA_LAST_DISPLAY=$(display_result_label "$QA_LAST")
UAT_LAST_DISPLAY=$(display_result_label "$UAT_LAST")

ISSUE_CONTENT=$(extract_section "Issue")
SOURCE_TODO_CONTENT=$(extract_section "Source Todo")
INVESTIGATION_CONTENT=$(extract_section "Investigation")
PLAN_CONTENT=$(extract_section "Plan")
IMPL_CONTENT=$(extract_section "Implementation")
QA_CONTENT=$(extract_section "QA")
UAT_CONTENT=$(extract_section "UAT")

case "$CONTEXT_MODE" in
  qa)
    cat <<ENDCONTEXT
${MD_HASH} Debug Session QA Context

**Session:** ${SESSION_ID}
**Title:** ${TITLE}
**Status:** ${STATUS}
**QA Round:** ${QA_ROUND} (last result: ${QA_LAST_DISPLAY})

${MD_HASH}${MD_HASH} Issue Summary

${ISSUE_CONTENT:-No issue description recorded.}

${MD_HASH}${MD_HASH} Source Todo

${SOURCE_TODO_CONTENT:-No source todo recorded.}

${MD_HASH}${MD_HASH} Root Cause & Investigation

${INVESTIGATION_CONTENT:-No investigation recorded.}

${MD_HASH}${MD_HASH} Fix Plan

${PLAN_CONTENT:-No plan recorded.}

${MD_HASH}${MD_HASH} Implementation

${IMPL_CONTENT:-No implementation recorded.}
ENDCONTEXT

    if [ -n "$QA_CONTENT" ] && [ "$QA_CONTENT" != "{QA rounds are appended here by the QA workflow.}" ]; then
      echo ""
      echo "## Prior QA Rounds"
      echo ""
      echo "$QA_CONTENT"
    fi
    ;;

  uat)
    cat <<ENDCONTEXT
${MD_HASH} Debug Session UAT Context

**Session:** ${SESSION_ID}
**Title:** ${TITLE}
**Status:** ${STATUS}
**UAT Round:** ${UAT_ROUND} (last result: ${UAT_LAST_DISPLAY})

${MD_HASH}${MD_HASH} Issue Summary

${ISSUE_CONTENT:-No issue description recorded.}

${MD_HASH}${MD_HASH} Source Todo

${SOURCE_TODO_CONTENT:-No source todo recorded.}

${MD_HASH}${MD_HASH} Implementation

${IMPL_CONTENT:-No implementation recorded.}

${MD_HASH}${MD_HASH} Latest QA Result

QA round ${QA_ROUND}: ${QA_LAST_DISPLAY}
ENDCONTEXT

    if [ -n "$QA_CONTENT" ] && [ "$QA_CONTENT" != "{QA rounds are appended here by the QA workflow.}" ]; then
      echo ""
      echo "## QA Details"
      echo ""
      echo "$QA_CONTENT"
    fi

    if [ -n "$UAT_CONTENT" ] && [ "$UAT_CONTENT" != "{UAT rounds are appended here by the UAT workflow.}" ]; then
      echo ""
      echo "## Prior UAT Rounds"
      echo ""
      echo "$UAT_CONTENT"
    fi
    ;;

  *)
    echo "Error: unknown context mode '$CONTEXT_MODE'. Valid: qa, uat" >&2
    exit 1
    ;;
esac
