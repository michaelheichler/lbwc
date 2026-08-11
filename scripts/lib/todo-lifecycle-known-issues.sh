#!/usr/bin/env bash
set -u

known_issue_normalize_legacy_identity() {
  local item_json="$1"
  local display_text issue_text source_path disposition phase_num

  display_text=$(printf '%s' "$item_json" | jq -r '.display_identity // .text // empty')
  issue_text="${display_text#\[KNOWN-ISSUE\] }"
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(added [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\})$//')
  disposition="unresolved"
  if printf '%s' "$issue_text" | grep -q 'accepted as process-exception for this phase'; then
    disposition="accepted-process-exception"
    issue_text="${issue_text// $'\xE2\x80\x94' accepted as process-exception for this phase/}"
  fi
  source_path=$(printf '%s' "$issue_text" | sed -n 's/.*(see \([^)]*\)).*/\1/p')
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(see [^)]*)//')
  phase_num=$(printf '%s' "$issue_text" | sed -n 's/.*(phase \([0-9][0-9]*\), seen [0-9][0-9]*x).*/\1/p')
  issue_text=$(printf '%s' "$issue_text" | sed 's/ *(phase [0-9][0-9]*, seen [0-9][0-9]*x)//')
  jq -cn --arg issue_text "$issue_text" --arg phase "$phase_num" \
    --arg disposition "$disposition" --arg source_path "$source_path" \
    '{issue_text:$issue_text, phase:$phase, disposition:$disposition, source_path:$source_path}'
}

known_issue_parse_legacy_identity() {
  local item_json="$1"
  local normalized_json issue_text phase_num disposition source_path
  local parsed_test parsed_file parsed_error

  normalized_json=$(known_issue_normalize_legacy_identity "$item_json")
  issue_text=$(printf '%s' "$normalized_json" | jq -r '.issue_text')
  if ! [[ "$issue_text" =~ ^(.+)[[:space:]]+\(([^()]+)\):[[:space:]]*(.+)$ ]]; then
    return 1
  fi
  parsed_test="${BASH_REMATCH[1]}"
  parsed_file="${BASH_REMATCH[2]}"
  parsed_error="${BASH_REMATCH[3]}"
  phase_num=$(printf '%s' "$normalized_json" | jq -r '.phase')
  disposition=$(printf '%s' "$normalized_json" | jq -r '.disposition')
  source_path=$(printf '%s' "$normalized_json" | jq -r '.source_path')
  jq -cn --arg test "$parsed_test" --arg file "$parsed_file" --arg error "$parsed_error" \
    --arg phase "$phase_num" --arg disposition "$disposition" --arg source_path "$source_path" \
    '{test:$test, file:$file, error:$error, phase:$phase, disposition:$disposition, source_path:$source_path}'
}

lookup_legacy_known_issue_signature() {
  local item_json="$1"
  local parsed_json phase_num phase_dir query_json lookup_result lookup_status

  if ! parsed_json=$(known_issue_parse_legacy_identity "$item_json"); then
    error_json "suppression_missing_signature" "Known-issue suppression metadata is unavailable. The todo was removed, but it may be re-promoted."
    return 0
  fi
  phase_num=$(printf '%s' "$parsed_json" | jq -r '.phase')
  phase_dir=$(phase_dir_for_number "$phase_num")
  if [ -z "$phase_dir" ]; then
    error_json "suppression_missing_phase" "Known-issue suppression metadata is incomplete. The todo was removed, but it may be re-promoted."
    return 0
  fi

  query_json=$(printf '%s' "$parsed_json" | jq -c '{test, file, error, disposition, source_path}')
  lookup_result=$(printf '%s' "$query_json" | bash "$SCRIPT_DIR/track-known-issues.sh" lookup-signature "$phase_dir" 2>/dev/null || true)
  lookup_status=$(printf '%s' "$lookup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$lookup_status" != "ok" ]; then
    printf '%s\n' "$lookup_result"
    return 0
  fi
  printf '%s\n' "$lookup_result"
}

suppress_known_issue_resolve_signature() {
  local item_json="$1"
  local signature_json lookup_result lookup_status

  signature_json=$(printf '%s' "$item_json" | jq -c '.known_issue_signature // null')
  if [ "$signature_json" != "null" ]; then
    printf '%s\n' "$signature_json"
    return 0
  fi

  lookup_result=$(lookup_legacy_known_issue_signature "$item_json")
  lookup_status=$(printf '%s' "$lookup_result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$lookup_status" != "ok" ]; then
    printf '%s\n' "$lookup_result"
    return 0
  fi
  printf '%s\n' "$lookup_result" | jq -c '.signature'
}

suppress_known_issue() {
  local item_json="$1"
  local command_label="$2"
  local signature_json phase_dir output_json status_val

  signature_json=$(suppress_known_issue_resolve_signature "$item_json")
  if [ "$(printf '%s' "$signature_json" | jq -r 'type')" != "object" ]; then
    printf '%s\n' "$signature_json"
    return 0
  fi

  phase_dir=$(printf '%s' "$signature_json" | jq -r '.phase_dir // empty')
  phase_dir=$(normalize_phase_dir "$phase_dir")
  if [ -z "$phase_dir" ]; then
    error_json "suppression_missing_phase" "Known-issue suppression metadata is incomplete. The todo was removed, but it may be re-promoted."
    return 0
  fi

  output_json=$(printf '%s' "$signature_json" | jq -c --arg via "$command_label" '. + {via:$via}' | bash "$SCRIPT_DIR/track-known-issues.sh" suppress "$phase_dir" 2>/dev/null || true)
  status_val=$(printf '%s' "$output_json" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$status_val" != "ok" ]; then
    printf '%s\n' "$output_json"
    return 0
  fi
  printf '%s\n' "$output_json"
}

cleanup_detail_remove_ref() {
  local ref="$1"
  local result status_val

  result=$(bash "$SCRIPT_DIR/todo-details.sh" remove "$ref" "$DETAILS_PATH" 2>/dev/null || true)
  status_val=$(printf '%s' "$result" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$status_val" != "ok" ]; then
    error_json "detail_cleanup_failed" "Todo detail cleanup failed for ref ${ref}. The todo was removed, but cleanup needs attention."
    return 0
  fi
  printf '%s\n' "$result"
}

cleanup_detail_if_safe() {
  local item_json="$1"
  local detail_status="$2"
  local cleanup_policy="$3"
  local ref

  ref=$(printf '%s' "$item_json" | jq -r '.ref // empty')
  if [ -z "$ref" ] || [ "$detail_status" = "none" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi
  if [ "$detail_status" = "not_found" ] || [ "$detail_status" = "error" ]; then
    jq -cn --arg status "warning" --arg code "detail_cleanup_skipped" \
      --arg message "Todo detail cleanup was skipped for ref ${ref} because the detail load status was ${detail_status}. The todo was removed, but the sidecar registry was left untouched." \
      '{status:$status, code:$code, message:$message}'
    return 0
  fi
  if [ "$cleanup_policy" != "safe" ]; then
    ok_json --arg status "ok" --arg action "skipped" '{status:$status, action:$action}'
    return 0
  fi
  cleanup_detail_remove_ref "$ref"
}

rewrite_state_apply_line() {
  local state_path="$1"
  local line_no="$2"
  local direct_count="$3"
  local tmp_file="$4"

  if [ "$direct_count" -le 1 ] 2>/dev/null; then
    awk -v target="$line_no" 'NR == target { print "None."; next } { print }' "$state_path" > "$tmp_file"
  else
    awk -v target="$line_no" 'NR == target { next } { print }' "$state_path" > "$tmp_file"
  fi
}

rewrite_state_stage_item() {
  local state_path="$2"
  local section_name="$3"
  local line_no="$4"
  local direct_count tmp_file

  if ! direct_count=$(extract_section_lines "$state_path" "$section_name" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' '); then
    error_json "rewrite_prepare_failed" "Could not inspect the current todo section in STATE.md. Rerun /lbwc:list-todos."
    return 0
  fi
  tmp_file=$(make_temp_with_suffix "$state_path" rewrite) || {
    error_json "rewrite_prepare_failed" "Could not prepare a temporary STATE.md rewrite. Rerun /lbwc:list-todos."
    return 0
  }
  if ! rewrite_state_apply_line "$state_path" "$line_no" "$direct_count" "$tmp_file"; then
    rm -f "$tmp_file"
    error_json "rewrite_prepare_failed" "Could not stage the updated todo section. Rerun /lbwc:list-todos."
    return 0
  fi
  jq -cn --arg status "ok" --arg tmp_file "$tmp_file" '{status:$status, tmp_file:$tmp_file}'
}

rewrite_state_finalize_item() {
  local tmp_file="$1"
  local state_path="$2"
  local activity_message="$3"

  if ! append_activity_entry "$tmp_file" "$activity_message"; then
    rm -f "$tmp_file"
    error_json "activity_write_failed" "Could not append the activity breadcrumb to STATE.md. Rerun /lbwc:list-todos."
    return 0
  fi
  if ! mv "$tmp_file" "$state_path"; then
    rm -f "$tmp_file"
    error_json "rewrite_finalize_failed" "Could not finalize the STATE.md rewrite. Rerun /lbwc:list-todos."
    return 0
  fi
  ok_json --arg status "ok" --arg state_path "$state_path" '{status:$status, state_path:$state_path}'
}

rewrite_state_for_item() {
  local item_json="$1"
  local activity_message="$2"
  local state_path section_name line_no stage_result stage_status tmp_file

  state_path=$(printf '%s' "$item_json" | jq -r '.state_path // empty')
  section_name=$(printf '%s' "$item_json" | jq -r '.section // empty')
  line_no=$(printf '%s' "$item_json" | jq -r '.line_no // empty')
  if [ -z "$state_path" ] || [ -z "$section_name" ] || [ -z "$line_no" ]; then
    error_json "invalid_item" "Todo selection payload is missing required metadata. Rerun /lbwc:list-todos."
    return 0
  fi
  if state_path_is_archived "$state_path"; then
    error_json "archived_state" "$(archived_state_message)"
    return 0
  fi

  stage_result=$(rewrite_state_stage_item "$item_json" "$state_path" "$section_name" "$line_no")
  stage_status=$(printf '%s' "$stage_result" | jq -r '.status // "error"')
  if [ "$stage_status" != "ok" ]; then
    printf '%s\n' "$stage_result"
    return 0
  fi
  tmp_file=$(printf '%s' "$stage_result" | jq -r '.tmp_file')
  rewrite_state_finalize_item "$tmp_file" "$state_path" "$activity_message"
}
