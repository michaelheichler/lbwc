#!/bin/bash
set -u

HOOK_EVENT="${1:-PostToolUse}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_OUTPUT_GUARD="$SCRIPT_DIR/lib/hook-output-guard.sh"
if [ -f "$HOOK_OUTPUT_GUARD" ]; then
  source "$HOOK_OUTPUT_GUARD"
fi
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // ""')

hook_event_allows_output() {
  local event_name="$1"
  if type should_emit_hook_output >/dev/null 2>&1; then
    should_emit_hook_output "$event_name"
    return $?
  fi
  [ "$event_name" = "PostToolUse" ]
}

emit_posttool_context() {
  local context="$1"
  [ "$HOOK_EVENT" = "PostToolUse" ] || return 0
  hook_event_allows_output "$HOOK_EVENT" || return 0
  jq -n --arg context "$context" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $context
    }
  }'
}

if ! echo "$FILE_PATH" | grep -qE '\.lbwc-planning/.*SUMMARY\.md$'; then
  exit 0
fi

[ ! -f "$FILE_PATH" ] && exit 0

MISSING=""

if ! head -1 "$FILE_PATH" | grep -q '^---$'; then
  MISSING="Missing YAML frontmatter. "
fi

_VS_STATUS=$(sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$FILE_PATH" 2>/dev/null | head -1 | tr -d '[:space:]')
if [ -n "$_VS_STATUS" ]; then
  case "$_VS_STATUS" in
    complete|partial|failed) ;;
    completed)
      MISSING="${MISSING}Status 'completed' should be 'complete' (canonical form). "
      ;;
    pending|in_progress|in-progress)
      MISSING="${MISSING}Invalid status '${_VS_STATUS}' -- SUMMARY.md must only be created at plan completion (status: complete|partial|failed). "
      ;;
    *)
      MISSING="${MISSING}Invalid status '${_VS_STATUS}' (must be complete|partial|failed). "
      ;;
  esac
else
  if head -1 "$FILE_PATH" | grep -q '^---$'; then
    MISSING="${MISSING}Missing 'status' field in frontmatter (must be complete|partial|failed). "
  fi
fi

if ! grep -q "## What Was Built" "$FILE_PATH"; then
  MISSING="${MISSING}Missing '## What Was Built'. "
fi

if ! grep -q "## Files Modified" "$FILE_PATH"; then
  MISSING="${MISSING}Missing '## Files Modified'. "
fi

case "$(basename "$FILE_PATH")" in
  *REMEDIATION*|R[0-9]*-SUMMARY.md) ;;
  *)
PLAN_PATH=$(echo "$FILE_PATH" | sed 's/SUMMARY\.md$/PLAN.md/')
if [ -f "$PLAN_PATH" ]; then
  _VS_HAS_MH=""
  if grep -qE '^must_haves:[[:space:]]*\[[^]]*[^][:space:]][^]]*\]' "$PLAN_PATH" 2>/dev/null; then
    _VS_HAS_MH=true
  elif sed -n '/^must_haves:/,/^[^ ]/p' "$PLAN_PATH" 2>/dev/null | grep '^ ' | grep -qE '^ *- |: *\[[^]]*[^][:space:]][^]]*\]'; then
    _VS_HAS_MH=true
  fi
  if [ "$_VS_HAS_MH" = true ]; then
    if ! sed -n '/^---$/,/^---$/p' "$FILE_PATH" 2>/dev/null | grep -q '^ac_results:'; then
      MISSING="${MISSING}Missing 'ac_results' in frontmatter (plan has must_haves). "
    else
      _VS_VERDICTS=$(sed -n '/^---$/,/^---$/{ /^ *verdict:/{ s/^ *verdict:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$FILE_PATH" 2>/dev/null)
      for _VS_V in $_VS_VERDICTS; do  # unquoted intentional: verdicts are single-word enums
        case "$_VS_V" in
          pass|fail|partial) ;;
          *) MISSING="${MISSING}Invalid ac_results verdict '${_VS_V}' (must be pass/fail/partial). " ;;
        esac
      done
    fi
  fi
fi
  ;;
esac

if [ -n "$MISSING" ]; then
  emit_posttool_context "SUMMARY validation: $MISSING"
fi

exit 0
