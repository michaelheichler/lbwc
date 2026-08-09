#!/bin/bash
set -u

PHASE_COUNT=0
NEXT_PHASE="none"
NEXT_PHASE_SLUG="none"
NEXT_PHASE_STATE="no_phases"
NEXT_PHASE_PLANS=0
NEXT_PHASE_SUMMARIES=0
UAT_ISSUES_PHASE="none"
UAT_ISSUES_SLUG="none"
UAT_ISSUES_MAJOR_OR_HIGHER=false
UAT_ISSUES_PHASES=""
UAT_ISSUES_COUNT=0
UAT_ROUND_COUNT=0
UAT_ISSUES_FILE=""
UAT_ISSUES_RELATIVE_FILE="none"
UAT_BLOCKING_PHASE="none"
UAT_BLOCKING_SLUG="none"
UAT_BLOCKING_STATUS="none"
UAT_BLOCKING_FILE=""
UAT_BLOCKING_RELATIVE_FILE="none"
UAT_LANE_BLOCKS_QA=false
PHASE_DIRS=()

set_next_phase_candidate() {
  declare -g NEXT_PHASE="$1"
  declare -g NEXT_PHASE_SLUG="$2"
  declare -g NEXT_PHASE_STATE="$3"
  declare -g NEXT_PHASE_PLANS="$4"
  declare -g NEXT_PHASE_SUMMARIES="$5"
}

route_earlier_phase_candidate() {
  local phase_dir="$1" phase_num="$2" phase_name="$3"
  local plans summaries contexts state

  plans=$(count_phase_plans "$phase_dir")
  summaries=$(count_complete_summaries "$phase_dir")
  if [ "$plans" -eq 0 ]; then
    state="needs_plan_and_execute"
    if [ "$CFG_REQUIRE_PHASE_DISCUSSION" = true ]; then
      contexts=$(find "$phase_dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
      [ "$contexts" -gt 0 ] || state="needs_discussion"
    fi
    set_next_phase_candidate "$phase_num" "$phase_name" "$state" "$plans" "$summaries"
    return 0
  fi
  if ! phase_execution_is_satisfied "$phase_dir" "$plans" "$summaries"; then
    set_next_phase_candidate "$phase_num" "$phase_name" "needs_execute" "$plans" "$summaries"
    return 0
  fi
  return 1
}

route_earlier_incomplete_before_phase() {
  local boundary_phase="$1"
  local phase_dir phase_name phase_num phase_num_cmp boundary_phase_cmp

  [ -n "$boundary_phase" ] && echo "$boundary_phase" | grep -qE '^[0-9]+$' || return 1
  boundary_phase_cmp=$(printf '%s' "$boundary_phase" | sed 's/^0*//')
  boundary_phase_cmp=${boundary_phase_cmp:-0}
  for phase_dir in "${PHASE_DIRS[@]}"; do
    phase_name=$(basename "$phase_dir")
    phase_num=$(echo "$phase_name" | sed 's/^\([0-9]*\).*/\1/')
    [ -n "$phase_num" ] && echo "$phase_num" | grep -qE '^[0-9]+$' || continue
    phase_num_cmp=$(printf '%s' "$phase_num" | sed 's/^0*//')
    phase_num_cmp=${phase_num_cmp:-0}
    [ "$phase_num_cmp" -lt "$boundary_phase_cmp" ] 2>/dev/null || break
    route_earlier_phase_candidate "$phase_dir" "$phase_num" "$phase_name" && return 0
  done
  return 1
}

if [ -d "$PHASES_DIR" ]; then
  PHASE_DIRS=()
  while IFS= read -r _phase_dir; do
    [ -n "$_phase_dir" ] || continue
    PHASE_DIRS+=("${_phase_dir%/}/")
  done < <(list_child_dirs_sorted "$PHASES_DIR")

  PHASE_COUNT=0
  for _dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    _bname=$(basename "$_dir")
    _num=$(echo "$_bname" | sed 's/^\([0-9]*\).*/\1/')
    if [ -n "$_num" ] && echo "$_num" | grep -qE '^[0-9]+$'; then
      PHASE_COUNT=$((PHASE_COUNT + 1))
    fi
  done

  if [ "$PHASE_COUNT" -eq 0 ]; then
    NEXT_PHASE_STATE="no_phases"
  elif [ ${#PHASE_DIRS[@]} -gt 0 ]; then
    for DIR in "${PHASE_DIRS[@]}"; do
      DIRNAME=$(basename "$DIR")
      NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

      if [ -z "$NUM" ] || ! echo "$NUM" | grep -qE '^[0-9]+$'; then
        continue
      fi

      DIR_PLANS=$(count_phase_plans "$DIR")
      DIR_SUMMARIES=$(count_complete_summaries "$DIR")
      if [ "$DIR_PLANS" -eq 0 ] || ! phase_execution_is_satisfied "$DIR" "$DIR_PLANS" "$DIR_SUMMARIES"; then
        continue
      fi

      UAT_FILE=$(current_uat "$DIR")
      if [ -f "$UAT_FILE" ]; then
        UAT_STATUS_CLASS=$(uat_file_status_class "$UAT_FILE" 2>/dev/null || printf '%s\n' "none")
        case "$UAT_STATUS_CLASS" in
          issues_found|active)
            if [ "$UAT_BLOCKING_PHASE" = "none" ]; then
              UAT_BLOCKING_PHASE="$NUM"
              UAT_BLOCKING_SLUG="$DIRNAME"
              UAT_BLOCKING_STATUS="$UAT_STATUS_CLASS"
              UAT_BLOCKING_FILE="$UAT_FILE"
            fi
            ;;
        esac
        if [ "$UAT_STATUS_CLASS" = "issues_found" ]; then
          if [ "$UAT_ISSUES_PHASE" = "none" ]; then
            UAT_ISSUES_PHASE="$NUM"
            UAT_ISSUES_SLUG="$DIRNAME"
            UAT_ISSUES_FILE="$UAT_FILE"
          fi

          UAT_ISSUES_COUNT=$((UAT_ISSUES_COUNT + 1))
          UAT_ISSUES_PHASES="${UAT_ISSUES_PHASES:+${UAT_ISSUES_PHASES},}$NUM"

          UAT_CRITICAL=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$UAT_FILE" || true)
          UAT_MAJOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$UAT_FILE" || true)
          UAT_MINOR=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$UAT_FILE" || true)
          UAT_TAGGED=$((UAT_CRITICAL + UAT_MAJOR + UAT_MINOR))

          if [ "$UAT_CRITICAL" -gt 0 ] || [ "$UAT_MAJOR" -gt 0 ] || [ "$UAT_TAGGED" -eq 0 ]; then
            UAT_ISSUES_MAJOR_OR_HIGHER=true
          fi
        fi
      fi
    done

    if [ "$UAT_ISSUES_PHASE" != "none" ]; then
      if ! route_earlier_incomplete_before_phase "$UAT_ISSUES_PHASE"; then
        TARGET_DIR="$PHASES_DIR/$UAT_ISSUES_SLUG/"
        NEXT_PHASE="$UAT_ISSUES_PHASE"
        NEXT_PHASE_SLUG="$UAT_ISSUES_SLUG"
        UAT_ROUND_COUNT=$(count_uat_rounds "$TARGET_DIR" "$UAT_ISSUES_PHASE")
        _rem_stage="none"
        _rem_state_file=""
        if [ -f "${TARGET_DIR}remediation/uat/.uat-remediation-stage" ]; then
          _rem_state_file="${TARGET_DIR}remediation/uat/.uat-remediation-stage"
          _rem_stage=$(state_file_kv_value "$_rem_state_file" stage)
          _rem_stage="${_rem_stage:-none}"
        elif [ -f "${TARGET_DIR}remediation/.uat-remediation-stage" ]; then
          _rem_state_file="${TARGET_DIR}remediation/.uat-remediation-stage"
          _rem_stage=$(state_file_kv_value "$_rem_state_file" stage)
          [ -n "$_rem_stage" ] || _rem_stage=$(state_file_scalar_value "$_rem_state_file")
          _rem_stage="${_rem_stage:-none}"
        elif [ -f "${TARGET_DIR}.uat-remediation-stage" ]; then
          _rem_state_file="${TARGET_DIR}.uat-remediation-stage"
          _rem_stage=$(state_file_kv_value "$_rem_state_file" stage)
          [ -n "$_rem_stage" ] || _rem_stage=$(state_file_scalar_value "$_rem_state_file")
          _rem_stage="${_rem_stage:-none}"
        fi
        NEXT_PHASE_PLANS=$(count_phase_plans "$TARGET_DIR")
        NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$TARGET_DIR")
        _total_plans="$NEXT_PHASE_PLANS"
        _total_summaries="$NEXT_PHASE_SUMMARIES"
        _cur_rr="01"
        if [ -n "$_rem_state_file" ] && [ -f "$_rem_state_file" ]; then
          _cr_val=$(state_file_kv_value "$_rem_state_file" round)
          _cur_rr="${_cr_val:-01}"
        fi
        _rd_plans=$(find "$TARGET_DIR" -path "*/remediation/uat/round-${_cur_rr}/R${_cur_rr}-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
        _rd_summary_file=$(find "$TARGET_DIR" -path "*/remediation/uat/round-${_cur_rr}/R${_cur_rr}-SUMMARY.md" 2>/dev/null | head -1)
        _rd_summaries=0
        if [ -n "$_rd_summary_file" ] && is_summary_terminal "$_rd_summary_file"; then
          _rd_summaries=1
        fi
        _total_plans=$(( _total_plans + _rd_plans ))
        _total_summaries=$(( _total_summaries + _rd_summaries ))
        if [ "$_rem_stage" = "execute" ] && [ "$_total_plans" -gt 0 ] && [ "$_total_summaries" -ge "$_total_plans" ]; then
          _rem_stage="done"
        fi
        if [ "$_rem_stage" = "done" ] || [ "$_rem_stage" = "verify" ]; then
          _round_uat=""
          _round_uat_class=""
          if [ -f "${TARGET_DIR}remediation/uat/round-${_cur_rr}/R${_cur_rr}-UAT.md" ]; then
            _round_uat="${TARGET_DIR}remediation/uat/round-${_cur_rr}/R${_cur_rr}-UAT.md"
          elif [ -f "${TARGET_DIR}remediation/round-${_cur_rr}/R${_cur_rr}-UAT.md" ]; then
            _round_uat="${TARGET_DIR}remediation/round-${_cur_rr}/R${_cur_rr}-UAT.md"
          fi
          if [ -n "$_round_uat" ]; then
            _round_uat_class=$(uat_file_status_class "$_round_uat" 2>/dev/null || printf '%s\n' "none")
          fi
          if [ -n "$_rem_state_file" ] && [ -f "$_rem_state_file" ]; then
            _cur_layout=$(state_file_kv_value "$_rem_state_file" layout)
            if [ -z "$_cur_layout" ]; then
              case "$_rem_state_file" in
                */remediation/.uat-remediation-stage|*/.uat-remediation-stage)
                  _cur_layout="legacy" ;;
                *)
                  _cur_layout="round-dir" ;;
              esac
            fi
          else
            _cur_layout="round-dir"
          fi
          case "$_round_uat_class" in
            issues_found)
              _uat_round_route=$(advance_uat_round_after_issues "$TARGET_DIR" "$_rem_state_file" "$_cur_rr" "$_cur_layout")
              NEXT_PHASE_STATE="$_uat_round_route"
              if [ "$_uat_round_route" = "needs_reverification" ]; then
                UAT_LANE_BLOCKS_QA=true
              fi
              ;;
            active)
              NEXT_PHASE_STATE="needs_verification"
              UAT_LANE_BLOCKS_QA=true
              ;;
            *)
              NEXT_PHASE_STATE="needs_reverification"
              ;;
          esac
        else
          NEXT_PHASE_STATE="needs_uat_remediation"
        fi
      fi
    elif [ "$UAT_BLOCKING_PHASE" != "none" ]; then
      if ! route_earlier_incomplete_before_phase "$UAT_BLOCKING_PHASE"; then
        TARGET_DIR="$PHASES_DIR/$UAT_BLOCKING_SLUG/"
        NEXT_PHASE="$UAT_BLOCKING_PHASE"
        NEXT_PHASE_SLUG="$UAT_BLOCKING_SLUG"
        UAT_ROUND_COUNT=$(count_uat_rounds "$TARGET_DIR" "$UAT_BLOCKING_PHASE")

        _block_stage="none"
        _block_state_file=""
        if [ -f "${TARGET_DIR}remediation/uat/.uat-remediation-stage" ]; then
          _block_state_file="${TARGET_DIR}remediation/uat/.uat-remediation-stage"
          _block_stage=$(state_file_kv_value "$_block_state_file" stage)
        elif [ -f "${TARGET_DIR}remediation/.uat-remediation-stage" ]; then
          _block_state_file="${TARGET_DIR}remediation/.uat-remediation-stage"
          _block_stage=$(state_file_kv_value "$_block_state_file" stage)
          [ -n "$_block_stage" ] || _block_stage=$(state_file_scalar_value "$_block_state_file")
        elif [ -f "${TARGET_DIR}.uat-remediation-stage" ]; then
          _block_state_file="${TARGET_DIR}.uat-remediation-stage"
          _block_stage=$(state_file_kv_value "$_block_state_file" stage)
          [ -n "$_block_stage" ] || _block_stage=$(state_file_scalar_value "$_block_state_file")
        fi
        _block_stage="${_block_stage:-none}"

        NEXT_PHASE_PLANS=$(count_phase_plans "$TARGET_DIR")
        NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$TARGET_DIR")
        case "$_block_stage" in
          research|plan|execute)
            NEXT_PHASE_STATE="needs_uat_remediation"
            ;;
          verify|done)
            if [ "$UAT_BLOCKING_STATUS" = "active" ]; then
              NEXT_PHASE_STATE="needs_verification"
            else
              NEXT_PHASE_STATE="needs_reverification"
            fi
            UAT_LANE_BLOCKS_QA=true
            ;;
          *)
            NEXT_PHASE_STATE="needs_verification"
            UAT_LANE_BLOCKS_QA=true
            ;;
        esac
      fi
    else
      ALL_DONE=true
      if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
      for DIR in "${PHASE_DIRS[@]}"; do
        DIRNAME=$(basename "$DIR")
        NUM=$(echo "$DIRNAME" | sed 's/^\([0-9]*\).*/\1/')

        if [ -z "$NUM" ] || ! echo "$NUM" | grep -qE '^[0-9]+$'; then
          continue
        fi

        P_COUNT=$(count_phase_plans "$DIR")
        S_COUNT=$(count_complete_summaries "$DIR")

        if [ "$P_COUNT" -eq 0 ]; then
          if [ "$CFG_REQUIRE_PHASE_DISCUSSION" = true ]; then
            C_COUNT=$(find "$DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
            if [ "$C_COUNT" -eq 0 ]; then
              if [ "$NEXT_PHASE" = "none" ]; then
                NEXT_PHASE="$NUM"
                NEXT_PHASE_SLUG="$DIRNAME"
                NEXT_PHASE_STATE="needs_discussion"
                NEXT_PHASE_PLANS="$P_COUNT"
                NEXT_PHASE_SUMMARIES="$S_COUNT"
              fi
              ALL_DONE=false
              break
            fi
          fi
          if [ "$NEXT_PHASE" = "none" ]; then
            NEXT_PHASE="$NUM"
            NEXT_PHASE_SLUG="$DIRNAME"
            NEXT_PHASE_STATE="needs_plan_and_execute"
            NEXT_PHASE_PLANS="$P_COUNT"
            NEXT_PHASE_SUMMARIES="$S_COUNT"
          fi
          ALL_DONE=false
          break
        elif ! phase_execution_is_satisfied "$DIR" "$P_COUNT" "$S_COUNT"; then
          if [ "$NEXT_PHASE" = "none" ]; then
            NEXT_PHASE="$NUM"
            NEXT_PHASE_SLUG="$DIRNAME"
            NEXT_PHASE_STATE="needs_execute"
            NEXT_PHASE_PLANS="$P_COUNT"
            NEXT_PHASE_SUMMARIES="$S_COUNT"
          fi
          ALL_DONE=false
          break
        fi
      done

      fi

      if [ "$ALL_DONE" = true ] && [ "$NEXT_PHASE" = "none" ]; then
        NEXT_PHASE_STATE="all_done"
      fi
    fi
  fi
fi

: "$UAT_ISSUES_RELATIVE_FILE" "$UAT_BLOCKING_RELATIVE_FILE" "$UAT_BLOCKING_FILE" \
  "$UAT_ISSUES_FILE" "$UAT_ISSUES_MAJOR_OR_HIGHER" "$UAT_ROUND_COUNT" \
  "$UAT_LANE_BLOCKS_QA" "$NEXT_PHASE_SLUG" "$NEXT_PHASE_STATE"
