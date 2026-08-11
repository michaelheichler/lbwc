#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
export DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
RAW_SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
SESSION_KEY="$(printf '%s' "$RAW_SESSION_KEY" | tr -c 'A-Za-z0-9_.-' '_')"
SESSION_KEY="${SESSION_KEY:-default}"
SNAPSHOT_PATH="/tmp/.lbwc-last-list-view-${SESSION_KEY}.json"
CMD="${1:-}"
shift || true

. "$SCRIPT_DIR/lib/todo-item-metadata.sh"
. "$SCRIPT_DIR/lib/todo-lifecycle-snapshot.sh"
. "$SCRIPT_DIR/lib/todo-lifecycle-known-issues.sh"

json_out() {
  jq -cn "$@"
}

error_json() {
  local code="$1"
  local message="$2"
  json_out --arg status "error" --arg code "$code" --arg message "$message" \
    '{status:$status, code:$code, message:$message}'
}

ok_json() {
  jq -cn "$@"
}

usage() {
  error_json "usage" "Usage: todo-lifecycle.sh <list-with-snapshot|snapshot-save|snapshot-show|snapshot-select|validate-item|detail-warning|pickup|remove> [args]"
}

read_stdin() {
  cat
}

make_temp_with_suffix() {
  local target_path="$1"
  local suffix="$2"
  mktemp "${target_path}.${suffix}.XXXXXX" 2>/dev/null
}

list_with_snapshot() {
  local output_json snapshot_result snapshot_status

  output_json=$(bash "$SCRIPT_DIR/list-todos.sh" "$@" 2>/dev/null || true)
  snapshot_result=$(snapshot_save <<< "$output_json")
  snapshot_status=$(printf '%s' "$snapshot_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$snapshot_status" != "ok" ]; then
    printf '%s\n' "$snapshot_result"
    return 0
  fi

  printf '%s\n' "$output_json"
}

snapshot_show() {
  if [ ! -f "$SNAPSHOT_PATH" ] || [ -L "$SNAPSHOT_PATH" ]; then
    error_json "snapshot_missing" "Todo snapshot missing. Rerun /lbwc:list-todos first."
    return 0
  fi

  local json_input
  json_input=$(cat "$SNAPSHOT_PATH" 2>/dev/null || true)
  if ! printf '%s' "$json_input" | jq empty >/dev/null 2>&1; then
    error_json "snapshot_invalid" "Todo snapshot is malformed. Rerun /lbwc:list-todos first."
    return 0
  fi

  if ! snapshot_validate_schema "$json_input"; then
    error_json "snapshot_invalid" "Todo snapshot is malformed. Rerun /lbwc:list-todos first."
    return 0
  fi

  printf '%s\n' "$json_input"
}

trim() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

state_path_is_archived() {
  case "$1" in
    */.lbwc-planning/milestones/*|.lbwc-planning/milestones/*) return 0 ;;
    *) return 1 ;;
  esac
}

section_items_json() {
  local state_path="$1"
  local section_name="$2"
  local current_lines items_json

  current_lines=$(extract_section_lines "$state_path" "$section_name" 2>/dev/null || true)
  items_json='[]'

  while IFS=$'\t' read -r current_line_no current_line; do
    [ -n "$current_line_no" ] || continue
    local section_index item_json
    section_index=$(printf '%s' "$items_json" | jq 'length + 1')
    item_json=$(todo_item_parse_line_json "$current_line" "$section_index" "$state_path" "$section_name")
    item_json=$(printf '%s' "$item_json" | jq -c --argjson line_no "$current_line_no" '. + {line_no: $line_no}')
    items_json=$(printf '%s' "$items_json" | jq --argjson item "$item_json" '. + [$item]')
  done <<< "$current_lines"

  todo_item_annotate_identity_occurrence "$items_json"
}

extract_section_lines() {
  local state_path="$1"
  local section_name="$2"

  case "$section_name" in
    "## Todos")
      awk -v state_path="$state_path" -v section_name="$section_name" '
        /^## Todos?$/ { found=1; next }
        found && /^##/ { exit }
        found && /^### / { sub_found=1; next }
        found && !sub_found && /^- / { print NR "\t" $0 }
      ' "$state_path"
      ;;
    "### Pending Todos")
      awk -v state_path="$state_path" -v section_name="$section_name" '
        /^### Pending Todos$/ { found=1; next }
        found && /^### Completed Todos$/ { exit }
        found && /^##/ { exit }
        found && /^- / { print NR "\t" $0 }
      ' "$state_path"
      ;;
    *)
      return 1
      ;;
  esac
}

validate_item_cmd() {
  local item_json validated_json validated_status
  item_json=$(read_stdin)
  if ! printf '%s' "$item_json" | jq empty >/dev/null 2>&1; then
    error_json "invalid_item" "Todo selection payload is invalid. Rerun /lbwc:list-todos."
    return 0
  fi
  validated_json=$(validate_item_against_live "$item_json")
  validated_status=$(printf '%s' "$validated_json" | jq -r '.status // "ok"' 2>/dev/null || echo 'error')
  if [ "$validated_status" = "error" ]; then
    printf '%s\n' "$validated_json"
    return 0
  fi
  printf '%s' "$validated_json" | jq -c '. + {status:"ok"}'
}

append_activity_line_to_file() {
  local file_path="$1"
  local activity_line="$2"
  local tmp_file heading_line next_heading
  tmp_file=$(make_temp_with_suffix "$file_path" activity) || return 1

  heading_line=$(grep -nE '^## (Recent Activity|Activity Log|Activity)$' "$file_path" 2>/dev/null | head -1 | cut -d: -f1 || true)
  if [ -n "$heading_line" ]; then
    next_heading=$(awk -v start="$heading_line" 'NR > start && /^## / { print NR; exit }' "$file_path")
    if [ -n "$next_heading" ]; then
      awk -v heading_line="$heading_line" -v next_heading="$next_heading" -v activity_line="$activity_line" '
        NR == next_heading { print activity_line; print "" }
        { print }
        END {
          if (NR < next_heading) {
            print activity_line
          }
        }
      ' "$file_path" > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
      }
    else
      cat "$file_path" > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
      }
      printf '\n%s\n' "$activity_line" >> "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
      }
    fi
  else
    cat "$file_path" > "$tmp_file" || {
      rm -f "$tmp_file"
      return 1
    }
    printf '\n## Activity Log\n\n%s\n' "$activity_line" >> "$tmp_file" || {
      rm -f "$tmp_file"
      return 1
    }
  fi

  mv "$tmp_file" "$file_path" || {
    rm -f "$tmp_file"
    return 1
  }
}

append_activity_entry() {
  local state_path="$1"
  local message="$2"
  local today line
  [ -f "$state_path" ] || return 0
  today=$(date +%Y-%m-%d)
  line="- ${today}: ${message}"
  append_activity_line_to_file "$state_path" "$line"
}

detail_warning() {
  local ref_hash="${1:-}"
  local state_path="${2:-${PLANNING_DIR}/STATE.md}"
  if [ -z "$ref_hash" ]; then
    error_json "usage" "Usage: todo-lifecycle.sh detail-warning <hash> [state-path]"
    return 0
  fi
  if [ ! -f "$state_path" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi
  if ! append_activity_entry "$state_path" "Detail for ref ${ref_hash} could not be loaded"; then
    error_json "activity_write_failed" "Could not record the detail warning in STATE.md. Rerun /lbwc:list-todos or inspect STATE.md manually."
    return 0
  fi
  ok_json --arg status "ok" --arg action "logged" --arg state_path "$state_path" '{status:$status, action:$action, state_path:$state_path}'
}

normalize_phase_dir() {
  local phase_dir="$1"
  if [ -z "$phase_dir" ]; then
    echo ""
    return
  fi
  case "$phase_dir" in
    /*)
      printf '%s\n' "$phase_dir"
      ;;
    *)
      if [ -d "$phase_dir" ]; then
        printf '%s\n' "$phase_dir"
      else
        printf '%s\n' "${PLANNING_DIR%/}/${phase_dir#./}"
      fi
      ;;
  esac
}

phase_dir_for_number() {
  local phase_num="$1"
  find "${PLANNING_DIR%/}/phases" -maxdepth 1 -type d -name "${phase_num}-*" 2>/dev/null | head -1
}

mutate_item() {
  local mode="$1"
  local command_label="$2"
  local detail_status="$3"
  local cleanup_policy="$4"
  local item_json validated_json activity_text rewrite_result rewrite_status detail_cleanup_result detail_cleanup_status suppression_result suppression_status final_status final_warning

  item_json=$(read_stdin)
  if ! printf '%s' "$item_json" | jq empty >/dev/null 2>&1; then
    error_json "invalid_item" "Todo selection payload is invalid. Rerun /lbwc:list-todos."
    return 0
  fi

  validated_json=$(validate_item_against_live "$item_json")
  rewrite_status=$(printf '%s' "$validated_json" | jq -r '.status // "ok"' 2>/dev/null || echo 'error')
  if [ "$rewrite_status" = "error" ]; then
    printf '%s\n' "$validated_json"
    return 0
  fi

  activity_text=$(printf '%s' "$validated_json" | jq -r '.display_identity // .normalized_text // "todo"')
  case "$mode" in
    pickup) activity_text="Picked up todo via ${command_label}: ${activity_text}" ;;
    remove) activity_text="Removed todo via /lbwc:list-todos: ${activity_text}" ;;
    *) activity_text="Updated todo: ${activity_text}" ;;
  esac

  rewrite_result=$(rewrite_state_for_item "$validated_json" "$activity_text")
  rewrite_status=$(printf '%s' "$rewrite_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$rewrite_status" != "ok" ]; then
    printf '%s\n' "$rewrite_result"
    return 0
  fi

  final_status="ok"
  final_warning=""

  detail_cleanup_result=$(cleanup_detail_if_safe "$validated_json" "$detail_status" "$cleanup_policy")
  detail_cleanup_status=$(printf '%s' "$detail_cleanup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$detail_cleanup_status" != "ok" ]; then
    final_status="partial"
    final_warning=$(printf '%s' "$detail_cleanup_result" | jq -r '.message // empty' 2>/dev/null || true)
  fi

  if [ "$(printf '%s' "$validated_json" | jq -r '.priority // empty')" = "known-issue" ]; then
    suppression_result=$(suppress_known_issue "$validated_json" "$command_label")
    suppression_status=$(printf '%s' "$suppression_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
    if [ "$suppression_status" != "ok" ]; then
      final_status="partial"
      if [ -n "$final_warning" ]; then
        final_warning+=" "
      fi
      final_warning+=$(printf '%s' "$suppression_result" | jq -r '.message // empty' 2>/dev/null || true)
    fi
  fi

  jq -cn \
    --arg status "$final_status" \
    --arg action "$mode" \
    --arg command_label "$command_label" \
    --arg state_path "$(printf '%s' "$validated_json" | jq -r '.state_path // empty')" \
    --arg warning "$final_warning" \
    '{
      status:$status,
      action:$action,
      command_label:$command_label,
      state_path:$state_path,
      warning:(if $warning == "" then null else $warning end)
    }'
}

case "$CMD" in
  list-with-snapshot)
    list_with_snapshot "$@"
    ;;
  snapshot-save)
    snapshot_save
    ;;
  snapshot-show)
    snapshot_show
    ;;
  snapshot-select)
    snapshot_select "$@"
    ;;
  validate-item)
    validate_item_cmd
    ;;
  detail-warning)
    detail_warning "$@"
    ;;
  pickup)
    mutate_item "pickup" "${1:-}" "${2:-none}" "${3:-keep}"
    ;;
  remove)
    mutate_item "remove" "/lbwc:list-todos" "${1:-none}" "${2:-keep}"
    ;;
  *)
    usage
    ;;
esac
