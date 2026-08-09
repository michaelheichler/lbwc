#!/bin/bash
set -u
_pd_normal_exit=false
_pd_output_file=
_pd_error_reason=
exec 3>&1
if _pd_output_file=$(mktemp "${TMPDIR:-/tmp}/lbwc-phase-detect.XXXXXX" 2>/dev/null) &&
   [ -n "$_pd_output_file" ] && [ -f "$_pd_output_file" ]; then
  if ! exec >"$_pd_output_file"; then
    rm -f "$_pd_output_file"
    _pd_output_file=
    printf '%s\n' 'phase_detect_error=true' 'phase_detect_reason=setup_failed' >&3
    exit 1
  fi
else
  [ -n "$_pd_output_file" ] && rm -f "$_pd_output_file"
  _pd_output_file=
  printf '%s\n' 'phase_detect_error=true' 'phase_detect_reason=setup_failed' >&3
  exit 1
fi
trap '
  if [ "$_pd_normal_exit" = true ] && [ -n "$_pd_output_file" ] && [ -f "$_pd_output_file" ]; then
    cat "$_pd_output_file" >&3
  elif [ "$_pd_error_reason" = setup_failed ]; then
    printf "%s\n" "phase_detect_error=true" "phase_detect_reason=setup_failed" >&3
  else
    printf "%s\n" "phase_detect_error=true" >&3
  fi
  [ -n "$_pd_output_file" ] && rm -f "$_pd_output_file"
  [ "$_pd_error_reason" = setup_failed ] && exit 1
  exit 0
' EXIT

_SCRIPT_DIR_PD="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
if ! . "$_SCRIPT_DIR_PD/lib/lbwc-settings.sh"; then
  _pd_error_reason=setup_failed
  exit 1
fi

count_phase_plans() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
    [ -f "$f" ] && count=$((count + 1))
  done
  echo "$count"
}

_pd_uat_frontmatter_phase_num() {
  local uat_file="$1"
  [ -n "$uat_file" ] && [ -f "$uat_file" ] || return 0
  awk '
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      lower = tolower($0)
      if (lower ~ /^phase:[[:space:]]*[0-9]+[[:space:]]*$/) {
        value = $0
        sub(/^[^:]*:[[:space:]]*/, "", value)
        gsub(/[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$uat_file" 2>/dev/null || true
}

_pd_phase_num_from_artifact_glob() {
  local dir="$1"
  local artifact num
  artifact=$(find "$dir" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name '[0-9]*-SUMMARY.md' -o -name '[0-9]*-UAT.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort) | head -1)
  [ -n "$artifact" ] || return 0
  num=$(basename "$artifact" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$' && echo "$num"
}

_pd_echo_num_if_valid() {
  local num="$1"
  [ -n "$num" ] && echo "$num" | grep -qE '^[0-9]+$' || return 1
  echo "$num"
}

resolve_phase_number_from_phase_dir() {
  local dir="$1"
  local base num uat_file

  base=$(basename "$dir")
  num=$(printf '%s' "$base" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
  _pd_echo_num_if_valid "$num" && return 0

  num=$(_pd_phase_num_from_artifact_glob "$dir")
  _pd_echo_num_if_valid "$num" && return 0

  uat_file=$(find "$dir" -maxdepth 1 ! -name '.*' -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' 2>/dev/null | (sort -V 2>/dev/null || sort) | head -1)
  num=$(_pd_uat_frontmatter_phase_num "$uat_file")
  _pd_echo_num_if_valid "$num" && return 0

  if type current_uat &>/dev/null; then
    uat_file=$(current_uat "$dir")
  else
    uat_file=""
  fi
  num=$(_pd_uat_frontmatter_phase_num "$uat_file")
  _pd_echo_num_if_valid "$num" && return 0

  echo ""
}

if [ -f "$_SCRIPT_DIR_PD/summary-utils.sh" ]; then
  . "$_SCRIPT_DIR_PD/summary-utils.sh"
fi
if [ -f "$_SCRIPT_DIR_PD/uat-utils.sh" ]; then
  . "$_SCRIPT_DIR_PD/uat-utils.sh"
fi
if [ -f "$_SCRIPT_DIR_PD/verification-freshness.sh" ]; then
  . "$_SCRIPT_DIR_PD/verification-freshness.sh"
else
  extract_verified_at_commit() { :; }
  verification_is_stale() { return 0; }
fi

if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-support.sh"; then
  exit 0
fi
JQ_AVAILABLE=false
if command -v jq &>/dev/null; then
  JQ_AVAILABLE=true
fi
echo "jq_available=$JQ_AVAILABLE"

if [ -d "$PLANNING_DIR" ]; then
  echo "planning_dir_exists=true"
else
  echo "planning_dir_exists=false"
  echo "project_exists=false"
  echo "phases_dir=none"
  echo "phase_count=0"
  echo "next_phase=none"
  echo "next_phase_slug=none"
  echo "next_phase_state=no_phases"
  echo "next_phase_plans=0"
  echo "next_phase_summaries=0"
  echo "uat_issues_phase=none"
  echo "uat_issues_slug=none"
  echo "uat_issues_major_or_higher=false"
  echo "uat_issues_phases="
  echo "uat_issues_count=0"
  echo "uat_blocking_phase=none"
  echo "uat_blocking_slug=none"
  echo "uat_blocking_status=none"
  echo "uat_blocking_file=none"
  echo "uat_file=none"
  echo "uat_round_count=0"
  echo "has_shipped_milestones=false"
  echo "needs_milestone_rename=false"
  echo "milestone_uat_issues=false"
  echo "milestone_uat_phase=none"
  echo "milestone_uat_slug=none"
  echo "milestone_uat_major_or_higher=false"
  echo "milestone_uat_phase_dir=none"
  echo "milestone_uat_count=0"
  echo "milestone_uat_phase_dirs="
  echo "config_effort=balanced"
  echo "config_autonomy=standard"
  echo "config_auto_commit=true"
  echo "config_planning_tracking=manual"
  echo "config_auto_push=never"
  echo "config_verification_tier=standard"
  echo "config_prefer_teams=auto"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "config_require_phase_discussion=false"
  echo "config_auto_uat=false"
  echo "has_unverified_phases=false"
  echo "first_unverified_phase="
  echo "first_unverified_slug="
  echo "first_qa_attention_phase="
  echo "first_qa_attention_slug="
  echo "qa_attention_status=none"
  echo "qa_attention_reason=none"
  echo "qa_status=none"
  echo "qa_reason=none"
  echo "qa_after_uat_dormant=false"
  echo "qa_round=00"
  echo "has_codebase_map=false"
  echo "brownfield=false"
  echo "execution_state=none"
  echo "phase_detect_complete=true"
  _pd_normal_exit=true
  exit 0
fi

PROJECT_EXISTS=false
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  if ! grep -q '{project-description}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    PROJECT_EXISTS=true
  fi
fi
echo "project_exists=$PROJECT_EXISTS"

PHASES_DIR="$PLANNING_DIR/phases"
echo "phases_dir=$PHASES_DIR"

HAS_SHIPPED_MILESTONES=false
NEEDS_MILESTONE_RENAME=false
MILESTONE_SCAN_DIRS=()
if [ -d "$PLANNING_DIR/milestones" ]; then
  MILESTONE_DIRS=()
  while IFS= read -r _ms_dir; do
    [ -n "$_ms_dir" ] || continue
    MILESTONE_DIRS+=("${_ms_dir%/}/")
  done < <(list_child_dirs_sorted "$PLANNING_DIR/milestones")

  if [ ${#MILESTONE_DIRS[@]} -gt 0 ]; then
  for _ms_dir in "${MILESTONE_DIRS[@]}"; do
    [ -d "$_ms_dir" ] || continue

    if [ -f "${_ms_dir}SHIPPED.md" ]; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
      continue
    fi

    if [ -d "${_ms_dir}phases" ] && ls -d "${_ms_dir}phases"/*/ >/dev/null 2>&1; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
    fi
  done
  fi
  [ -d "$PLANNING_DIR/milestones/default" ] && NEEDS_MILESTONE_RENAME=true
fi
echo "has_shipped_milestones=$HAS_SHIPPED_MILESTONES"
echo "needs_milestone_rename=$NEEDS_MILESTONE_RENAME"

CFG_REQUIRE_PHASE_DISCUSSION="false"
CFG_AUTO_UAT_EARLY="false"
CONFIG_FILE_EARLY="$PLANNING_DIR/config.json"
if [ "$JQ_AVAILABLE" = true ]; then
  MERGED_CONFIG_EARLY=$(lbwc_merged_config "$CONFIG_FILE_EARLY")
  _rpd=$(jq -r 'if .require_phase_discussion == null then false else .require_phase_discussion end' <<< "$MERGED_CONFIG_EARLY" 2>/dev/null) || true
  [ -n "${_rpd:-}" ] && CFG_REQUIRE_PHASE_DISCUSSION="$_rpd"
  _aue=$(jq -r 'if .auto_uat == null then false else .auto_uat end' <<< "$MERGED_CONFIG_EARLY" 2>/dev/null) || true
  [ -n "${_aue:-}" ] && CFG_AUTO_UAT_EARLY="$_aue"
fi
: "$CFG_REQUIRE_PHASE_DISCUSSION" "$CFG_AUTO_UAT_EARLY"

if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-active-routing.sh"; then
  exit 0
fi
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-qa-routing.sh"; then
  exit 0
fi
echo "phase_count=$PHASE_COUNT"
echo "next_phase=$NEXT_PHASE"
echo "next_phase_slug=$NEXT_PHASE_SLUG"
echo "next_phase_state=$NEXT_PHASE_STATE"
echo "next_phase_plans=$NEXT_PHASE_PLANS"
echo "next_phase_summaries=$NEXT_PHASE_SUMMARIES"
echo "has_unverified_phases=$HAS_UNVERIFIED_PHASES"
echo "first_unverified_phase=$FIRST_UNVERIFIED_PHASE"
echo "first_unverified_slug=$FIRST_UNVERIFIED_SLUG"
echo "first_qa_attention_phase=$FIRST_QA_ATTENTION_PHASE"
echo "first_qa_attention_slug=$FIRST_QA_ATTENTION_SLUG"
echo "qa_attention_status=$QA_ATTENTION_STATUS"
echo "qa_attention_reason=$QA_ATTENTION_REASON"
echo "qa_status=$QA_STATUS"
echo "qa_reason=$QA_REASON"
echo "qa_after_uat_dormant=$QA_AFTER_UAT_DORMANT"
echo "qa_round=$QA_ROUND"
echo "uat_issues_phase=$UAT_ISSUES_PHASE"
echo "uat_issues_slug=$UAT_ISSUES_SLUG"
echo "uat_issues_major_or_higher=$UAT_ISSUES_MAJOR_OR_HIGHER"
echo "uat_issues_phases=$UAT_ISSUES_PHASES"
echo "uat_issues_count=$UAT_ISSUES_COUNT"
echo "uat_blocking_phase=$UAT_BLOCKING_PHASE"
echo "uat_blocking_slug=$UAT_BLOCKING_SLUG"
echo "uat_blocking_status=$UAT_BLOCKING_STATUS"
echo "uat_blocking_file=$UAT_BLOCKING_RELATIVE_FILE"
echo "uat_file=$UAT_ISSUES_RELATIVE_FILE"
echo "uat_round_count=$UAT_ROUND_COUNT"
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-milestone-recovery.sh"; then
  exit 0
fi
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-environment-output.sh"; then
  exit 0
fi
if ! phase_detect_output_milestone_extraction; then
  exit 0
fi
echo "phase_detect_complete=true"
_pd_normal_exit=true
exit 0
