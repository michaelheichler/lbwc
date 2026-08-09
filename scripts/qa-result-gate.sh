#!/usr/bin/env bash
set -euo pipefail


PHASE_DIR="${1:-}"
VERIF_NAME="${2:-}"
EXPLICIT_VERIF_NAME=false
if [ -n "$VERIF_NAME" ]; then
  EXPLICIT_VERIF_NAME=true
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE_VERIF_SCRIPT="$SCRIPT_DIR/resolve-verification-path.sh"
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  . "$SCRIPT_DIR/summary-utils.sh"
fi
TRACK_UAT_DEVIATIONS_SCRIPT="$SCRIPT_DIR/track-uat-deviations.sh"
: "$TRACK_UAT_DEVIATIONS_SCRIPT"

. "$SCRIPT_DIR/lib/qa-result-gate-path-evidence.sh"
. "$SCRIPT_DIR/lib/qa-result-gate-fail-classifications.sh"
. "$SCRIPT_DIR/lib/qa-result-gate-known-issues.sh"
. "$SCRIPT_DIR/lib/qa-result-gate-summary-deviations.sh"

if [ -z "$PHASE_DIR" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

if [ -z "$VERIF_NAME" ]; then
  VERIF_PATH=$(bash "$RESOLVE_VERIF_SCRIPT" phase "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$VERIF_PATH" ]; then
    VERIF_NAME=$(basename "$VERIF_PATH")
  else
    PHASE_NUM=$(basename "$PHASE_DIR" | grep -oE '^[0-9]+' 2>/dev/null || true)
    VERIF_NAME="${PHASE_NUM:-01}-VERIFICATION.md"
    VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
  fi
else
  VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
fi

IN_REMEDIATION="false"
PLAN_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level plans
SUMMARY_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level summaries
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  _gate_stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_stage="${_gate_stage:-none}"
  case "$_gate_stage" in
    plan|execute|verify|done) IN_REMEDIATION="true" ;;
    *) _gate_stage="none" ;;
  esac
  _gate_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_round="${_gate_round:-01}"
  if ! [[ "$_gate_round" =~ ^[0-9]+$ ]]; then
    _gate_round="01"
  fi
  _gate_round=$(printf '%02d' "$((10#${_gate_round}))")
  _gate_round_dir="$PHASE_DIR/remediation/qa/round-${_gate_round}"
  _gate_round_verif="${_gate_round_dir}/R${_gate_round}-VERIFICATION.md"
  if [ "$EXPLICIT_VERIF_NAME" = false ]; then
    case "$_gate_stage" in
      verify)
        VERIF_PATH="$_gate_round_verif"
        VERIF_NAME=$(basename "$VERIF_PATH")
        ;;
      done)
        _gate_authoritative_verif=$(bash "$RESOLVE_VERIF_SCRIPT" authoritative "$PHASE_DIR" 2>/dev/null || true)
        if [ -n "${_gate_authoritative_verif:-}" ]; then
          VERIF_PATH="$_gate_authoritative_verif"
          VERIF_NAME=$(basename "$VERIF_PATH")
        fi
        ;;
    esac
  fi
  if [ "$VERIF_PATH" = "$_gate_round_verif" ]; then
    PLAN_SCOPE_DIR="$_gate_round_dir"
    SUMMARY_SCOPE_DIR="$_gate_round_dir"
  fi
fi

GIT_ROOT=$(git -C "$PHASE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
KNOWN_ISSUES_STATUS="missing"
KNOWN_ISSUES_COUNT=0
if [ -f "$SCRIPT_DIR/track-known-issues.sh" ]; then
  _known_issues_meta=$(bash "$SCRIPT_DIR/track-known-issues.sh" status "$PHASE_DIR" 2>/dev/null || true)
  _known_issues_status=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_status=/{print $2; exit}')
  _known_issues_count_raw=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_count=/{print $2; exit}')
  case "${_known_issues_status:-}" in
    present|missing|malformed)
      case "${_known_issues_count_raw:-}" in
        '')
          if [ "$_known_issues_status" = "present" ]; then
            KNOWN_ISSUES_STATUS="probe_error"
            KNOWN_ISSUES_COUNT=0
          else
            KNOWN_ISSUES_STATUS="$_known_issues_status"
            KNOWN_ISSUES_COUNT=0
          fi
          ;;
        *[!0-9]*)
          KNOWN_ISSUES_STATUS="probe_error"
          KNOWN_ISSUES_COUNT=0
          ;;
        *)
          if [ "$_known_issues_status" != "present" ] && [ "$_known_issues_count_raw" -gt 0 ] 2>/dev/null; then
            KNOWN_ISSUES_STATUS="probe_error"
            KNOWN_ISSUES_COUNT=0
          else
            KNOWN_ISSUES_STATUS="$_known_issues_status"
            KNOWN_ISSUES_COUNT="$_known_issues_count_raw"
          fi
          ;;
      esac
      ;;
    *)
      KNOWN_ISSUES_STATUS="probe_error"
      KNOWN_ISSUES_COUNT=0
      ;;
  esac
fi

if [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
  _known_issues_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
  _known_issues_registry_count=$(json_object_array_length "${_known_issues_registry_json:-[]}")
  case "${_known_issues_registry_count:-}" in
    ''|*[!0-9]*)
      KNOWN_ISSUES_COUNT=0
      ;;
    *)
      KNOWN_ISSUES_COUNT="$_known_issues_registry_count"
      ;;
  esac
fi

if [ ! -f "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

if [ ! -r "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=unreadable"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

WRITER=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^writer:/ { sub(/^writer:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

RESULT=$(awk '
  BEGIN { in_fm=0; result_seen=0; status_seen=0; result=""; status="" }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^result:/ {
    result_seen=1
    result=$0
    sub(/^result:[[:space:]]*/, "", result)
    sub(/[[:space:]]+$/, "", result)
    next
  }
  in_fm && /^status:/ {
    status_seen=1
    status=$0
    sub(/^status:[[:space:]]*/, "", status)
    sub(/[[:space:]]+$/, "", status)
    next
  }
  END {
    if (result_seen) {
      print toupper(result)
    } else if (status_seen && (toupper(status) == "PASS" || toupper(status) == "FAIL" || toupper(status) == "PARTIAL")) {
      print toupper(status)
    }
  }
' "$VERIF_PATH" 2>/dev/null)

FAIL_COUNT=$(count_fail_rows_in_verification "$VERIF_PATH")

if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$SUMMARY_SCOPE_DIR" "$PLAN_SCOPE_DIR")
else
  DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$SUMMARY_SCOPE_DIR")
fi

ROUND_SOURCE_VERIFICATION_MISSING="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  if [ -n "${_gate_round:-}" ] && [ "$((10#${_gate_round}))" -gt 1 ] 2>/dev/null; then
    _expected_source_round=$(printf '%02d' "$((10#${_gate_round} - 1))")
    _expected_source_verification="$PHASE_DIR/remediation/qa/round-${_expected_source_round}/R${_expected_source_round}-VERIFICATION.md"
    if [ ! -r "$_expected_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  else
    _phase_source_verification=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
    if [ -z "$_phase_source_verification" ] || [ ! -r "$_phase_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  fi
fi

SOURCE_VERIFICATION_PATH=""
SOURCE_VERIFIED_AT_COMMIT=""
SOURCE_FAIL_IDS=""
SOURCE_FAIL_ROW_COUNT=0
ROUND_STARTED_AT_COMMIT=""
ROUND_STARTED_AFTER_SOURCE="true"
ROUND_ACTUAL_DIFF_PATHS=""
ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="false"
ROUND_ACTUAL_DIFF_PATHS_CANONICAL=""
ROUND_WORKTREE_PATHS_CANONICAL=""
ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=""
ROUND_INPUT_MODE="none"
ROUND_KNOWN_ISSUE_BACKLOG_PATH=""
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  _qa_remediation_state=$(bash "$SCRIPT_DIR/qa-remediation-state.sh" get "$PHASE_DIR" 2>/dev/null || true)
  SOURCE_VERIFICATION_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^source_verification_path=/{print $2; exit}')
  ROUND_STARTED_AT_COMMIT=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^round_started_at_commit=/{print $2; exit}')
  ROUND_INPUT_MODE=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^input_mode=/{print $2; exit}')
  ROUND_KNOWN_ISSUE_BACKLOG_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^known_issues_path=/{print $2; exit}')
  if [ -z "$SOURCE_VERIFICATION_PATH" ] || [ ! -r "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="true"
  fi
  if [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ "${_gate_stage:-none}" = "done" ] && [ "${ROUND_INPUT_MODE:-none}" = "none" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ -n "$SOURCE_VERIFICATION_PATH" ] && [ -r "$SOURCE_VERIFICATION_PATH" ]; then
    SOURCE_VERIFIED_AT_COMMIT=$(extract_verified_at_commit "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_IDS=$(extract_fail_ids_from_verification "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_ROW_COUNT=$(count_fail_rows_in_verification "$SOURCE_VERIFICATION_PATH")
  fi
  if [ -n "$SOURCE_VERIFIED_AT_COMMIT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && ! commit_is_ancestor_or_same "$GIT_ROOT" "$SOURCE_VERIFIED_AT_COMMIT" "$ROUND_STARTED_AT_COMMIT"; then
    ROUND_STARTED_AFTER_SOURCE="false"
  fi
  if [ -n "$GIT_ROOT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && git -C "$GIT_ROOT" cat-file -e "${ROUND_STARTED_AT_COMMIT}^{commit}" 2>/dev/null; then
    ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="true"
    ROUND_ACTUAL_DIFF_PATHS=$(git_diff_paths_since_commit "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
    ROUND_ACTUAL_DIFF_PATHS_CANONICAL=$(printf '%s\n' "$ROUND_ACTUAL_DIFF_PATHS" | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_WORKTREE_PATHS_CANONICAL=$(git_current_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=$(git_ignored_metadata_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
  fi
fi

METADATA_ONLY_ROUND="false"
ROUND_SUMMARY_MISSING="false"
ROUND_PLAN_MISSING="false"
ROUND_CHANGE_EVIDENCE_UNAVAILABLE="false"
ROUND_CHANGE_EVIDENCE_EMPTY="false"
ROUND_IGNORED_EVIDENCE_USED="false"
ROUND_SUMMARY_NONTERMINAL="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  _mo_has_code_changes="false"
  _mo_found_summary="false"
  _mo_all_recorded_paths=""
  _mo_structural_recorded_paths=""
  _mo_effective_files=""
  while IFS= read -r _mo_summary; do
    [ -f "$_mo_summary" ] || continue
    _mo_found_summary="true"
    _mo_status=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
    ' "$_mo_summary" 2>/dev/null)
    case "${_mo_status:-}" in
      complete|completed|partial|failed) ;;
      *) ROUND_SUMMARY_NONTERMINAL="true" ;;
    esac
    _mo_files=$(extract_frontmatter_array_items "$_mo_summary" files_modified)
    _mo_recorded_files=$(printf '%s\n' "$_mo_files" | canonicalize_recorded_paths "$PHASE_DIR")
    _mo_commit_hashes=$(extract_frontmatter_array_items "$_mo_summary" commit_hashes)
    _mo_commits=$(printf '%s\n' "$_mo_commit_hashes" | awk 'NF { count++ } END { print count + 0 }')
    _mo_commits="${_mo_commits:-0}"
    if [ -z "$_mo_files" ] && [ "$_mo_commits" -eq 0 ] 2>/dev/null; then
      ROUND_CHANGE_EVIDENCE_EMPTY="true"
    fi
    if [ -n "$_mo_files" ]; then
      _mo_structural_recorded_paths=$(printf '%s\n%s\n' "${_mo_structural_recorded_paths:-}" "$_mo_recorded_files")
      if [ -z "$_mo_recorded_files" ]; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      elif [ -n "$GIT_ROOT" ]; then
        if [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] || [ "$ROUND_ACTUAL_DIFF_PATHS_AVAILABLE" != "true" ]; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        _mo_effective_files=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL")
        if [ -z "$_mo_effective_files" ] || ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_effective_files"; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        if [ "$ROUND_IGNORED_EVIDENCE_USED" != "true" ] && [ -n "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL" ]; then
          _mo_without_ignored=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "")
          if ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_without_ignored"; then
            ROUND_IGNORED_EVIDENCE_USED="true"
          fi
        fi
      else
        _mo_effective_files="$_mo_recorded_files"
      fi
      _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_effective_files")
      if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_effective_files"; then
        _mo_has_code_changes="true"
      fi
    elif [ "$_mo_commits" -gt 0 ] 2>/dev/null; then
      if ! commit_hashes_resolve_cleanly "$GIT_ROOT" "$_mo_commit_hashes" \
        || [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] \
        || ! commit_hashes_are_round_local "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" "$_mo_commit_hashes"; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
      _mo_commit_files="$(commit_hashes_to_changed_files "$GIT_ROOT" "$_mo_commit_hashes" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))"
      if [ -n "$_mo_commit_files" ]; then
        _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_commit_files")
        if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_commit_files"; then
          _mo_has_code_changes="true"
        fi
      else
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
    fi
    [ "$_mo_has_code_changes" = "true" ] && break
  done < <(find "$SUMMARY_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  if [ "$_mo_found_summary" = "false" ]; then
    ROUND_SUMMARY_MISSING="true"
  elif [ "$_mo_has_code_changes" = "false" ]; then
    METADATA_ONLY_ROUND="true"
  fi
fi

PLAN_COUNT=0
while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
done < <(find "$PLAN_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))

PLANS_VERIFIED_COUNT=$(extract_frontmatter_array_items "$VERIF_PATH" plans_verified | awk '
  {
    if (!seen[$0]++) count++
  }
  END { print count + 0 }
' 2>/dev/null)
PLANS_VERIFIED_COUNT="${PLANS_VERIFIED_COUNT:-0}"

if [ "$IN_REMEDIATION" = "true" ] && [ "$PLAN_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$PLAN_COUNT" -eq 0 ] 2>/dev/null; then
  ROUND_PLAN_MISSING="true"
fi

ROUND_ALL_RECORDED_PATHS=$(printf '%s\n' "${_mo_all_recorded_paths:-}" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
ROUND_RECORDED_STRUCTURAL_PATHS=$(printf '%s\n' "${_mo_structural_recorded_paths:-}" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
ROUND_CLASSIFICATION_TYPES=""
ROUND_CLASSIFICATION_IDS=""
ROUND_CLASSIFICATION_PATHS=""
ROUND_CLASSIFICATION_TYPE_COUNT=0
ROUND_CLASSIFICATION_ID_COUNT=0
ROUND_CODE_FIX_COUNT=0
ROUND_DOC_FIX_COUNT=0
ROUND_PLAN_AMENDMENT_COUNT=0
ROUND_PLAN_AMENDMENT_SOURCE_PLANS=""
ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=0
ROUND_CLASSIFICATIONS_VALID=true
ROUND_KNOWN_ISSUE_INPUTS_JSON='[]'
ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON='[]'
ROUND_KNOWN_ISSUE_OUTCOMES_JSON='[]'
ROUND_CARRIED_KNOWN_ISSUES_JSON='[]'
ROUND_KNOWN_ISSUE_INPUT_COUNT=0
ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=0
ROUND_KNOWN_ISSUE_OUTCOME_COUNT=0
ROUND_CARRIED_KNOWN_ISSUE_COUNT=0
ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="false"
ROUND_KNOWN_ISSUES_VALID=true
ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=false
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  ROUND_CLASSIFICATION_TYPES=$(collect_fail_classification_types_in_dir "$PLAN_SCOPE_DIR")
  ROUND_CLASSIFICATION_IDS=$(collect_fail_classification_ids_in_dir "$PLAN_SCOPE_DIR" | (sort -u 2>/dev/null || sort -u))
  ROUND_CLASSIFICATION_PATHS=$(collect_fail_classification_paths_in_dir "$PLAN_SCOPE_DIR")
  ROUND_CLASSIFICATION_TYPE_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CLASSIFICATION_ID_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_IDS" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CODE_FIX_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "code-fix" { count++ } END { print count + 0 }')
  ROUND_DOC_FIX_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "doc-fix" { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "plan-amendment" { count++ } END { print count + 0 }')
  if [ "$ROUND_DOC_FIX_COUNT" -gt 0 ] 2>/dev/null; then
    ROUND_DOC_FIX_PATHS=$(printf '%s\n' "$ROUND_CLASSIFICATION_PATHS" | sed '/^[[:space:]]*$/d')
  else
    ROUND_DOC_FIX_PATHS=""
  fi
  ROUND_DOC_FIX_PATH_COUNT=$(printf '%s\n' "$ROUND_DOC_FIX_PATHS" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_SOURCE_PLANS=$(collect_fail_classification_source_plans_in_dir "$PLAN_SCOPE_DIR")
  ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=$(printf '%s\n' "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" | awk 'NF { count++ } END { print count + 0 }')

  if [ "$ROUND_CLASSIFICATION_ID_COUNT" -ne "$ROUND_CLASSIFICATION_TYPE_COUNT" ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null && ! fail_classification_types_are_valid <<< "$ROUND_CLASSIFICATION_TYPES"; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$ROUND_DOC_FIX_COUNT" -gt 0 ] 2>/dev/null && [ "$ROUND_DOC_FIX_PATH_COUNT" -ne "$ROUND_DOC_FIX_COUNT" ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$METADATA_ONLY_ROUND" = "true" ] && [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && [ "$ROUND_CLASSIFICATION_ID_COUNT" -eq 0 ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && {
    [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -ne "$SOURCE_FAIL_ROW_COUNT" ] 2>/dev/null \
      || ! classification_ids_cover_source_fail_ids "$SOURCE_FAIL_IDS" "$ROUND_CLASSIFICATION_IDS";
  }; then
    ROUND_CLASSIFICATIONS_VALID=false
  fi
  if [ -z "$GIT_ROOT" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
    ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
  fi

  ROUND_KNOWN_ISSUE_INPUTS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issues_input issue)
  ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issue_resolutions resolution)
  ROUND_KNOWN_ISSUE_OUTCOMES_JSON=$(collect_frontmatter_json_object_array_in_dir "$SUMMARY_SCOPE_DIR" summary known_issue_outcomes outcome)
  ROUND_CARRIED_KNOWN_ISSUES_JSON=$(load_known_issue_registry_json "$ROUND_KNOWN_ISSUE_BACKLOG_PATH")
  ROUND_KNOWN_ISSUE_INPUT_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_INPUTS_JSON")
  ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON")
  ROUND_KNOWN_ISSUE_OUTCOME_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON")
  ROUND_CARRIED_KNOWN_ISSUE_COUNT=$(json_object_array_length "$ROUND_CARRIED_KNOWN_ISSUES_JSON")

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_RESOLUTION_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null \
    || [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] \
    || [ "${ROUND_INPUT_MODE:-none}" = "both" ]; then
    ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="true"
  fi

  if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ]; then
    if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null && ! json_object_array_covers_full_issue_objects "$ROUND_CARRIED_KNOWN_ISSUES_JSON" "$ROUND_KNOWN_ISSUE_INPUTS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_dispositions_match "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" && [ "$KNOWN_ISSUES_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    fi
  fi

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null && [ "$SOURCE_FAIL_ROW_COUNT" -eq 0 ] 2>/dev/null && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi

  if paths_include_process_exception_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
    ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=true
  elif [ "$METADATA_ONLY_ROUND" = "true" ] \
    && [ "$ROUND_CHANGE_EVIDENCE_UNAVAILABLE" = "true" ] \
    && paths_are_process_exception_evidence_artifacts "$PHASE_DIR" <<< "$ROUND_RECORDED_STRUCTURAL_PATHS"; then
    ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=true
  fi
fi

EXEMPT_FAIL_COUNT=0
UNRESOLVED_FAIL_COUNT="$FAIL_COUNT"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
  && [ "$ROUND_CLASSIFICATIONS_VALID" = "true" ]; then
  _exempt_fail_count=$(count_fail_ids_with_round_classifications "$VERIF_PATH" "$PLAN_SCOPE_DIR" 2>/dev/null || printf '0')
  case "${_exempt_fail_count:-}" in
    ''|*[!0-9]*) _exempt_fail_count=0 ;;
  esac
  if [ "$_exempt_fail_count" -le "$FAIL_COUNT" ] 2>/dev/null; then
    EXEMPT_FAIL_COUNT="$_exempt_fail_count"
    UNRESOLVED_FAIL_COUNT=$((FAIL_COUNT - EXEMPT_FAIL_COUNT))
  fi
fi

echo "qa_gate_writer=${WRITER:-missing}"
echo "qa_gate_result=${RESULT:-missing}"
echo "qa_gate_fail_count=$FAIL_COUNT"
echo "qa_gate_deviation_count=$DEVIATION_COUNT"
echo "qa_gate_known_issue_count=$KNOWN_ISSUES_COUNT"
echo "qa_gate_plan_count=$PLAN_COUNT"
echo "qa_gate_plans_verified_count=$PLANS_VERIFIED_COUNT"
if [ "$ROUND_IGNORED_EVIDENCE_USED" = "true" ]; then
  echo "qa_gate_planning_ignored_evidence=true"
fi

if [ -z "$WRITER" ] || [ "$WRITER" != "write-verification.sh" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

if [ -z "$RESULT" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

CLASSIFIED_FAIL_EXEMPTION_REPORTED=false
case "$RESULT" in
  FAIL|PARTIAL)
    if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
      && [ "$ROUND_CLASSIFICATIONS_VALID" = "true" ] \
      && [ "$FAIL_COUNT" -gt 0 ] 2>/dev/null \
      && [ "$UNRESOLVED_FAIL_COUNT" -eq 0 ] 2>/dev/null; then
      echo "qa_gate_classified_fail_exemption=true"
      echo "qa_gate_exempt_fail_count=$EXEMPT_FAIL_COUNT"
      CLASSIFIED_FAIL_EXEMPTION_REPORTED=true
      RESULT=PASS
    else
      if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
        && [ "$ROUND_CLASSIFICATIONS_VALID" != "true" ]; then
        echo "qa_gate_classifications_invalid=true"
      fi
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
      exit 0
    fi
    ;;
esac

case "$RESULT" in
  PASS)
    if [ "$EXEMPT_FAIL_COUNT" -gt 0 ] 2>/dev/null && [ "$CLASSIFIED_FAIL_EXEMPTION_REPORTED" != "true" ]; then
      echo "qa_gate_classified_fail_exemption=true"
      echo "qa_gate_exempt_fail_count=$EXEMPT_FAIL_COUNT"
    fi
    if [ "$UNRESOLVED_FAIL_COUNT" -gt 0 ] 2>/dev/null; then
      echo "qa_gate_fail_count_positive=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_NONTERMINAL" = "true" ]; then
      echo "qa_gate_round_summary_nonterminal=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SOURCE_VERIFICATION_MISSING" = "true" ]; then
      echo "qa_gate_source_verification_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_MISSING" = "true" ]; then
      echo "qa_gate_round_summary_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_PLAN_MISSING" = "true" ]; then
      echo "qa_gate_round_plan_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_UNAVAILABLE" = "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
      echo "qa_gate_round_change_evidence_unavailable=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_EMPTY" = "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
      echo "qa_gate_round_change_evidence_empty=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
      && [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
      && [ "$ROUND_KNOWN_ISSUES_VALID" != "true" ]; then
      echo "qa_gate_known_issue_contract_invalid=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_CLASSIFICATIONS_VALID" != "true" ]; then
      if [ "$METADATA_ONLY_ROUND" = "true" ]; then
        PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$PHASE_DIR")
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
      fi
      echo "qa_gate_classifications_invalid=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$METADATA_ONLY_ROUND" != "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null && ! paths_include_code_fix_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
      echo "qa_gate_code_fix_evidence_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_PLAN_AMENDMENT_COUNT" -gt 0 ] 2>/dev/null && [ "${_gate_stage:-none}" != "done" ] && {
      [ "$ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT" -ne "$ROUND_PLAN_AMENDMENT_COUNT" ] 2>/dev/null \
        || ! plan_amendment_source_plans_are_valid "$PHASE_DIR" <<< "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" \
        || ! paths_cover_required_original_plan_artifacts "$PHASE_DIR" "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" <<< "$ROUND_ALL_RECORDED_PATHS";
    }; then
      echo "qa_gate_plan_amendment_evidence_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$DEVIATION_COUNT" -gt 0 ] && { [ "$IN_REMEDIATION" = "false" ] || [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; }; then
      echo "qa_gate_deviation_override=true"
      if [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      fi
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$METADATA_ONLY_ROUND" = "true" ]; then
      PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$PHASE_DIR")
      if [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_metadata_only_code_fix=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$ROUND_DOC_FIX_COUNT" -gt 0 ] 2>/dev/null \
        && ! paths_include_documentation_fix_evidence "$PHASE_DIR" "$ROUND_DOC_FIX_PATHS" <<< "$ROUND_ALL_RECORDED_PATHS"; then
        echo "qa_gate_doc_fix_evidence_missing=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$ROUND_DOC_FIX_COUNT" -gt 0 ] 2>/dev/null; then
        echo "qa_gate_routing=PROCEED_TO_UAT"
      elif [ "$ROUND_PLAN_AMENDMENT_COUNT" -eq 0 ] 2>/dev/null \
        && [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null \
        && [ "$ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID" != "true" ]; then
        echo "qa_gate_process_exception_evidence_missing=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
        echo "qa_gate_routing=QA_RERUN_REQUIRED"
      elif [ "$KNOWN_ISSUES_STATUS" = "malformed" ] || [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
        echo "qa_gate_known_issues_override=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
        _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
        if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
           && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
           && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
          echo "qa_gate_known_issues_all_addressed=true"
          echo "qa_gate_routing=PROCEED_TO_UAT"
        else
          echo "qa_gate_known_issues_override=true"
          echo "qa_gate_routing=REMEDIATION_REQUIRED"
        fi
      else
        echo "qa_gate_routing=PROCEED_TO_UAT"
      fi
    elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
      echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "malformed" ] || [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
      echo "qa_gate_known_issues_override=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
      _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
      if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
         && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
         && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
        echo "qa_gate_known_issues_all_addressed=true"
        echo "qa_gate_routing=PROCEED_TO_UAT"
      else
        echo "qa_gate_known_issues_override=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      fi
    else
      echo "qa_gate_routing=PROCEED_TO_UAT"
    fi
    ;;
  FAIL|PARTIAL)
    echo "qa_gate_routing=REMEDIATION_REQUIRED"
    ;;
  *)
    echo "qa_gate_routing=QA_RERUN_REQUIRED"
    ;;
esac

exit 0
