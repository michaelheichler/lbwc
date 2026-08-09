#!/bin/bash
set -u

list_child_dirs_sorted_fallback() {
  local dirs=("$@")
  local sorted=()
  local candidate candidate_name candidate_prefix candidate_num
  local existing existing_name existing_prefix existing_num
  local insert_at idx

  [ ${#dirs[@]} -gt 0 ] || return 0

  for candidate in "${dirs[@]}"; do
    candidate_name="${candidate##*/}"
    candidate_prefix="${candidate_name%%[^0-9]*}"
    if [ -z "$candidate_prefix" ]; then
      sorted+=("$candidate")
      continue
    fi

    candidate_num=$((10#$candidate_prefix))
    insert_at=${#sorted[@]}

    for idx in "${!sorted[@]}"; do
      existing="${sorted[$idx]}"
      existing_name="${existing##*/}"
      existing_prefix="${existing_name%%[^0-9]*}"
      if [ -z "$existing_prefix" ]; then
        continue
      fi

      existing_num=$((10#$existing_prefix))
      if [ "$candidate_num" -lt "$existing_num" ] || { [ "$candidate_num" -eq "$existing_num" ] && [[ "$candidate" < "$existing" ]]; }; then
        insert_at=$idx
        break
      fi
    done

    sorted=("${sorted[@]:0:$insert_at}" "$candidate" "${sorted[@]:$insert_at}")
  done

  printf '%s\n' "${sorted[@]}"
}

list_child_dirs_sorted() {
  local parent="$1"
  local sorted_output=""

  [ -d "$parent" ] || return 0

  local dirs=() d
  for d in "$parent"/*/; do
    [ -d "$d" ] && dirs+=("${d%/}")
  done
  case ${#dirs[@]} in
    0) return 0 ;;
    1)
      printf '%s\n' "${dirs[0]}"
      return 0
      ;;
  esac

  sorted_output=$(printf '%s\n' "${dirs[@]}" | sort -V 2>/dev/null || true)
  if [ -n "$sorted_output" ]; then
    printf '%s\n' "$sorted_output"
    return 0
  fi

  list_child_dirs_sorted_fallback "${dirs[@]}"
}

phase_relative_path() {
  local base="${1%/}"
  local path="$2"

  case "$path" in
    "$base"/*)
      printf '%s\n' "${path#"$base"/}"
      ;;
    *)
      basename "$path"
      ;;
  esac
}

phase_has_uat_cutover() {
  local phase_dir="$1"
  local phase_name phase_num root_uat f

  [ -n "$phase_dir" ] || return 1
  case "$phase_dir" in
    */) ;;
    *) phase_dir="$phase_dir/" ;;
  esac

  [ -d "$phase_dir" ] || return 1

  [ -f "${phase_dir}.uat-remediation-stage" ] && return 0
  [ -f "${phase_dir}remediation/uat/.uat-remediation-stage" ] && return 0
  [ -f "${phase_dir}remediation/.uat-remediation-stage" ] && return 0

  if type latest_non_source_uat &>/dev/null; then
    root_uat=$(latest_non_source_uat "$phase_dir")
    [ -n "$root_uat" ] && [ -f "$root_uat" ] && return 0
  fi

  phase_name=$(basename "${phase_dir%/}")
  phase_num=$(printf '%s\n' "$phase_name" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')

  if [ -n "$phase_num" ] && [ -f "${phase_dir}${phase_num}-UAT.md" ]; then
    return 0
  fi

  for f in "${phase_dir}"[0-9]*-UAT-round-*.md; do
    [ -f "$f" ] && return 0
  done
  for f in "${phase_dir}"remediation/round-*/R*-UAT.md; do
    [ -f "$f" ] && return 0
  done
  for f in "${phase_dir}"remediation/uat/round-*/R*-UAT.md; do
    [ -f "$f" ] && return 0
  done

  return 1
}

advance_uat_round_after_issues() {
  local current_round="$3"
  local cap_decision cap_status cap_reached

  case "$current_round" in
    ''|*[!0-9]*)
      printf '%s\n' "needs_reverification"
      return 0
      ;;
  esac

  cap_decision=$(bash "$_SCRIPT_DIR_PD/resolve-uat-remediation-round-limit.sh" --next-round-decision "$PLANNING_DIR/config.json" "$current_round" 2>/dev/null)
  cap_status=$?
  cap_reached=$(printf '%s\n' "$cap_decision" | awk -F= '/^cap_reached=/{print $2; exit}')
  case "${cap_status}:${cap_reached:-}" in
    0:true)
      printf '%s\n' "needs_reverification"
      ;;
    0:false)
      printf '%s\n' "needs_uat_remediation"
      ;;
    *)
      printf '%s\n' "needs_reverification"
      ;;
  esac
}

normalize_qa_remediation_stage() {
  case "${1:-none}" in
    plan|execute|verify|done) echo "$1" ;;
    *) echo "none" ;;
  esac
}

trim_phase_detect_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

state_file_kv_value() {
  local file_path="$1"
  local key_name="$2"
  local line value

  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$key_name"=*)
        value="${line#"$key_name="}"
        trim_phase_detect_value "$value"
        return 0
        ;;
    esac
  done < "$file_path"

  return 0
}

state_file_scalar_value() {
  local file_path="$1"
  local line value

  [ -f "$file_path" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    value=$(trim_phase_detect_value "$line")
    [ -n "$value" ] || continue
    printf '%s\n' "$value"
    return 0
  done < "$file_path"

  return 0
}

verification_writer() {
  local verification_file="$1"
  [ -f "$verification_file" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^writer:/ { sub(/^writer:[[:space:]]*/, ""); print; exit }
  ' "$verification_file" 2>/dev/null
}

verification_frontmatter_value() {
  local verification_file="$1"
  local key_name="$2"
  [ -n "$verification_file" ] && [ -f "$verification_file" ] || return 0
  [ -n "$key_name" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      prefix = key ":"
      if (index($0, prefix) == 1) {
        value=$0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' key="$key_name" "$verification_file" 2>/dev/null || true
}

verification_frontmatter_has_key() {
  local verification_file="$1"
  local key_name="$2"
  [ -n "$verification_file" ] && [ -f "$verification_file" ] || return 1
  [ -n "$key_name" ] || return 1
  awk '
    BEGIN { in_fm=0; found=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      prefix = key ":"
      if (index($0, prefix) == 1) {
        found=1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' key="$key_name" "$verification_file" 2>/dev/null
}

verification_result_value() {
  local verification_file="$1"
  local status_value status_upper

  [ -n "$verification_file" ] && [ -f "$verification_file" ] || return 0

  if verification_frontmatter_has_key "$verification_file" "result"; then
    verification_frontmatter_value "$verification_file" "result"
    return 0
  fi

  if verification_frontmatter_has_key "$verification_file" "status"; then
    status_value=$(verification_frontmatter_value "$verification_file" "status")
    status_upper=$(printf '%s' "$status_value" | tr '[:lower:]' '[:upper:]')
    case "$status_upper" in
      PASS|FAIL|PARTIAL)
        printf '%s\n' "$status_value"
        ;;
    esac
  fi
}

verification_pending_reason() {
  local verification_file="$1"
  local field_value field_upper

  [ -n "$verification_file" ] && [ -f "$verification_file" ] || {
    printf '%s\n' "missing_verification_artifact"
    return 0
  }

  if verification_frontmatter_has_key "$verification_file" "result"; then
    field_value=$(verification_frontmatter_value "$verification_file" "result")
    field_value=$(trim_phase_detect_value "$field_value")
    if [ -z "$field_value" ]; then
      printf '%s\n' "verification_result_missing"
    else
      printf '%s\n' "verification_result_unrecognized"
    fi
    return 0
  fi

  if verification_frontmatter_has_key "$verification_file" "status"; then
    field_value=$(verification_frontmatter_value "$verification_file" "status")
    field_value=$(trim_phase_detect_value "$field_value")
    field_upper=$(printf '%s' "$field_value" | tr '[:lower:]' '[:upper:]')
    case "$field_upper" in
      PASS|FAIL|PARTIAL)
        printf '%s\n' "none"
        ;;
      "")
        printf '%s\n' "verification_result_missing"
        ;;
      *)
        printf '%s\n' "verification_result_unrecognized"
        ;;
    esac
    return 0
  fi

  printf '%s\n' "verification_result_missing"
}

phase_verification_assessment() {
  local phase_dir="$1"
  local verification_file="$2"
  local success_state="$3"
  local qa_result qa_gate_routing stale_reason

  [ -n "$verification_file" ] && [ -f "$verification_file" ] || {
    printf '%s\t%s\n' "pending" "missing_verification_artifact"
    return 0
  }

  qa_result=$(verification_result_value "$verification_file")
  qa_result=$(printf '%s' "$qa_result" | tr '[:lower:]' '[:upper:]')
  case "$qa_result" in
    PASS)
      qa_gate_routing=$(bash "$_SCRIPT_DIR_PD/qa-result-gate.sh" "$phase_dir" 2>/dev/null | awk -F= '$1 == "qa_gate_routing" { print $2; exit }')
      case "${qa_gate_routing:-}" in
        REMEDIATION_REQUIRED)
          printf '%s\t%s\n' "failed" "none"
          ;;
        QA_RERUN_REQUIRED)
          printf '%s\t%s\n' "pending" "qa_gate_rerun_required"
          ;;
        "")
          printf '%s\t%s\n' "pending" "qa_gate_output_missing"
          ;;
        PROCEED_TO_UAT)
          if verification_is_stale "$verification_file" "$phase_dir"; then
            stale_reason="${VERIFICATION_FRESHNESS_REASON:-freshness_baseline_unavailable}"
            case "$stale_reason" in
              ""|fresh|missing_file) stale_reason="freshness_baseline_unavailable" ;;
            esac
            printf '%s\t%s\n' "pending" "$stale_reason"
          else
            printf '%s\t%s\n' "$success_state" "none"
          fi
          ;;
        *)
          printf '%s\t%s\n' "pending" "qa_gate_output_missing"
          ;;
      esac
      ;;
    FAIL|PARTIAL)
      printf '%s\t%s\n' "failed" "none"
      ;;
    *)
      printf '%s\t%s\n' "pending" "$(verification_pending_reason "$verification_file")"
      ;;
  esac
}

phase_has_passing_qa_remediation() {
  local phase_dir="$1"
  local state_file stage verification_file assessment assessment_state _

  state_file="${phase_dir%/}/remediation/qa/.qa-remediation-stage"
  [ -f "$state_file" ] || return 1
  stage=$(normalize_qa_remediation_stage "$(state_file_kv_value "$state_file" stage)")
  [ "$stage" = "done" ] || return 1

  verification_file=$(bash "$_SCRIPT_DIR_PD/resolve-verification-path.sh" current "$phase_dir" 2>/dev/null) || return 1
  [ -f "$verification_file" ] || return 1
  assessment=$(phase_verification_assessment "$phase_dir" "$verification_file" "satisfied")
  IFS=$'\t' read -r assessment_state _ <<< "$assessment"
  [ "$assessment_state" = "satisfied" ]
}

phase_execution_is_satisfied() {
  local phase_dir="$1"
  local plan_count="$2"
  local complete_count="$3"
  local terminal_count f status has_partial=false

  [ "$plan_count" -gt 0 ] || return 1
  [ "$complete_count" -ge "$plan_count" ] && return 0
  terminal_count=$(count_terminal_summaries "$phase_dir")
  [ "$terminal_count" -ge "$plan_count" ] || return 1
  for f in "$phase_dir"/*-SUMMARY.md "$phase_dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    status=$(extract_summary_status "$f")
    case "$status" in
      partial) has_partial=true ;;
      complete|completed) ;;
      failed) return 1 ;;
    esac
  done
  [ "$has_partial" = true ] || return 1
  phase_has_passing_qa_remediation "$phase_dir"
}
