#!/usr/bin/env bash
set -euo pipefail


PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
export FILTER="${1:-}"
export DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DETAILS_CACHE_JSON=""

. "$SCRIPT_DIR/lib/todo-item-metadata.sh"

resolve_state_path() {
  local state_path="$PLANNING_DIR/STATE.md"

  if [ -f "$state_path" ] && [ ! -L "$state_path" ]; then
    echo "$state_path"
    return 0
  fi

  echo '{"status":"error","message":"Writable root STATE.md not found at '"$state_path"'. Run /lbwc:init to set up your project."}'
  return 1
}

emit_error_json() {
  local state_path="$1"
  local section_name="$2"
  local filter_lower="$3"
  local message="$4"
  jq -n --arg sp "$state_path" --arg sec "$section_name" --arg f "$filter_lower" --arg msg "$message" '
    {status:"error", state_path:$sp, section:$sec, count:0,
      filter:(if $f == "" then null else $f end),
      display:$msg, message:$msg, items:[]}
  '
}

. "$SCRIPT_DIR/lib/list-todos-functions.inc"

main
