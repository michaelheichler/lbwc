#!/bin/bash
set -u

MISNAMED_PLANS=false
if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _mn_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_mn_dir" ] || continue
    if find "$_mn_dir" -maxdepth 1 \( -iname 'PLAN-[0-9].md' -o -iname 'PLAN-[0-9][0-9].md' -o -iname 'PLAN-[0-9]-SUMMARY.md' -o -iname 'PLAN-[0-9][0-9]-SUMMARY.md' -o -iname 'PLAN-[0-9]-CONTEXT.md' -o -iname 'PLAN-[0-9][0-9]-CONTEXT.md' -o -iname 'SUMMARY-[0-9].md' -o -iname 'SUMMARY-[0-9][0-9].md' -o -iname 'CONTEXT-[0-9].md' -o -iname 'CONTEXT-[0-9][0-9].md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*\.md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*-summary\.md' -o -iregex '.*/plan-[0-9][0-9][0-9][0-9]*-context\.md' -o -iregex '.*/summary-[0-9][0-9][0-9][0-9]*\.md' -o -iregex '.*/context-[0-9][0-9][0-9][0-9]*\.md' \) 2>/dev/null | grep -q .; then
      MISNAMED_PLANS=true
      break
    fi
  done
fi
echo "misnamed_plans=$MISNAMED_PLANS"

REMEDIATED_MS_PATHS=""
if [ -d "$PHASES_DIR" ] && [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _rx_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_rx_dir" ] || continue
    _rx_ctx=""
    for _rx_f in "$_rx_dir"[0-9]*-CONTEXT.md; do
      [ -f "$_rx_f" ] || continue
      _rx_ctx="$_rx_f"
      break
    done
    [ -f "$_rx_ctx" ] || continue
    _rx_src_ms=$(awk '/^source_milestone:/{gsub(/^source_milestone:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit}' "$_rx_ctx" 2>/dev/null || true)
    _rx_src_ph=$(awk '/^source_phase:/{gsub(/^source_phase:[[:space:]]*/,""); gsub(/[[:space:]]*$/,""); print; exit}' "$_rx_ctx" 2>/dev/null || true)
    if [ -n "$_rx_src_ms" ] && [ -n "$_rx_src_ph" ]; then
      _rx_resolved="$PLANNING_DIR/milestones/$_rx_src_ms/phases/$_rx_src_ph"
      REMEDIATED_MS_PATHS="${REMEDIATED_MS_PATHS:+${REMEDIATED_MS_PATHS}$'\n'}$_rx_resolved"
    fi
  done
fi

MILESTONE_UAT_ISSUES=false
MILESTONE_UAT_PHASE="none"
MILESTONE_UAT_SLUG="none"
MILESTONE_UAT_MAJOR_OR_HIGHER=false
MILESTONE_UAT_PHASE_DIR="none"
MILESTONE_UAT_COUNT=0
MILESTONE_UAT_PHASE_DIRS=""

if [ "$UAT_ISSUES_PHASE" = "none" ] && { [ "$NEXT_PHASE_STATE" = "all_done" ] || [ "$NEXT_PHASE_STATE" = "no_phases" ]; } && [ "$HAS_SHIPPED_MILESTONES" = true ] && [ ${#MILESTONE_SCAN_DIRS[@]} -gt 0 ]; then
  for _ms_dir in "${MILESTONE_SCAN_DIRS[@]}"; do
    [ -d "$_ms_dir" ] || continue
    [ -d "${_ms_dir}phases" ] || continue

    MS_SLUG=$(basename "$_ms_dir")
    MS_PHASE_DIRS=()
    while IFS= read -r _ms_phase_dir; do
      [ -n "$_ms_phase_dir" ] || continue
      MS_PHASE_DIRS+=("${_ms_phase_dir%/}/")
    done < <(list_child_dirs_sorted "${_ms_dir}phases")

    _ms_issue_count=0
    _ms_issue_phase="none"
    _ms_issue_phase_dirs=""
    _ms_issue_major_or_higher=false

    if [ ${#MS_PHASE_DIRS[@]} -gt 0 ]; then
    for _ms_phase_dir in "${MS_PHASE_DIRS[@]}"; do
      [ -d "$_ms_phase_dir" ] || continue
      _ms_dirname=$(basename "$_ms_phase_dir")
      _ms_num=$(resolve_phase_number_from_phase_dir "$_ms_phase_dir")

      if [ -z "$_ms_num" ] || ! echo "$_ms_num" | grep -qE '^[0-9]+$'; then
        continue
      fi

      [ -f "${_ms_phase_dir}.remediated" ] && continue

      _ms_phase_canonical="${_ms_phase_dir%/}"
      if [ -n "$REMEDIATED_MS_PATHS" ] && printf '%s\n' "$REMEDIATED_MS_PATHS" | grep -Fqx -- "$_ms_phase_canonical"; then
        continue
      fi

      _ms_plans=$(count_phase_plans "$_ms_phase_dir")
      _ms_summaries=$(count_complete_summaries "$_ms_phase_dir")
      if [ "$_ms_plans" -eq 0 ] || [ "$_ms_summaries" -lt "$_ms_plans" ]; then
        continue
      fi

      _ms_uat=$(current_uat "$_ms_phase_dir")
      if [ -f "$_ms_uat" ]; then
        _ms_uat_status=$(uat_file_status_class "$_ms_uat" 2>/dev/null || printf '%s\n' "none")
        if [ "$_ms_uat_status" = "issues_found" ]; then
          _ms_issue_count=$((_ms_issue_count + 1))
          if [ "$_ms_issue_phase" = "none" ]; then
            _ms_issue_phase="$_ms_num"
          fi
          _ms_issue_phase_dirs="${_ms_issue_phase_dirs:+${_ms_issue_phase_dirs}|}${_ms_phase_dir%/}"

          _ms_critical=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$_ms_uat" || true)
          _ms_major=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$_ms_uat" || true)
          _ms_minor=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$_ms_uat" || true)
          _ms_tagged=$((_ms_critical + _ms_major + _ms_minor))

          if [ "$_ms_critical" -gt 0 ] || [ "$_ms_major" -gt 0 ] || [ "$_ms_tagged" -eq 0 ]; then
            _ms_issue_major_or_higher=true
          fi
        fi
      fi
    done
    fi

    if [ "$_ms_issue_count" -gt 0 ]; then
      MILESTONE_UAT_ISSUES=true
      MILESTONE_UAT_PHASE="$_ms_issue_phase"
      MILESTONE_UAT_SLUG="$MS_SLUG"
      MILESTONE_UAT_PHASE_DIR=$(echo "$_ms_issue_phase_dirs" | cut -d'|' -f1)
      MILESTONE_UAT_MAJOR_OR_HIGHER="$_ms_issue_major_or_higher"
      MILESTONE_UAT_COUNT="$_ms_issue_count"
      MILESTONE_UAT_PHASE_DIRS="$_ms_issue_phase_dirs"
    fi
  done
fi

echo "milestone_uat_issues=$MILESTONE_UAT_ISSUES"
echo "milestone_uat_phase=$MILESTONE_UAT_PHASE"
echo "milestone_uat_slug=$MILESTONE_UAT_SLUG"
echo "milestone_uat_major_or_higher=$MILESTONE_UAT_MAJOR_OR_HIGHER"
echo "milestone_uat_phase_dir=$MILESTONE_UAT_PHASE_DIR"
echo "milestone_uat_count=$MILESTONE_UAT_COUNT"
echo "milestone_uat_phase_dirs=$MILESTONE_UAT_PHASE_DIRS"

_PD_ISSUE_PARSER="$_SCRIPT_DIR_PD/parse-uat-issues.awk"
_PD_ROUND_ID_PARSER="$_SCRIPT_DIR_PD/extract-round-issue-ids.awk"

_pd_reset_uat_extraction() {
  declare -g _PD_EXTRACT_LINES=""
  declare -g _PD_EXTRACT_COUNT=0
  declare -g _PD_EXTRACT_ERROR=""
  declare -g _PD_BASE_ISSUES=""
  declare -g _PD_ROUND_IDS=""
}

_pd_read_base_uat_issues() {
  local uat_file="$1" base_count=0 frontmatter_issues

  _PD_BASE_ISSUES=$(awk -f "$_PD_ISSUE_PARSER" "$uat_file" 2>/dev/null) || _PD_BASE_ISSUES=""
  if [ -n "$_PD_BASE_ISSUES" ]; then
    base_count=$(printf '%s\n' "$_PD_BASE_ISSUES" | wc -l | tr -d ' ')
  fi
  [ "$base_count" -eq 0 ] || return 0
  frontmatter_issues=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^[[:space:]]*issues[[:space:]]*:/ {
      val=$0; sub(/^[^:]*:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)
      print val; exit
    }
  ' "$uat_file" 2>/dev/null || true)
  frontmatter_issues=$(printf '%s' "$frontmatter_issues" | tr -d '[:space:]')
  if [ -n "$frontmatter_issues" ] && [ "$frontmatter_issues" != "0" ]; then
    _PD_EXTRACT_ERROR="true"
  fi
  return 1
}

_pd_add_round_issue_ids() {
  local round_file="$1" round_num="$2" issue_id

  while IFS= read -r issue_id; do
    [ -n "$issue_id" ] || continue
    _PD_ROUND_IDS="${_PD_ROUND_IDS}${_PD_ROUND_IDS:+$'\n'}${issue_id} ${round_num}"
  done < <(awk -f "$_PD_ROUND_ID_PARSER" "$round_file" 2>/dev/null)
}

_pd_collect_legacy_round_ids() {
  local phase_dir="$1" phase_num="$2" uat_file="$3"
  local round_file round_num

  for round_file in "${phase_dir}${phase_num}"-UAT-round-*.md; do
    [ -f "$round_file" ] || continue
    [ "$round_file" = "$uat_file" ] && continue
    round_num=$(basename "$round_file" | sed "s/^${phase_num}-UAT-round-0*\\([0-9]*\\)\\.md$/\\1/")
    if [ -n "$round_num" ] && echo "$round_num" | grep -qE '^[0-9]+$'; then
      _pd_add_round_issue_ids "$round_file" "$round_num"
    fi
  done
}

_pd_collect_round_dir_ids() {
  local phase_dir="$1" uat_file="$2"
  local round_file round_num

  for round_file in "${phase_dir}"remediation/uat/round-*/R*-UAT.md; do
    [ -f "$round_file" ] || continue
    [ "$round_file" = "$uat_file" ] && continue
    round_num=$(basename "$round_file" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
    if [ -n "$round_num" ] && echo "$round_num" | grep -qE '^[0-9]+$'; then
      _pd_add_round_issue_ids "$round_file" "$round_num"
    fi
  done
}

_pd_format_uat_issue_lines() {
  local current_round="$1" issue_id severity description past_rounds failed_in line

  while IFS='|' read -r issue_id severity description; do
    [ -n "$issue_id" ] || continue
    past_rounds=""
    if [ -n "$_PD_ROUND_IDS" ]; then
      past_rounds=$(printf '%s\n' "$_PD_ROUND_IDS" | awk -v id="$issue_id" '$1 == id { print $2 }' | sort -n | paste -sd, -) || past_rounds=""
    fi
    failed_in="$current_round"
    [ -z "$past_rounds" ] || failed_in="${past_rounds},${current_round}"
    line="${issue_id}|${severity}|${description}|${failed_in}"
    _PD_EXTRACT_LINES="${_PD_EXTRACT_LINES}${_PD_EXTRACT_LINES:+$'\n'}${line}"
    _PD_EXTRACT_COUNT=$((_PD_EXTRACT_COUNT + 1))
  done < <(printf '%s\n' "$_PD_BASE_ISSUES")
}

_pd_build_uat_issue_lines() {
  local phase_dir="$1" phase_num="$2" uat_file="$3" current_round="$4"

  _pd_reset_uat_extraction
  if [ ! -f "$_PD_ISSUE_PARSER" ] || [ ! -f "$_PD_ROUND_ID_PARSER" ]; then
    _PD_EXTRACT_ERROR="true"
    return 0
  fi
  _pd_read_base_uat_issues "$uat_file" || return 0
  case "$phase_dir" in */) ;; *) phase_dir="$phase_dir/" ;; esac
  _pd_collect_legacy_round_ids "$phase_dir" "$phase_num" "$uat_file"
  _pd_collect_round_dir_ids "$phase_dir" "$uat_file"
  _pd_format_uat_issue_lines "$current_round"
}

_pd_resolve_milestone_uat_file() {
  local phase_dir="$1"

  declare -g _pd_ms_uat=""
  if type current_uat &>/dev/null; then
    _pd_ms_uat=$(current_uat "$phase_dir")
  elif type latest_non_source_uat &>/dev/null; then
    _pd_ms_uat=$(latest_non_source_uat "$phase_dir")
  fi
  [ -n "$_pd_ms_uat" ] && [ -f "$_pd_ms_uat" ]
}

_pd_resolve_milestone_uat_metadata() {
  local phase_dir="$1"
  local is_round_dir=false

  _pd_resolve_milestone_uat_file "$phase_dir" || return 1
  declare -g _pd_ms_phase _pd_ms_fname _pd_ms_round
  _pd_ms_phase=$(resolve_phase_number_from_phase_dir "$phase_dir")
  _pd_ms_fname=$(basename "$_pd_ms_uat")
  _pd_ms_round=""
  case "$_pd_ms_uat" in
    */remediation/uat/round-*/R*-UAT.md)
      is_round_dir=true
      _pd_ms_round=$(basename "$_pd_ms_uat" | sed 's/^R0*\([0-9]*\)-UAT\.md$/\1/')
      _pd_ms_round="${_pd_ms_round:-0}"
      ;;
  esac
  if [ -z "$_pd_ms_round" ] || ! echo "$_pd_ms_round" | grep -qE '^[0-9]+$'; then
    _pd_ms_round=1
  fi
  if [ -n "$_pd_ms_phase" ] && type count_uat_rounds &>/dev/null && [ "$is_round_dir" = false ]; then
    _pd_ms_round=$(( $(count_uat_rounds "$phase_dir" "$_pd_ms_phase") + 1 ))
  fi
}

_pd_emit_milestone_uat() {
  local phase_dir="$1"

  echo "milestone_phase_dir=$phase_dir"
  if ! _pd_resolve_milestone_uat_metadata "$phase_dir"; then
    echo "uat_extract_error=true dir=$phase_dir"
    return 0
  fi
  if [ -n "$_pd_ms_phase" ]; then
    _pd_build_uat_issue_lines "$phase_dir" "$_pd_ms_phase" "$_pd_ms_uat" "$_pd_ms_round"
  else
    _pd_reset_uat_extraction
    _PD_EXTRACT_ERROR="true"
  fi
  if [ -n "$_PD_EXTRACT_ERROR" ]; then
    echo "uat_extract_error=true dir=$phase_dir"
    return 0
  fi
  echo "uat_phase=${_pd_ms_phase} uat_issues_total=${_PD_EXTRACT_COUNT} uat_round=${_pd_ms_round} uat_file=${_pd_ms_fname}"
  [ "$_PD_EXTRACT_COUNT" -eq 0 ] || printf '%s\n' "$_PD_EXTRACT_LINES"
}

phase_detect_output_milestone_extraction() {
  local old_ifs phase_dir

  [ "$MILESTONE_UAT_ISSUES" = true ] && [ -n "$MILESTONE_UAT_PHASE_DIRS" ] || return 0
  echo "---MILESTONE_UAT_EXTRACT_START---"
  old_ifs="$IFS"
  IFS='|'
  for phase_dir in $MILESTONE_UAT_PHASE_DIRS; do
    IFS="$old_ifs"
    [ -d "$phase_dir" ] || continue
    _pd_emit_milestone_uat "$phase_dir"
    echo "---"
  done
  IFS="$old_ifs"
  echo "---MILESTONE_UAT_EXTRACT_END---"
}
: "$_PD_ISSUE_PARSER" "$_PD_ROUND_ID_PARSER"
