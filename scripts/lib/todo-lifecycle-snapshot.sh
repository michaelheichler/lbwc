#!/usr/bin/env bash
set -u

SNAPSHOT_SCHEMA_FILTER='
  def non_empty_string: type == "string" and length > 0;
  def positive_integer: type == "number" and floor == . and . > 0;
  def valid_section: . == "## Todos" or . == "### Pending Todos";
  def maybe_filter: . == null or (type == "string" and length > 0);
  def maybe_ref: . == null or (type == "string" and test("^[a-f0-9]{8}$"));
  def maybe_known_issue_signature:
    . == null
    or (
      type == "object"
      and ((keys_unsorted - ["phase", "phase_dir", "test", "file", "error", "source_kind", "disposition", "source_path"]) | length == 0)
      and ([.phase, .phase_dir, .test, .file, .error, .source_kind, .disposition, .source_path] | all(. == null or (type == "string")))
    );
  def valid_item($state_path; $section):
    type == "object"
    and (.state_path | non_empty_string)
    and (.state_path == $state_path)
    and (.section | valid_section)
    and (.section == $section)
    and (.line | non_empty_string)
    and (.normalized_text | non_empty_string)
    and (.section_index | positive_integer)
    and (.num | positive_integer)
    and (.identity_occurrence | positive_integer)
    and (.identity_total | positive_integer)
    and (.ref | maybe_ref)
    and (.known_issue_signature | maybe_known_issue_signature);
  def identity_of:
    {
      normalized_text: (.normalized_text // ""),
      ref: (.ref // null),
      known_issue_signature: (.known_issue_signature // null)
    };
  def item_nums_are_sequential:
    . as $items
    | to_entries
    | all(.value.num == (.key + 1));
  def unfiltered_identity_ordinals_match:
    . as $items
    | to_entries
    | all(
        (.key + 1) as $num
        | (.value | identity_of) as $id
        | (.value.identity_occurrence == ([range(0; $num) as $j | $items[$j] | select(identity_of == $id)] | length))
          and (.value.identity_total == ([ $items[] | select(identity_of == $id) ] | length))
      );

  type == "object"
  and (.status | type == "string")
  and (
    if .status == "error" then
      (.message | type == "string")
      and (if has("filter") then (.filter | maybe_filter) else true end)
      and (if has("items") then (.items | type == "array") else true end)
    elif .status == "empty" then
      (has("state_path") and (.state_path | non_empty_string))
      and (has("section") and .section == null)
      and (has("count") and .count == 0)
      and (has("filter") and (.filter | maybe_filter))
      and (has("items") and (.items | type == "array") and (.items | length == 0))
    elif .status == "no-match" then
      (has("state_path") and (.state_path | non_empty_string))
      and (has("section") and (.section | valid_section))
      and (has("count") and .count == 0)
      and (has("filter") and (.filter | type == "string" and length > 0))
      and (has("items") and (.items | type == "array") and (.items | length == 0))
    elif .status == "ok" then
      . as $snapshot
      | (has("state_path") and (.state_path | non_empty_string))
        and (has("section") and (.section | valid_section))
        and (has("count") and (.count | positive_integer))
        and (has("filter") and (.filter | maybe_filter))
        and (has("items") and (.items | type == "array") and (.items | length > 0))
        and (.count == (.items | length))
        and ([.items[] | valid_item($snapshot.state_path; $snapshot.section)] | all)
        and (.items | item_nums_are_sequential)
        and (if .filter == null then (.items | unfiltered_identity_ordinals_match) else true end)
    else
      false
    end
  )
'

snapshot_validate_schema() {
  local json_input="$1"
  printf '%s' "$json_input" | jq -e "$SNAPSHOT_SCHEMA_FILTER" >/dev/null 2>&1
}

snapshot_write_canonical() {
  local json_input="$1"
  local tmp_file

  tmp_file=$(mktemp "${SNAPSHOT_PATH}.tmp.XXXXXX" 2>/dev/null) || {
    error_json "snapshot_write_failed" "Todo snapshot could not be created. Rerun /lbwc:list-todos."
    return 0
  }

  if ! printf '%s' "$json_input" | jq -cS '.' > "$tmp_file"; then
    rm -f "$tmp_file"
    error_json "snapshot_write_failed" "Todo snapshot could not be written. Rerun /lbwc:list-todos."
    return 0
  fi

  chmod 600 "$tmp_file" 2>/dev/null || true
  if ! mv "$tmp_file" "$SNAPSHOT_PATH"; then
    rm -f "$tmp_file"
    error_json "snapshot_write_failed" "Todo snapshot could not be finalized. Rerun /lbwc:list-todos."
    return 0
  fi
  ok_json --arg status "ok" --arg path "$SNAPSHOT_PATH" '{status:$status, path:$path}'
}

snapshot_save() {
  local json_input
  json_input=$(read_stdin)

  if ! printf '%s' "$json_input" | jq empty >/dev/null 2>&1; then
    error_json "snapshot_invalid" "Todo snapshot JSON is invalid. Rerun /lbwc:list-todos."
    return 0
  fi

  if ! snapshot_validate_schema "$json_input"; then
    error_json "snapshot_invalid" "Todo snapshot JSON is malformed. Rerun /lbwc:list-todos."
    return 0
  fi

  snapshot_write_canonical "$json_input"
}

snapshot_select_require_unfiltered() {
  local snapshot="$1"
  local require_unfiltered="$2"
  local filter

  filter=$(printf '%s' "$snapshot" | jq -r '.filter // empty')
  if [ "$require_unfiltered" = "true" ] && [ -n "$filter" ]; then
    error_json "snapshot_filtered" "Current list view is filtered. Rerun unfiltered /lbwc:list-todos before using this numbered todo command."
    return 1
  fi
}

snapshot_select_emit_item() {
  local snapshot="$1"
  local selection="$2"
  local idx=$((selection - 1))

  printf '%s' "$snapshot" | jq -c --argjson idx "$idx" --argjson num "$selection" '
    . as $snapshot
    | .items[$idx]
    | . + {
        status: "ok",
        selection_source: "snapshot",
        num: $num,
        snapshot_filter: ($snapshot.filter // null),
        snapshot_state_path: ($snapshot.state_path // null),
        snapshot_section: ($snapshot.section // null)
      }
  '
}

snapshot_select_from_snapshot() {
  local snapshot="$1"
  local selection="$2"
  local require_unfiltered="$3"
  local snapshot_status count

  snapshot_status=$(printf '%s' "$snapshot" | jq -r '.status // "ok"' 2>/dev/null || echo 'error')
  if [ "$snapshot_status" = "error" ]; then
    printf '%s\n' "$snapshot"
    return 0
  fi
  if ! snapshot_select_require_unfiltered "$snapshot" "$require_unfiltered"; then
    return 0
  fi

  count=$(printf '%s' "$snapshot" | jq '.items | length')
  selection=$((10#$selection))
  if [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
    error_json "invalid_selection" "Invalid selection. Only items 1-${count} exist."
    return 0
  fi

  snapshot_select_emit_item "$snapshot" "$selection"
}

snapshot_select() {
  local selection="${1:-}"
  local require_unfiltered="false"
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --require-unfiltered) require_unfiltered="true" ;;
    esac
    shift || true
  done

  if [ -z "$selection" ] || ! [[ "$selection" =~ ^[0-9]+$ ]]; then
    error_json "invalid_selection" "Invalid selection. Choose a numbered todo from /lbwc:list-todos."
    return 0
  fi

  local snapshot
  snapshot=$(snapshot_show)
  snapshot_select_from_snapshot "$snapshot" "$selection" "$require_unfiltered"
}

todo_item_matching_candidates_json() {
  local current_items_json="$1"
  local expected_normalized="$2"
  local expected_ref="$3"
  local expected_signature="$4"
  local expected_occurrence="$5"

  printf '%s' "$current_items_json" | jq -c \
    --arg normalized_text "$expected_normalized" \
    --arg ref "$expected_ref" \
    --argjson signature "$expected_signature" \
    --argjson occurrence "$expected_occurrence" '
      [ .[]
        | select(.normalized_text == $normalized_text)
        | select((.ref // "") == $ref)
        | select((.known_issue_signature // null) == $signature)
        | select(.identity_occurrence == $occurrence)
      ]
    '
}

validate_item_candidate_metadata() {
  local candidate_json="$1"
  local expected_signature="$2"
  local expected_total="$3"
  local expected_line="$4"
  local current_signature

  current_signature=$(printf '%s' "$candidate_json" | jq -c '.known_issue_signature // null')
  [ "$expected_signature" = "$current_signature" ] || return 1
  [ "$(printf '%s' "$candidate_json" | jq -r '.identity_total')" = "$expected_total" ] || return 1
  if [ -n "$expected_line" ]; then
    [ "$(printf '%s' "$candidate_json" | jq -r '.line // empty')" = "$expected_line" ] || return 1
  fi
}

validate_item_metadata_json() {
  local item_json="$1"
  local expected_signature

  expected_signature=$(printf '%s' "$item_json" | jq -c '.known_issue_signature // null')
  expected_signature=$(todo_item_canonical_signature_json "$expected_signature")
  printf '%s' "$item_json" | jq -c --argjson expected_signature "$expected_signature" '{
    state_path:(.state_path // ""),
    section_name:(.section // ""),
    expected_normalized:(.normalized_text // ""),
    expected_ref:(.ref // ""),
    expected_signature:$expected_signature,
    expected_line:(.line // ""),
    expected_occurrence:(.identity_occurrence // ""),
    expected_total:(.identity_total // "")
  }'
}

validate_item_live_candidate_json() {
  local metadata_json="$1"
  local current_items_json="$2"
  local candidate_json candidate_count

  candidate_json=$(todo_item_matching_candidates_json "$current_items_json" \
    "$(printf '%s' "$metadata_json" | jq -r '.expected_normalized')" \
    "$(printf '%s' "$metadata_json" | jq -r '.expected_ref')" \
    "$(printf '%s' "$metadata_json" | jq -c '.expected_signature')" \
    "$(printf '%s' "$metadata_json" | jq -r '.expected_occurrence')")
  candidate_count=$(printf '%s' "$candidate_json" | jq 'length')
  [ "$candidate_count" -eq 1 ] 2>/dev/null || return 1
  candidate_json=$(printf '%s' "$candidate_json" | jq -c '.[0]') || return 1
  validate_item_candidate_metadata "$candidate_json" \
    "$(printf '%s' "$metadata_json" | jq -c '.expected_signature')" \
    "$(printf '%s' "$metadata_json" | jq -r '.expected_total')" \
    "$(printf '%s' "$metadata_json" | jq -r '.expected_line')" || return 1
  printf '%s\n' "$candidate_json"
}

validate_item_against_live_payload() {
  local metadata_json="$1"
  local state_path section_name current_items_json candidate_json

  state_path=$(printf '%s' "$metadata_json" | jq -r '.state_path')
  section_name=$(printf '%s' "$metadata_json" | jq -r '.section_name')
  if [ -z "$state_path" ] || [ -z "$section_name" ] || \
    [ -z "$(printf '%s' "$metadata_json" | jq -r '.expected_occurrence')" ] || \
    [ -z "$(printf '%s' "$metadata_json" | jq -r '.expected_total')" ]; then
    error_json "invalid_item" "Todo selection payload is missing required metadata. Rerun /lbwc:list-todos."
    return 0
  fi
  local state_dir planning_dir
  state_dir=$(cd -P "$(dirname "$state_path")" 2>/dev/null && pwd) || state_dir=""
  planning_dir=$(cd -P "${PLANNING_DIR%/}" 2>/dev/null && pwd) || planning_dir=""
  if [ "$(basename "$state_path")" != "STATE.md" ] || [ "$state_dir" != "$planning_dir" ] || [ ! -f "$state_path" ] || [ -L "$state_path" ]; then
    error_json "state_missing" "Todo selection no longer matches the writable root backlog. Rerun /lbwc:list-todos."
    return 0
  fi

  current_items_json=$(section_items_json "$state_path" "$section_name")
  if ! candidate_json=$(validate_item_live_candidate_json "$metadata_json" "$current_items_json"); then
    error_json "selection_stale" "Todo selection no longer matches live backlog. Rerun /lbwc:list-todos."
    return 0
  fi
  printf '%s' "$candidate_json"
}

validate_item_against_live() {
  local item_json="$1"
  local metadata_json
  metadata_json=$(validate_item_metadata_json "$item_json")
  validate_item_against_live_payload "$metadata_json"
}
