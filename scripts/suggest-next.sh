#!/usr/bin/env bash

set -eo pipefail

CMD="${1:-}"
RESULT="${2:-}"
TARGET_PHASE_ARG="${3:-}"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE_VERIF_SCRIPT="$SCRIPT_DIR/resolve-verification-path.sh"

. "$SCRIPT_DIR/uat-utils.sh"
read_status_field() { extract_status_value "$@"; }

if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  . "$SCRIPT_DIR/summary-utils.sh"
else
  count_complete_summaries() { echo "0"; }
fi
if [ -f "$SCRIPT_DIR/phase-state-utils.sh" ]; then
  . "$SCRIPT_DIR/phase-state-utils.sh"
else
  count_phase_plans() {
    local dir="$1"
    find "$dir" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | wc -l | tr -d ' '
  }
fi

list_child_dirs_sorted() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-)
}

has_project=false
phase_count=0
next_unplanned=""
next_unbuilt=""
all_done=false
last_qa_result=""
map_exists=false

effort="balanced"
active_phase_dir=""
active_phase_num=""
active_phase_name=""
active_phase_plans=0
deviation_count=0
failing_plan_ids=""
map_staleness=-1
cfg_autonomy="standard"
has_uat=false
uat_major_or_higher=false
verify_target_phase=""
verify_target_phase_dir=""
verify_target_uat=""
milestone_uat_issues=false
milestone_uat_phase="none"
milestone_uat_slug="none"
milestone_uat_count=0
current_uat_issues_phase=""
current_uat_issues_slug=""
current_uat_issues_label=""
current_uat_major_or_higher=false
current_uat_round_count=0
current_uat_blocking_phase=""
cfg_require_phase_discussion=false
next_undiscussed=""
next_preseeded=""
cfg_auto_uat=false
has_unverified_phases=false
first_unverified_phase=""
first_unverified_slug=""
next_phase_state=""
pd_next_phase=""

read_deviations_field() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && tolower($0) ~ /^[[:space:]]*deviations[[:space:]]*:/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$file" 2>/dev/null || true
}

if [ -d "$PLANNING_DIR" ]; then

  _pd_out=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null || true)
  _pd_complete=$(printf '%s\n' "$_pd_out" | awk -F= '/^phase_detect_complete=/{print $2; exit}')
  if [ -n "$_pd_out" ] && [ "$_pd_out" != "phase_detect_error=true" ] && [ "${_pd_complete:-}" = "true" ]; then
    _pd_milestone_uat=$(echo "$_pd_out" | grep -m1 '^milestone_uat_issues=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_phase=$(echo "$_pd_out" | grep -m1 '^milestone_uat_phase=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_slug=$(echo "$_pd_out" | grep -m1 '^milestone_uat_slug=' | sed 's/^[^=]*=//' || true)
    _pd_milestone_count=$(echo "$_pd_out" | grep -m1 '^milestone_uat_count=' | sed 's/^[^=]*=//' || true)

    [ -n "${_pd_milestone_uat:-}" ] && milestone_uat_issues="$_pd_milestone_uat"
    [ -n "${_pd_milestone_phase:-}" ] && milestone_uat_phase="$_pd_milestone_phase"
    [ -n "${_pd_milestone_slug:-}" ] && milestone_uat_slug="$_pd_milestone_slug"
    [ -n "${_pd_milestone_count:-}" ] && milestone_uat_count="$_pd_milestone_count"

    _pd_require_discuss=$(echo "$_pd_out" | grep -m1 '^config_require_phase_discussion=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_require_discuss:-}" ] && cfg_require_phase_discussion="$_pd_require_discuss"

    _pd_has_unverified=$(echo "$_pd_out" | grep -m1 '^has_unverified_phases=' | sed 's/^[^=]*=//' || true)
    [ "${_pd_has_unverified:-}" = "true" ] && has_unverified_phases=true

    _pd_first_unverified_phase=$(echo "$_pd_out" | grep -m1 '^first_unverified_phase=' | sed 's/^[^=]*=//' || true)
    _pd_first_unverified_slug=$(echo "$_pd_out" | grep -m1 '^first_unverified_slug=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_first_unverified_phase:-}" ] && first_unverified_phase="$_pd_first_unverified_phase"
    [ -n "${_pd_first_unverified_slug:-}" ] && first_unverified_slug="$_pd_first_unverified_slug"

    _pd_next_phase_state=$(echo "$_pd_out" | grep -m1 '^next_phase_state=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_next_phase_state:-}" ] && next_phase_state="$_pd_next_phase_state"

    _pd_next_phase=$(echo "$_pd_out" | grep -m1 '^next_phase=' | sed 's/^[^=]*=//' || true)
    [ -n "${_pd_next_phase:-}" ] && pd_next_phase="$_pd_next_phase"

    _pd_uat_phase=$(echo "$_pd_out" | grep -m1 '^uat_issues_phase=' | sed 's/^[^=]*=//' || true)
    _pd_uat_slug=$(echo "$_pd_out" | grep -m1 '^uat_issues_slug=' | sed 's/^[^=]*=//' || true)
    _pd_uat_major=$(echo "$_pd_out" | grep -m1 '^uat_issues_major_or_higher=' | sed 's/^[^=]*=//' || true)
    _pd_uat_round_count=$(echo "$_pd_out" | grep -m1 '^uat_round_count=' | sed 's/^[^=]*=//' || true)
    _pd_uat_blocking_phase=$(echo "$_pd_out" | grep -m1 '^uat_blocking_phase=' | sed 's/^[^=]*=//' || true)
    if [ -n "${_pd_uat_phase:-}" ] && [ "$_pd_uat_phase" != "none" ]; then
      current_uat_issues_phase="$_pd_uat_phase"
      current_uat_issues_slug="${_pd_uat_slug:-}"
      [ "${_pd_uat_major:-}" = "true" ] && current_uat_major_or_higher=true
      [ -n "${_pd_uat_round_count:-}" ] && current_uat_round_count="$_pd_uat_round_count"
    fi
    if [ -n "${_pd_uat_blocking_phase:-}" ] && [ "$_pd_uat_blocking_phase" != "none" ]; then
      current_uat_blocking_phase="$_pd_uat_blocking_phase"
    fi

    if [ -n "$current_uat_issues_phase" ] && [ -n "$current_uat_issues_slug" ]; then
      current_uat_issues_label="Phase $current_uat_issues_phase ($current_uat_issues_slug)"
    elif [ -n "$current_uat_issues_phase" ]; then
      current_uat_issues_label="Phase $current_uat_issues_phase"
    else
      current_uat_issues_label=""
    fi
    if [ -n "$current_uat_issues_label" ] && [ "$current_uat_round_count" -gt 0 ] 2>/dev/null; then
      _display_round=$((current_uat_round_count + 1))
      current_uat_issues_label="$current_uat_issues_label, Round $_display_round"
    fi
  fi

  PHASES_DIR="$PLANNING_DIR/phases"

  if [ -f "$PLANNING_DIR/PROJECT.md" ] && ! grep -q '{project-name}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    has_project=true
  fi

  if [ -f "$PLANNING_DIR/config.json" ] && command -v jq >/dev/null 2>&1; then
    if ! jq -e '.model_profile' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' "$PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$PLANNING_DIR/config.json"
    fi
    e=$(jq -r '.effort // "balanced"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ -n "$e" ] && [ "$e" != "null" ] && effort="$e"
    a=$(jq -r '.autonomy // "standard"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ -n "$a" ] && [ "$a" != "null" ] && cfg_autonomy="$a"
    au=$(jq -r '.auto_uat // "false"' "$PLANNING_DIR/config.json" 2>/dev/null)
    [ "$au" = "true" ] && cfg_auto_uat=true
  fi

  if [ -d "$PHASES_DIR" ]; then
    SN_PHASE_DIRS=()
    while IFS= read -r _sn_dir; do
      [ -n "$_sn_dir" ] || continue
      SN_PHASE_DIRS+=("${_sn_dir%/}/")
    done < <(list_child_dirs_sorted "$PHASES_DIR")

    last_phase_dir=""
    last_phase_num=""
    last_phase_name=""
    last_phase_plans=0

    if [ ${#SN_PHASE_DIRS[@]} -gt 0 ]; then
    for dir in "${SN_PHASE_DIRS[@]}"; do
      [ -d "$dir" ] || continue
      phase_num=$(basename "$dir" | sed 's/[^0-9].*//')
      if [ -z "$phase_num" ] || ! echo "$phase_num" | grep -qE '^[0-9]+$'; then
        continue
      fi
      phase_count=$((phase_count + 1))
      phase_slug=$(basename "$dir" | sed 's/^[0-9]*-//')

      plans=$(count_phase_plans "$dir")
      summaries=$(count_complete_summaries "$dir")

      if [ "$plans" -eq 0 ] && [ -z "$next_unplanned" ]; then
        if [ "$cfg_require_phase_discussion" = "true" ] && [ -z "$next_undiscussed" ]; then
          context_files=$(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | wc -l | tr -d ' ')
          if [ "$context_files" -eq 0 ]; then
            next_undiscussed="$phase_num"
          elif [ -z "$next_preseeded" ]; then
            while IFS= read -r ctx_file; do
              [ -n "$ctx_file" ] || continue
              if awk '
              BEGIN { in_fm=0; found=0 }
              NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
              in_fm && /^---[[:space:]]*$/ { exit }
              in_fm && /^pre_seeded[[:space:]]*:[[:space:]]*"?true"?[[:space:]]*$/ { found=1; exit }
              END { exit !found }
            ' "$ctx_file" 2>/dev/null; then
                next_preseeded="$phase_num"
                break
              fi
            done < <(find "$dir" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | sort)
          fi
        fi
        next_unplanned="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans=0
      elif [ "$plans" -gt 0 ] && [ "$summaries" -lt "$plans" ] && [ -z "$next_unbuilt" ]; then
        next_unbuilt="$phase_num"
        active_phase_dir="$dir"
        active_phase_num="$phase_num"
        active_phase_name="$phase_slug"
        active_phase_plans="$plans"
      fi

      last_phase_dir="$dir"
      last_phase_num="$phase_num"
      last_phase_name="$phase_slug"
      last_phase_plans="$plans"
    done
    fi  # end SN_PHASE_DIRS length check

    if [ -z "$active_phase_dir" ] && [ -n "$last_phase_dir" ]; then
      active_phase_dir="$last_phase_dir"
      active_phase_num="$last_phase_num"
      active_phase_name="$last_phase_name"
      active_phase_plans="$last_phase_plans"
    fi

    if [ "$phase_count" -gt 0 ] && [ -z "$next_unplanned" ] && [ -z "$next_unbuilt" ] && [ -z "$current_uat_issues_phase" ] && [ -z "$current_uat_blocking_phase" ]; then
      all_done=true
    fi

    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      _sn_verif=$(bash "$RESOLVE_VERIF_SCRIPT" authoritative "${dir%/}" 2>/dev/null || true)
      [ -n "$_sn_verif" ] || continue
      [ -f "$_sn_verif" ] || continue
      r=$(grep -m1 '^result:' "$_sn_verif" 2>/dev/null | sed 's/result:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' || true)
      [ -n "$r" ] && last_qa_result="$r"
    done

    if [ -n "$active_phase_dir" ] && [ -d "$active_phase_dir" ]; then
      for sf in "$active_phase_dir"/*-SUMMARY.md "$active_phase_dir"/SUMMARY.md; do
        [ -f "$sf" ] || continue
        d=$(read_deviations_field "$sf")
        case "$d" in
          0|"[]"|"") ;;  # zero deviations
          [0-9]*) deviation_count=$((deviation_count + d)) ;;
          *) deviation_count=$((deviation_count + 1)) ;;  # non-empty, non-numeric = at least 1
        esac
        s=$(read_status_field "$sf")
        if [ "$s" = "failed" ] || [ "$s" = "partial" ]; then
          plan_id=$(basename "$sf" | sed 's/-SUMMARY.md//')
          failing_plan_ids="${failing_plan_ids:+$failing_plan_ids }$plan_id"
        fi
      done

      for uf in "$active_phase_dir"/*-UAT.md; do
        [ -f "$uf" ] || continue
        case "$uf" in
          *SOURCE-UAT.md) continue ;;
        esac
        us=$(read_status_field "$uf")
        if [ "$us" = "complete" ] || [ "$us" = "passed" ]; then
          has_uat=true
        fi
      done
      if [ "$has_uat" != true ]; then
        for uf in "$active_phase_dir"/remediation/uat/round-*/R*-UAT.md; do
          [ -f "$uf" ] || continue
          us=$(read_status_field "$uf")
          if [ "$us" = "complete" ] || [ "$us" = "passed" ]; then
            has_uat=true
          fi
        done
      fi
    fi
  fi

  if [ -d "$PLANNING_DIR/codebase" ]; then
    map_exists=true
    META="$PLANNING_DIR/codebase/META.md"
    if [ -f "$META" ] && git rev-parse --git-dir >/dev/null 2>&1; then
      git_hash=$(grep '^git_hash:' "$META" 2>/dev/null | awk '{print $2}' || true)
      file_count=$(grep '^file_count:' "$META" 2>/dev/null | awk '{print $2}' || true)
      if [ -n "$git_hash" ] && [ -n "$file_count" ] && [ "$file_count" -gt 0 ] 2>/dev/null; then
        if git cat-file -e "$git_hash" 2>/dev/null; then
          changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')
          map_staleness=$((changed * 100 / file_count))
        else
          map_staleness=100
        fi
      fi
    fi
  fi
fi

effective_result="${RESULT:-$last_qa_result}"

if [ "$CMD" = "verify" ] && [ "$effective_result" = "issues_found" ] && [ -d "${PHASES_DIR:-}" ]; then
  verify_target_phase="$TARGET_PHASE_ARG"

  if [ -n "$verify_target_phase" ]; then
    verify_target_phase=$(echo "$verify_target_phase" | sed 's/^0*//')
    [ -z "$verify_target_phase" ] && verify_target_phase="0"
  fi

  if [ -n "$verify_target_phase" ]; then
    for dir in "$PHASES_DIR"/*/; do
      [ -d "$dir" ] || continue
      pn=$(basename "$dir" | sed 's/[^0-9].*//' | sed 's/^0*//')
      [ -z "$pn" ] && pn="0"
      if [ "$pn" = "$verify_target_phase" ]; then
        verify_target_phase_dir="$dir"
        break
      fi
    done
  else
    SN_VERIFY_DIRS=()
    while IFS= read -r _sv_dir; do
      [ -n "$_sv_dir" ] || continue
      SN_VERIFY_DIRS+=("${_sv_dir%/}/")
    done < <(list_child_dirs_sorted "$PHASES_DIR")

    for dir in ${SN_VERIFY_DIRS[@]+"${SN_VERIFY_DIRS[@]}"}; do
      [ -d "$dir" ] || continue
      _plans=$(count_phase_plans "$dir")
      _summaries=$(count_complete_summaries "$dir")
      if [ "$_plans" -eq 0 ] || [ "$_summaries" -lt "$_plans" ]; then
        continue
      fi
      _uat=$(current_uat "$dir")
      if [ -f "$_uat" ]; then
        _us=$(read_status_field "$_uat")
        if [ "$_us" = "issues_found" ]; then
          verify_target_phase_dir="$dir"
          verify_target_phase=$(basename "$dir" | sed 's/[^0-9].*//' | sed 's/^0*//')
          [ -z "$verify_target_phase" ] && verify_target_phase="0"
          break
        fi
      fi
    done
  fi

  if [ -n "$verify_target_phase_dir" ]; then
    verify_target_uat=$(current_uat "$verify_target_phase_dir")
  fi

  if [ -f "$verify_target_uat" ]; then
    uat_critical=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*critical' "$verify_target_uat" || true)
    uat_major=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*major' "$verify_target_uat" || true)
    uat_minor=$(grep -Eci 'severity:\**[[:space:]]*\**[[:space:]]*minor' "$verify_target_uat" || true)
    tagged_severities=$((uat_critical + uat_major + uat_minor))

    if [ "$uat_critical" -gt 0 ] || [ "$uat_major" -gt 0 ] || [ "$tagged_severities" -eq 0 ]; then
      uat_major_or_higher=true
    fi
  else
    if [ -n "$verify_target_phase_dir" ]; then
      uat_major_or_higher=true
    fi
  fi
fi

fmt_phase_name() {
  echo "$1" | tr '-' ' '
}

echo "➜ Next Up"

suggest() {
  echo "  $1"
}

suggest_milestone_recovery() {
  if [ "$milestone_uat_issues" = true ]; then
    if [ "$milestone_uat_slug" != "none" ] && [ "${milestone_uat_count:-0}" -gt 1 ] 2>/dev/null; then
      suggest "/lbwc:vibe -- Milestone UAT recovery pending (${milestone_uat_slug}, ${milestone_uat_count} phase(s))"
    elif [ "$milestone_uat_slug" != "none" ] && [ "$milestone_uat_phase" != "none" ]; then
      suggest "/lbwc:vibe -- Milestone UAT recovery pending (${milestone_uat_slug}, Phase ${milestone_uat_phase})"
    else
      suggest "/lbwc:vibe -- Milestone UAT recovery pending"
    fi
    return 0
  fi
  return 1
}

case "$CMD" in
  init)
    suggest "/lbwc:vibe -- Define your project and start building"
    ;;

  vibe|implement|execute)
    case "$effective_result" in
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/lbwc:fix -- Fix plan $first_fail (failed verification)"
        else
          suggest "/lbwc:fix -- Fix the failing checks"
        fi
        suggest "/lbwc:vibe -- Re-run verification after fixing"
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/lbwc:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/lbwc:fix -- Address partial failures"
        fi
        if [ "$all_done" != true ]; then
          suggest "/lbwc:vibe -- Continue to next phase"
        fi
        ;;
      *)
        if [ -z "$current_uat_issues_phase" ] && \
           { { [ "$has_uat" = false ] && [ "$active_phase_plans" -gt 0 ] && { [ "$cfg_auto_uat" = true ] || [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; } \
             || { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; }; then
          if [ -n "$first_unverified_phase" ]; then
            _uv_label="$first_unverified_phase"
            [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
            suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
          else
            suggest "/lbwc:vibe -- Verify completed work before continuing"
          fi
        fi
        if [ "$all_done" = true ] || [ "$next_phase_state" = "needs_reverification" ] || { [ "$next_phase_state" = "needs_verification" ] && [ -n "$current_uat_blocking_phase" ]; }; then
          if [ "$next_phase_state" = "needs_reverification" ]; then
            suggest "/lbwc:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
          elif [ "$next_phase_state" = "needs_verification" ] && [ -n "$current_uat_blocking_phase" ]; then
            suggest "/lbwc:vibe -- Resume Verify for Phase ${pd_next_phase:-}"
          elif ! suggest_milestone_recovery; then
            if [ "$deviation_count" -eq 0 ]; then
              suggest "/lbwc:vibe --archive -- All phases complete, zero deviations"
            else
              suggest "/lbwc:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
              suggest "/lbwc:vibe -- Review before archiving"
            fi
          elif [ "$deviation_count" -gt 0 ]; then
            suggest "/lbwc:vibe -- Review remediation scope before resuming new work"
          else
            :
          fi
        elif [ -n "$current_uat_issues_phase" ]; then
          if [ "$current_uat_major_or_higher" = true ]; then
            suggest "/lbwc:vibe -- Remediate UAT issues for $current_uat_issues_label"
          else
            suggest "/lbwc:fix -- Fix minor UAT issues in $current_uat_issues_label"
          fi
        elif { [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; } && ! { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; then
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
            suggest "/lbwc:discuss $target -- Discuss phase before planning"
          elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/lbwc:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
                break
              fi
            done
          elif [ -n "$active_phase_name" ] && [ "$target" != "$active_phase_num" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/lbwc:vibe -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/lbwc:vibe -- Continue to next phase"
          fi
        fi
        if [ "$RESULT" = "skipped" ]; then
          suggest "/lbwc:vibe -- Verify completed work"
        fi
        ;;
    esac
    ;;

  plan)
    if [ "$active_phase_plans" -gt 0 ]; then
      suggest "/lbwc:vibe -- Execute $active_phase_plans plans ($effort effort)"
    else
      suggest "/lbwc:vibe -- Execute the planned phase"
    fi
    ;;

  qa)
    _qa_debug_handled=false
    if [ "${phase_count:-0}" -eq 0 ] && [ -d "$PLANNING_DIR/debugging" ]; then
      _qa_ds_output=$("$SCRIPT_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null) || true
      if [ -n "$_qa_ds_output" ]; then
        eval "$_qa_ds_output" 2>/dev/null || true
        if [ "${active_session:-none}" != "none" ] && [ -n "${session_file:-}" ] && [ -f "$session_file" ]; then
          _qa_ds_status="${session_status:-}"
          case "$_qa_ds_status" in
            qa_pending|uat_pending|fix_applied)
              case "$effective_result" in
                pass)
                  case "$_qa_ds_status" in
                    qa_pending|fix_applied)
                      suggest "/lbwc:debug --resume -- Continue to QA verification"
                      _qa_debug_handled=true
                      ;;
                    uat_pending)
                      suggest "/lbwc:debug --resume -- Continue to UAT verification"
                      _qa_debug_handled=true
                      ;;
                  esac
                  ;;
                fail|partial)
                  suggest "/lbwc:debug --resume -- Address QA failures"
                  _qa_debug_handled=true
                  ;;
                *)
                  case "$_qa_ds_status" in
                    qa_pending|fix_applied)
                      suggest "/lbwc:debug --resume -- Continue to QA verification"
                      _qa_debug_handled=true
                      ;;
                    uat_pending)
                      suggest "/lbwc:debug --resume -- Continue to UAT verification"
                      _qa_debug_handled=true
                      ;;
                  esac
                  ;;
              esac
              ;;
            qa_failed)
              suggest "/lbwc:debug --resume -- Address QA failures"
              _qa_debug_handled=true
              ;;
          esac
        fi
      fi
    fi
    if [ "$_qa_debug_handled" = true ]; then
      :
    else
    case "$effective_result" in
      pass)
        if [ -z "$current_uat_issues_phase" ] && \
           { { [ "$has_uat" = false ] && [ "$active_phase_plans" -gt 0 ] && { [ "$cfg_auto_uat" = true ] || [ "$cfg_autonomy" = "cautious" ] || [ "$cfg_autonomy" = "standard" ]; }; } \
             || { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; }; then
          if [ -n "$first_unverified_phase" ]; then
            _uv_label="$first_unverified_phase"
            [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
            suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
          else
            suggest "/lbwc:vibe -- Verify completed work"
          fi
        fi
        if [ "$all_done" = true ] || [ "$next_phase_state" = "needs_reverification" ] || { [ "$next_phase_state" = "needs_verification" ] && [ -n "$current_uat_blocking_phase" ]; }; then
          if [ "$next_phase_state" = "needs_reverification" ]; then
            suggest "/lbwc:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
          elif [ "$next_phase_state" = "needs_verification" ] && [ -n "$current_uat_blocking_phase" ]; then
            suggest "/lbwc:vibe -- Resume Verify for Phase ${pd_next_phase:-}"
          elif ! suggest_milestone_recovery; then
            if [ "$deviation_count" -eq 0 ]; then
              suggest "/lbwc:vibe --archive -- All phases complete, zero deviations"
            else
              suggest "/lbwc:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
            fi
          else
            :
          fi
        elif [ -n "$current_uat_issues_phase" ]; then
          if [ "$current_uat_major_or_higher" = true ]; then
            suggest "/lbwc:vibe -- Remediate UAT issues for $current_uat_issues_label"
          else
            suggest "/lbwc:fix -- Fix minor UAT issues in $current_uat_issues_label"
          fi
        elif { [ -n "${next_unbuilt:-}" ] || [ -n "${next_unplanned:-}" ]; } && ! { [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; }; then
          target="${next_unbuilt:-$next_unplanned}"
          if [ -n "$next_undiscussed" ] && [ -n "$target" ] && [ "$next_undiscussed" = "$target" ]; then
            suggest "/lbwc:discuss $target -- Discuss phase before planning"
          elif [ -n "$next_preseeded" ] && [ -n "$target" ] && [ "$next_preseeded" = "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/lbwc:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
                break
              fi
            done
          elif [ -n "$target" ]; then
            for dir in "$PHASES_DIR"/*/; do
              [ -d "$dir" ] || continue
              pn=$(basename "$dir" | sed 's/[^0-9].*//')
              if [ "$pn" = "$target" ]; then
                tname=$(basename "$dir" | sed 's/^[0-9]*-//')
                suggest "/lbwc:vibe -- Continue to Phase $target: $(fmt_phase_name "$tname")"
                break
              fi
            done
          else
            suggest "/lbwc:vibe -- Continue to next phase"
          fi
        fi
        ;;
      fail)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/lbwc:fix -- Fix plan $first_fail (failed QA)"
        else
          suggest "/lbwc:fix -- Fix the failing checks"
        fi
        ;;
      partial)
        if [ -n "$failing_plan_ids" ]; then
          first_fail=$(echo "$failing_plan_ids" | awk '{print $1}')
          suggest "/lbwc:fix -- Fix plan $first_fail (partial failure)"
        else
          suggest "/lbwc:fix -- Address partial failures"
        fi
        suggest "/lbwc:vibe -- Continue despite warnings"
        ;;
      *)
        suggest "/lbwc:vibe -- Continue building"
        ;;
    esac
    fi
    ;;

  fix)
    _fix_debug_handled=false
    if [ "${phase_count:-0}" -eq 0 ] && [ -d "$PLANNING_DIR/debugging" ]; then
      _fix_ds_output=$("$SCRIPT_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null) || true
      if [ -n "$_fix_ds_output" ]; then
        eval "$_fix_ds_output" 2>/dev/null || true
        if [ "${active_session:-none}" != "none" ] && [ -n "${session_file:-}" ] && [ -f "$session_file" ]; then
          _fix_ds_status="${session_status:-}"
          case "$_fix_ds_status" in
            qa_pending|fix_applied)
              suggest "/lbwc:debug --resume -- Address remaining issues"
              _fix_debug_handled=true
              ;;
            qa_failed)
              suggest "/lbwc:debug --resume -- Address QA failures"
              _fix_debug_handled=true
              ;;
            uat_pending)
              suggest "/lbwc:debug --resume -- Run UAT on the debug fix"
              _fix_debug_handled=true
              ;;
            uat_failed)
              suggest "/lbwc:debug --resume -- Address UAT issues"
              _fix_debug_handled=true
              ;;
            investigating)
              suggest "/lbwc:debug --resume -- Continue investigation"
              _fix_debug_handled=true
              ;;
          esac
        fi
      fi
    fi
    if [ "$_fix_debug_handled" = false ]; then
      suggest "/lbwc:vibe -- Verify the fix"
      if [ "$cfg_auto_uat" = true ] && [ -f "$PLANNING_DIR/.last-fix-commit" ]; then
        _marker_stale=true
        _marker_mtime=$(stat -c '%Y' "$PLANNING_DIR/.last-fix-commit" 2>/dev/null || stat -f '%m' "$PLANNING_DIR/.last-fix-commit" 2>/dev/null || echo 0)
        _now=$(date +%s 2>/dev/null || echo 0)
        if [ "$_marker_mtime" -gt 0 ] && [ "$_now" -gt 0 ]; then
          _marker_age=$(( _now - _marker_mtime ))
          [ "$_marker_age" -ge 0 ] && [ "$_marker_age" -le 86400 ] && _marker_stale=false
        fi
        if [ "$_marker_stale" = false ]; then
          suggest "/lbwc:verify -- Run UAT on the fix"
        fi
      fi
      suggest "/lbwc:vibe -- Continue building"
    fi
    ;;

  verify)
    _verify_debug_handled=false
    if [ "${phase_count:-0}" -eq 0 ] && [ -d "$PLANNING_DIR/debugging" ]; then
      _verify_ds_output=$("$SCRIPT_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null) || true
      if [ -n "$_verify_ds_output" ]; then
        eval "$_verify_ds_output" 2>/dev/null || true
        if [ "${active_session:-none}" != "none" ] && [ -n "${session_file:-}" ] && [ -f "$session_file" ]; then
          _verify_ds_status="${session_status:-}"
          if [ "$_verify_ds_status" = "uat_failed" ]; then
            suggest "/lbwc:debug --resume -- Address UAT issues"
            _verify_debug_handled=true
          fi
        fi
      fi
    fi
    if [ "$_verify_debug_handled" = false ]; then
    case "$effective_result" in
      pass)
        if [ "$next_phase_state" = "needs_reverification" ]; then
          suggest "/lbwc:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
        elif [ "$next_phase_state" = "needs_verification" ] && [ -n "$current_uat_blocking_phase" ]; then
          suggest "/lbwc:vibe -- Resume Verify for Phase ${pd_next_phase:-}"
        elif [ "$all_done" = true ]; then
          if ! suggest_milestone_recovery; then
            suggest "/lbwc:vibe --archive -- All verified, ready to ship"
          fi
        else
          suggest "/lbwc:vibe -- Continue to next phase"
        fi
        ;;
      issues_found)
        if [ "$uat_major_or_higher" = true ]; then
          if [ -n "$verify_target_phase" ]; then
            suggest "/lbwc:vibe -- Remediate UAT issues for Phase $verify_target_phase"
          else
            suggest "/lbwc:vibe -- Remediate UAT issues from the latest report"
          fi
        else
          suggest "/lbwc:fix -- Fix minor issues found during UAT"
        fi
        ;;
      *)
        suggest "/lbwc:vibe -- Continue building"
        ;;
    esac
    fi
    ;;

  debug)
    _ds_status=""
    if [ -d "$PLANNING_DIR/debugging" ]; then
      _ds_output=$("$SCRIPT_DIR/debug-session-state.sh" get-or-latest "$PLANNING_DIR" 2>/dev/null) || true
      if [ -n "$_ds_output" ]; then
        eval "$_ds_output" 2>/dev/null || true
        if [ "${active_session:-none}" != "none" ] && [ -n "${session_file:-}" ] && [ -f "$session_file" ]; then
          _ds_status="${session_status:-}"
        fi
      fi
    fi
    case "$_ds_status" in
      qa_pending|fix_applied)
        suggest "/lbwc:debug --resume -- Continue to QA verification"
        ;;
      qa_failed)
        suggest "/lbwc:debug --resume -- Address QA failures"
        ;;
      uat_pending)
        suggest "/lbwc:debug --resume -- Continue to UAT verification"
        ;;
      uat_failed)
        suggest "/lbwc:debug --resume -- Address UAT issues"
        ;;
      complete)
        suggest "/lbwc:status -- View project status"
        ;;
      investigating)
        suggest "/lbwc:debug --resume -- Continue investigation"
        suggest "/lbwc:fix -- Apply the fix"
        ;;
      *)
        suggest "/lbwc:fix -- Apply the fix"
        suggest "/lbwc:vibe -- Continue building"
        ;;
    esac
    ;;

  config)
    if [ "$has_project" = true ]; then
      suggest "/lbwc:status -- View project state"
    else
      suggest "/lbwc:vibe -- Define your project and start building"
    fi
    ;;

  archive)
    suggest "/lbwc:vibe -- Start new work"
    ;;

  status)
    if [ "$next_phase_state" = "needs_reverification" ]; then
      suggest "/lbwc:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
    elif [ "$next_phase_state" = "needs_verification" ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
      else
        suggest "/lbwc:vibe -- Verify completed phases before continuing"
      fi
    elif [ "$all_done" = true ]; then
      if ! suggest_milestone_recovery; then
        if [ "$deviation_count" -eq 0 ]; then
          suggest "/lbwc:vibe --archive -- All phases complete, zero deviations"
        else
          suggest "/lbwc:vibe --archive -- Archive completed work"
        fi
      else
        :
      fi
    elif [ -n "$current_uat_issues_phase" ]; then
      if [ "$current_uat_major_or_higher" = true ]; then
        suggest "/lbwc:vibe -- Remediate UAT issues for $current_uat_issues_label"
      else
        suggest "/lbwc:fix -- Fix minor UAT issues in $current_uat_issues_label"
      fi
    elif [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
      else
        suggest "/lbwc:vibe -- Verify completed phases before continuing"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
        suggest "/lbwc:discuss $target -- Discuss phase before planning"
      elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/lbwc:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
            break
          fi
        done
      else
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/lbwc:vibe -- Continue Phase $target: $(fmt_phase_name "$tname")"
            break
          fi
        done
      fi
    else
      suggest "/lbwc:vibe -- Start building"
    fi
    ;;

  map)
    suggest "/lbwc:vibe -- Start building"
    suggest "/lbwc:status -- View project state"
    ;;

  discuss|assumptions)
    suggest "/lbwc:vibe --plan -- Plan this phase"
    suggest "/lbwc:vibe -- Plan and execute in one flow"
    ;;

  resume)
    if [ "$next_phase_state" = "needs_reverification" ]; then
      suggest "/lbwc:vibe -- Re-verify Phase ${pd_next_phase:-} after remediation"
    elif [ "$next_phase_state" = "needs_verification" ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
      else
        suggest "/lbwc:vibe -- Verify completed phases before continuing"
      fi
    elif [ -n "$current_uat_issues_phase" ]; then
      if [ "$current_uat_major_or_higher" = true ]; then
        suggest "/lbwc:vibe -- Remediate UAT issues for $current_uat_issues_label"
      else
        suggest "/lbwc:fix -- Fix minor UAT issues in $current_uat_issues_label"
      fi
    elif [ "$all_done" = true ]; then
      if ! suggest_milestone_recovery; then
        if [ "$deviation_count" -eq 0 ]; then
          suggest "/lbwc:vibe --archive -- All phases complete, zero deviations"
        else
          suggest "/lbwc:vibe --archive -- Archive completed work ($deviation_count deviation(s) logged)"
        fi
      fi
    elif [ "$cfg_auto_uat" = true ] && [ "$has_unverified_phases" = true ]; then
      if [ -n "$first_unverified_phase" ]; then
        _uv_label="$first_unverified_phase"
        [ -n "$first_unverified_slug" ] && _uv_label="$first_unverified_phase ($(fmt_phase_name "${first_unverified_slug#*-}"))"
        suggest "/lbwc:vibe -- Verify $_uv_label before continuing"
      else
        suggest "/lbwc:vibe -- Verify completed phases before continuing"
      fi
    elif [ -n "$next_unbuilt" ] || [ -n "$next_unplanned" ]; then
      target="${next_unbuilt:-$next_unplanned}"
      if [ -n "$next_undiscussed" ] && [ "$next_undiscussed" = "$target" ]; then
        suggest "/lbwc:discuss $target -- Discuss phase before planning"
      elif [ -n "$next_preseeded" ] && [ "$next_preseeded" = "$target" ]; then
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/lbwc:vibe -- Plan Phase $target: $(fmt_phase_name "$tname") (discussion pre-seeded from UAT)"
            break
          fi
        done
      else
        for dir in "$PHASES_DIR"/*/; do
          [ -d "$dir" ] || continue
          pn=$(basename "$dir" | sed 's/[^0-9].*//')
          if [ "$pn" = "$target" ]; then
            tname=$(basename "$dir" | sed 's/^[0-9]*-//')
            suggest "/lbwc:vibe -- Continue Phase $target: $(fmt_phase_name "$tname")"
            break
          fi
        done
      fi
    else
      suggest "/lbwc:vibe -- Continue building"
    fi
    suggest "/lbwc:status -- View current progress"
    ;;

  *)
    if [ "$has_project" = true ]; then
      suggest "/lbwc:vibe -- Continue building"
      suggest "/lbwc:status -- View project progress"
    else
      suggest "/lbwc:vibe -- Start a new project"
    fi
    ;;
esac

case "$CMD" in
  map|init|help|update|whats-new|uninstall) ;;
  *)
    if [ "$has_project" = true ] && [ "$phase_count" -gt 0 ]; then
      if [ "$map_exists" = false ]; then
        suggest "/lbwc:map -- Map your codebase for better planning"
      elif [ "$map_staleness" -gt 30 ]; then
        suggest "/lbwc:map --incremental -- Codebase map is ${map_staleness}% stale"
      fi
    fi
    ;;
esac

case "$CMD" in
  init|help|update|whats-new|uninstall) ;;
  *)
    if [ "$has_project" = true ] && [ -d "$PHASES_DIR" ]; then
      _ki_total=0
      while IFS= read -r _ki_dir; do
        [ -d "$_ki_dir" ] || continue
        _ki_file="$_ki_dir/known-issues.json"
        if [ -f "$_ki_file" ]; then
          _ki_count=$(jq -r '.issues | length' "$_ki_file" 2>/dev/null || echo "0")
          _ki_total=$(( _ki_total + _ki_count ))
        fi
      done < <(find "$PHASES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
      if [ "$_ki_total" -gt 0 ]; then
        echo ""
        echo "Note: $_ki_total known issue(s) deferred across phases, visible in /lbwc:list-todos"
      fi
    fi
    ;;
esac
