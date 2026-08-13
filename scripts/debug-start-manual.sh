#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PLANNING_DIR="${1:-}"
DETAIL_STATUS="${DETAIL_STATUS:-none}"
DETAIL_RESULT_JSON="${DETAIL_RESULT_JSON:-}"
MANUAL_REF="${REF_HASH:-none}"

fail() {
  printf 'debug-start-manual: %s\n' "$1" >&2
  exit 1
}

[ -n "$PLANNING_DIR" ] || fail 'planning directory is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

case "$DETAIL_STATUS" in
  ok|not_found|error|none) ;;
  *) fail "invalid detail status: $DETAIL_STATUS" ;;
esac

ARGUMENTS=$(cat) || fail 'could not read debug arguments'
BUG_DESC=$(
  printf '%s' "$ARGUMENTS" |
    sed -E '
      s/[[:space:]]*\(ref:[^)]+\)//g
      s/(^|[[:space:]])--(competing|parallel|serial)([[:space:]]|$)/ /g
      s/^[[:space:]]+//
      s/[[:space:]]+$//
      s/[[:space:]]+/ /g
    '
) || fail 'could not normalize the bug description'

MANUAL_DETAIL_CONTEXT=""
MANUAL_DETAIL_FILES='[]'
if [ "$DETAIL_STATUS" = "ok" ]; then
  [ -n "$DETAIL_RESULT_JSON" ] || fail 'detail status ok requires DETAIL_RESULT_JSON'
  DETAIL_JSON=$(
    printf '%s' "$DETAIL_RESULT_JSON" |
      jq -ce '
        select(.status == "ok")
        | {
            context: (.detail.context // ""),
            files: (
              (.detail.files // [])
              | if type == "array" and all(.[]; type == "string")
                then .
                else error("detail.files must be an array of strings")
                end
            )
          }
      '
  ) || fail 'DETAIL_RESULT_JSON is invalid or does not have status ok'
  MANUAL_DETAIL_CONTEXT=$(jq -r '.context' <<< "$DETAIL_JSON")
  MANUAL_DETAIL_FILES=$(jq -c '.files' <<< "$DETAIL_JSON")
fi

if [ -z "$BUG_DESC" ] && [ "$DETAIL_STATUS" != "ok" ]; then
  fail 'bug description is empty after removing routing metadata'
fi

SLUG=$(
  printf '%s' "$BUG_DESC" |
    LC_ALL=C tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' |
    cut -c 1-50 |
    sed -E 's/-+$//'
) || fail 'could not create the debug-session slug'
[ -n "$SLUG" ] || SLUG="debug"

SOURCE_TODO_JSON=$(
  jq -cn \
    --arg mode "source-todo" \
    --arg text "$BUG_DESC" \
    --arg raw_line "none" \
    --arg ref "$MANUAL_REF" \
    --arg detail_status "$DETAIL_STATUS" \
    --argjson related_files "$MANUAL_DETAIL_FILES" \
    --arg detail_context "$MANUAL_DETAIL_CONTEXT" \
    '{mode:$mode,text:$text,raw_line:$raw_line,ref:$ref,detail_status:$detail_status,related_files:$related_files,detail_context:$detail_context}'
) || fail 'could not build source-todo JSON'

SESSION_ASSIGNMENTS=$(
  printf '%s' "$SOURCE_TODO_JSON" |
    bash "$SCRIPT_DIR/debug-session-state.sh" start-with-source-todo "$PLANNING_DIR" "$SLUG"
) || fail 'could not create the debug session'

printf 'BUG_DESC=%q\n' "$BUG_DESC"
printf 'SLUG=%q\n' "$SLUG"
printf 'MANUAL_REF=%q\n' "$MANUAL_REF"
printf 'MANUAL_DETAIL_CONTEXT=%q\n' "$MANUAL_DETAIL_CONTEXT"
printf 'MANUAL_DETAIL_FILES=%q\n' "$MANUAL_DETAIL_FILES"
printf 'DETAIL_STATUS=%q\n' "$DETAIL_STATUS"
printf '%s\n' "$SESSION_ASSIGNMENTS"
