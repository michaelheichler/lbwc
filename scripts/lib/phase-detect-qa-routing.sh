#!/bin/bash
set -u

HAS_UNVERIFIED_PHASES=false
FIRST_UNVERIFIED_PHASE=""
FIRST_UNVERIFIED_SLUG=""
FIRST_QA_ATTENTION_PHASE=""
FIRST_QA_ATTENTION_SLUG=""
QA_ATTENTION_STATUS="none"
QA_ATTENTION_REASON="none"
QA_STATUS="none"
QA_REASON="none"
QA_AFTER_UAT_DORMANT=false
QA_ROUND="00"
QA_REMEDIATING_PHASE=""
QA_REMEDIATING_SLUG=""
QA_REMEDIATING_ROUND="00"

if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _qr_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_qr_dir" ] || continue
    _qr_dirname=$(basename "$_qr_dir")
    echo "$_qr_dirname" | grep -qE '^[0-9]+-' || continue
    _qr_plans=$(count_phase_plans "$_qr_dir")
    [ "$_qr_plans" -gt 0 ] || continue
    _qr_sums=$(count_complete_summaries "$_qr_dir")
    if ! phase_execution_is_satisfied "$_qr_dir" "$_qr_plans" "$_qr_sums"; then
      continue
    fi
    if phase_has_uat_cutover "$_qr_dir"; then
      continue
    fi

    _qr_rem_file="${_qr_dir}remediation/qa/.qa-remediation-stage"
    [ -f "$_qr_rem_file" ] || continue

    _qr_stage=$(state_file_kv_value "$_qr_rem_file" stage)
    _qr_stage=$(normalize_qa_remediation_stage "${_qr_stage:-none}")
    case "$_qr_stage" in
      none|done) continue ;;
    esac

    _qr_round=$(state_file_kv_value "$_qr_rem_file" round)
    _qr_round="${_qr_round:-01}"
    _qr_dirname=$(basename "$_qr_dir")
    QA_REMEDIATING_PHASE=$(echo "$_qr_dirname" | sed 's/^\([0-9]*\).*/\1/')
    QA_REMEDIATING_SLUG="$_qr_dirname"
    QA_REMEDIATING_ROUND="$_qr_round"
    break
  done
fi

if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _uv_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_uv_dir" ] || continue
    _uv_dirname=$(basename "$_uv_dir")
    echo "$_uv_dirname" | grep -qE '^[0-9]+-' || continue
    _uv_plans=$(count_phase_plans "$_uv_dir")
    [ "$_uv_plans" -gt 0 ] || continue
    _uv_sums=$(count_complete_summaries "$_uv_dir")
    if ! phase_execution_is_satisfied "$_uv_dir" "$_uv_plans" "$_uv_sums"; then
      continue
    fi
    _uv_uat_cutover=false
    if phase_has_uat_cutover "$_uv_dir"; then
      _uv_uat_cutover=true
    fi

    _qa_rem_stage="none"
    _qa_rem_round="00"
    _qa_rem_file="${_uv_dir}remediation/qa/.qa-remediation-stage"
    if [ -f "$_qa_rem_file" ]; then
      _qa_rem_stage=$(state_file_kv_value "$_qa_rem_file" stage)
      _qa_rem_stage=$(normalize_qa_remediation_stage "${_qa_rem_stage:-none}")
      _qa_rem_round=$(state_file_kv_value "$_qa_rem_file" round)
      _qa_rem_round="${_qa_rem_round:-01}"
    fi

    if [ "$_qa_rem_stage" != "none" ] && [ "$_qa_rem_stage" != "done" ]; then
      if [ "$_uv_uat_cutover" = true ]; then
        QA_AFTER_UAT_DORMANT=true
      else
        if [ -z "$FIRST_UNVERIFIED_PHASE" ]; then
          _uv_dirname=$(basename "$_uv_dir")
          FIRST_UNVERIFIED_PHASE=$(echo "$_uv_dirname" | sed 's/^\([0-9]*\).*/\1/')
          FIRST_UNVERIFIED_SLUG="$_uv_dirname"
          QA_STATUS="remediating"
          QA_REASON="none"
          QA_ROUND="$_qa_rem_round"
        fi
        break
      fi
    fi

    _uv_verif=$(bash "$_SCRIPT_DIR_PD/resolve-verification-path.sh" phase "$_uv_dir" 2>/dev/null || true)
    if [ -n "$_uv_verif" ] && [ ! -f "$_uv_verif" ]; then
      _uv_verif=""
    fi
    _uv_uat=$(current_uat "$_uv_dir")
    _uv_is_unverified=false
    if [ -z "$_uv_uat" ]; then
      _uv_is_unverified=true
    else
      _uv_uat_status=$(uat_file_status_class "$_uv_uat" 2>/dev/null || printf '%s\n' "none")
      case "$_uv_uat_status" in
        complete|issues_found) ;;
        *) _uv_is_unverified=true ;;
      esac
    fi
    if [ "$_uv_is_unverified" = true ]; then
      HAS_UNVERIFIED_PHASES=true
      if [ -z "$FIRST_UNVERIFIED_PHASE" ]; then
        _uv_dirname=$(basename "$_uv_dir")
        FIRST_UNVERIFIED_PHASE=$(echo "$_uv_dirname" | sed 's/^\([0-9]*\).*/\1/')
        FIRST_UNVERIFIED_SLUG="$_uv_dirname"

        if [ "$_uv_uat_cutover" = true ]; then
          QA_STATUS="none"
          QA_REASON="uat_cutover"
          QA_AFTER_UAT_DORMANT=true
        else
          if [ "$_qa_rem_stage" = "done" ]; then
            _uv_verif=$(bash "$_SCRIPT_DIR_PD/resolve-verification-path.sh" current "$_uv_dir" 2>/dev/null || true)
            if [ -n "$_uv_verif" ] && [ ! -f "$_uv_verif" ]; then
              _uv_verif=""
            fi
            _uv_assessment=$(phase_verification_assessment "$_uv_dir" "$_uv_verif" "remediated")
          elif [ -n "$_uv_verif" ] && [ -f "$_uv_verif" ]; then
            _uv_assessment=$(phase_verification_assessment "$_uv_dir" "$_uv_verif" "passed")
          else
            _uv_assessment=$(phase_verification_assessment "$_uv_dir" "" "passed")
          fi
          IFS=$'\t' read -r QA_STATUS QA_REASON <<< "$_uv_assessment"
          QA_STATUS="${QA_STATUS:-pending}"
          QA_REASON="${QA_REASON:-none}"
        fi
      fi
      break
    fi
  done
fi

if [ ${#PHASE_DIRS[@]} -gt 0 ]; then
  for _qa_dir in ${PHASE_DIRS[@]+"${PHASE_DIRS[@]}"}; do
    [ -d "$_qa_dir" ] || continue
    _qa_dirname=$(basename "$_qa_dir")
    echo "$_qa_dirname" | grep -qE '^[0-9]+-' || continue
    _qa_plans=$(count_phase_plans "$_qa_dir")
    [ "$_qa_plans" -gt 0 ] || continue
    _qa_sums=$(count_complete_summaries "$_qa_dir")
    if ! phase_execution_is_satisfied "$_qa_dir" "$_qa_plans" "$_qa_sums"; then
      continue
    fi
    if phase_has_uat_cutover "$_qa_dir"; then
      continue
    fi

    _qa_stage="none"
    _qa_round_scan="00"
    _qa_rem_file_scan="${_qa_dir}remediation/qa/.qa-remediation-stage"
    if [ -f "$_qa_rem_file_scan" ]; then
      _qa_stage=$(state_file_kv_value "$_qa_rem_file_scan" stage)
      _qa_stage=$(normalize_qa_remediation_stage "${_qa_stage:-none}")
      _qa_round_scan=$(state_file_kv_value "$_qa_rem_file_scan" round)
      _qa_round_scan="${_qa_round_scan:-01}"
    fi

    _qa_attention="none"
    _qa_attention_reason="none"
    case "$_qa_stage" in
      plan|execute) continue ;;
      verify) _qa_attention="verify" ;;
    esac

    _qa_verif_scan=""
    if [ "$_qa_stage" = "done" ]; then
      _qa_verif_scan=$(bash "$_SCRIPT_DIR_PD/resolve-verification-path.sh" current "$_qa_dir" 2>/dev/null || true)
    elif [ "$_qa_attention" = "none" ]; then
      _qa_verif_scan=$(bash "$_SCRIPT_DIR_PD/resolve-verification-path.sh" phase "$_qa_dir" 2>/dev/null || true)
    fi
    if [ -n "$_qa_verif_scan" ] && [ ! -f "$_qa_verif_scan" ]; then
      _qa_verif_scan=""
    fi
    if [ "$_qa_attention" = "none" ]; then
      _qa_assessment=$(phase_verification_assessment "$_qa_dir" "$_qa_verif_scan" "none")
      IFS=$'\t' read -r _qa_attention _qa_attention_reason <<< "$_qa_assessment"
      _qa_attention="${_qa_attention:-none}"
      _qa_attention_reason="${_qa_attention_reason:-none}"
    fi

    if [ "$_qa_attention" != "none" ]; then
      _qa_dirname=$(basename "$_qa_dir")
      FIRST_QA_ATTENTION_PHASE=$(echo "$_qa_dirname" | sed 's/^\([0-9]*\).*/\1/')
      FIRST_QA_ATTENTION_SLUG="$_qa_dirname"
      QA_ATTENTION_STATUS="$_qa_attention"
      QA_ATTENTION_REASON="${_qa_attention_reason:-none}"
      break
    fi
  done
fi

if [ -n "$QA_REMEDIATING_PHASE" ] && [ "$NEXT_PHASE_STATE" != "needs_uat_remediation" ] && [ "$UAT_LANE_BLOCKS_QA" != true ]; then
  case "$NEXT_PHASE_STATE" in
    needs_discussion|needs_plan_and_execute|needs_execute|needs_verification|needs_reverification|all_done|no_phases)
      NEXT_PHASE="$QA_REMEDIATING_PHASE"
      NEXT_PHASE_SLUG="$QA_REMEDIATING_SLUG"
      NEXT_PHASE_STATE="needs_qa_remediation"
      QA_STATUS="remediating"
      QA_REASON="none"
      QA_ROUND="$QA_REMEDIATING_ROUND"
      _QR_DIR="$PHASES_DIR/$QA_REMEDIATING_SLUG"
      if [ -d "$_QR_DIR" ]; then
        NEXT_PHASE_PLANS=$(count_phase_plans "$_QR_DIR")
        NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$_QR_DIR")
      fi
      ;;
  esac
fi

if [ "$CFG_AUTO_UAT_EARLY" = "true" ] && [ "$HAS_UNVERIFIED_PHASES" = "true" ] && [ "$QA_STATUS" != "remediating" ]; then
  case "$NEXT_PHASE_STATE" in
    needs_discussion|needs_plan_and_execute|needs_execute|all_done)
      NEXT_PHASE="$FIRST_UNVERIFIED_PHASE"
      NEXT_PHASE_SLUG="$FIRST_UNVERIFIED_SLUG"
      NEXT_PHASE_STATE="needs_verification"
      _UV_DIR="$PHASES_DIR/$FIRST_UNVERIFIED_SLUG"
      if [ -d "$_UV_DIR" ]; then
        NEXT_PHASE_PLANS=$(count_phase_plans "$_UV_DIR")
        NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$_UV_DIR")
      fi
      ;;
    *) ;;
  esac
fi

if [ "$NEXT_PHASE_STATE" = "all_done" ] && [ -n "$FIRST_QA_ATTENTION_PHASE" ]; then
  _QA_ATT_DIR="$PHASES_DIR/$FIRST_QA_ATTENTION_SLUG/"
  if phase_has_uat_cutover "$_QA_ATT_DIR"; then
    QA_AFTER_UAT_DORMANT=true
  else
    case "$QA_ATTENTION_STATUS" in
      failed|verify)
        NEXT_PHASE="$FIRST_QA_ATTENTION_PHASE"
        NEXT_PHASE_SLUG="$FIRST_QA_ATTENTION_SLUG"
        if [ -d "$_QA_ATT_DIR" ]; then
          NEXT_PHASE_PLANS=$(count_phase_plans "$_QA_ATT_DIR")
          NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$_QA_ATT_DIR")
        fi
        NEXT_PHASE_STATE="needs_qa_remediation"
        if [ "$QA_ATTENTION_STATUS" = "failed" ]; then
          QA_STATUS="failed"
        else
          QA_STATUS="remediating"
        fi
        QA_REASON="none"
        ;;
      pending)
        _QA_ATT_UAT="$(current_uat "$_QA_ATT_DIR")"
        _QA_ATT_UAT_STATUS=""
        if [ -f "$_QA_ATT_UAT" ]; then
          _QA_ATT_UAT_STATUS=$(uat_file_status_class "$_QA_ATT_UAT" 2>/dev/null || printf '%s\n' "none")
        fi

        case "$_QA_ATT_UAT_STATUS" in
          complete)
            NEXT_PHASE="$FIRST_QA_ATTENTION_PHASE"
            NEXT_PHASE_SLUG="$FIRST_QA_ATTENTION_SLUG"
            if [ -d "$_QA_ATT_DIR" ]; then
              NEXT_PHASE_PLANS=$(count_phase_plans "$_QA_ATT_DIR")
              NEXT_PHASE_SUMMARIES=$(count_complete_summaries "$_QA_ATT_DIR")
            fi
            NEXT_PHASE_STATE="needs_verification"
            QA_STATUS="pending"
            QA_REASON="${QA_ATTENTION_REASON:-none}"
            ;;
        esac
        ;;
    esac
  fi
fi

if [ "$NEXT_PHASE_STATE" = "needs_qa_remediation" ]; then
  _pd_qa_guard_dir="$PHASES_DIR/$NEXT_PHASE_SLUG/"
  if phase_has_uat_cutover "$_pd_qa_guard_dir"; then
    _pd_guard_uat=$(current_uat "$_pd_qa_guard_dir")
    _pd_guard_uat_status=""
    if [ -f "$_pd_guard_uat" ]; then
      _pd_guard_uat_status=$(uat_file_status_class "$_pd_guard_uat" 2>/dev/null || printf '%s\n' "none")
    fi
    QA_AFTER_UAT_DORMANT=true
    QA_STATUS="none"
    QA_REASON="uat_cutover"
    QA_ROUND="00"
    case "$_pd_guard_uat_status" in
      issues_found)
        NEXT_PHASE_STATE="needs_uat_remediation"
        ;;
      complete)
        NEXT_PHASE="none"
        NEXT_PHASE_SLUG="none"
        NEXT_PHASE_PLANS=0
        NEXT_PHASE_SUMMARIES=0
        NEXT_PHASE_STATE="all_done"
        ;;
      *)
        NEXT_PHASE_STATE="needs_verification"
        ;;
    esac
  fi
fi

if [ "$UAT_ISSUES_PHASE" != "none" ] && [ -n "$UAT_ISSUES_FILE" ] && [ -f "$UAT_ISSUES_FILE" ]; then
  _pd_active_phase_dir="${PHASES_DIR}/${UAT_ISSUES_SLUG}"
  if [ -d "$_pd_active_phase_dir" ]; then
    UAT_ISSUES_RELATIVE_FILE=$(phase_relative_path "$_pd_active_phase_dir" "$UAT_ISSUES_FILE")
  else
    UAT_ISSUES_RELATIVE_FILE=$(basename "$UAT_ISSUES_FILE")
  fi
fi

if [ "$UAT_BLOCKING_PHASE" != "none" ] && [ -n "$UAT_BLOCKING_FILE" ] && [ -f "$UAT_BLOCKING_FILE" ]; then
  _pd_blocking_phase_dir="${PHASES_DIR}/${UAT_BLOCKING_SLUG}"
  if [ -d "$_pd_blocking_phase_dir" ]; then
    UAT_BLOCKING_RELATIVE_FILE=$(phase_relative_path "$_pd_blocking_phase_dir" "$UAT_BLOCKING_FILE")
  else
    UAT_BLOCKING_RELATIVE_FILE=$(basename "$UAT_BLOCKING_FILE")
  fi
fi

: "$QA_AFTER_UAT_DORMANT" "$QA_ROUND" "$NEXT_PHASE" "$NEXT_PHASE_PLANS" \
  "$NEXT_PHASE_SUMMARIES" "$UAT_ISSUES_RELATIVE_FILE" "$UAT_BLOCKING_RELATIVE_FILE"
