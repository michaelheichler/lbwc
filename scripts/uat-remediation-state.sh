#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  source "$SCRIPT_DIR/uat-utils.sh"
fi
CMD="${1:-}"
PHASE_DIR="${2:-}"
SEVERITY_ARG="${3:-}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: uat-remediation-state.sh <get|advance|reset|init|get-or-init|needs-round|current-round> <phase-dir> [severity]" >&2
  exit 1
fi

reject_milestone_phase_dir() {
  local phase_dir="$1"

  case "$phase_dir" in
    */.lbwc-planning/milestones/*|.lbwc-planning/milestones/*)
      echo "Error: refusing to operate on archived milestone path: $phase_dir" >&2
      echo "Remediation must target active phases in .lbwc-planning/phases/" >&2
      echo "Use create-remediation-phase.sh to create active remediation phases from milestone UAT." >&2
      exit 1
      ;;
  esac
}

canonicalize_existing_or_parent() {
  local path="$1" parent base parent_real

  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
    return 0
  fi

  parent=$(dirname "$path")
  base=$(basename "$path")
  if parent_real=$(cd "$parent" 2>/dev/null && pwd -P); then
    printf '%s/%s\n' "$parent_real" "$base"
  else
    printf '%s\n' "$path"
  fi
}

active_phase_root() {
  local candidate="$1"
  if [[ "$candidate" != *"/.lbwc-planning/phases/"* ]]; then
    echo "Error: UAT remediation phase must be under active .lbwc-planning/phases/: $candidate" >&2
    exit 1
  fi
  printf '%s\n' "${candidate%%/.lbwc-planning/phases/*}"
}

canonicalize_phase_dir() {
  local raw_phase_dir="$1" candidate phase_root
  if [[ "$raw_phase_dir" = /* ]]; then
    candidate="$raw_phase_dir"
  else
    candidate="${LBWC_CONFIG_ROOT:-$(pwd -P)}/$raw_phase_dir"
  fi
  candidate=$(canonicalize_existing_or_parent "$candidate")
  reject_milestone_phase_dir "$candidate"
  phase_root=$(active_phase_root "$candidate")
  [ -n "$phase_root" ] || { echo "Error: unable to determine LBWC root from phase path: $candidate" >&2; exit 1; }
  export LBWC_CONFIG_ROOT="$phase_root"
  export LBWC_PLANNING_DIR="$phase_root/.lbwc-planning"
  printf '%s\n' "$candidate"
}

reject_milestone_phase_dir "$PHASE_DIR"
PHASE_DIR=$(canonicalize_phase_dir "$PHASE_DIR")

case "$PHASE_DIR" in
  */.lbwc-planning/milestones/*)
    echo "Error: refusing to operate on archived milestone path: $PHASE_DIR" >&2
    echo "Remediation must target active phases in .lbwc-planning/phases/" >&2
    echo "Use create-remediation-phase.sh to create active remediation phases from milestone UAT." >&2
    exit 1
    ;;
esac

STATE_FILE="$PHASE_DIR/remediation/uat/.uat-remediation-stage"
LEGACY_STATE_FILE="$PHASE_DIR/.uat-remediation-stage"
LEGACY_REMED_STATE_FILE="$PHASE_DIR/remediation/.uat-remediation-stage"

reconcile_uat_state() {
  local changed_path="${1:-$STATE_FILE}"

  [ -f "$SCRIPT_DIR/reconcile-state-md.sh" ] || return 0
  if [ -e "$changed_path" ]; then
    bash "$SCRIPT_DIR/reconcile-state-md.sh" --changed "$changed_path" >/dev/null 2>&1 || true
  else
    bash "$SCRIPT_DIR/reconcile-state-md.sh" --changed "$PHASE_DIR" >/dev/null 2>&1 || true
  fi
}

read_state_stage_value() {
  local file="$1" _val=""

  if grep -q '^stage=' "$file" 2>/dev/null; then
    _val=$(grep '^stage=' "$file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  else
    _val=$(tr -d '[:space:]' < "$file")
  fi
  printf '%s\n' "${_val:-none}"
}

read_state_round_value() {
  local file="$1" _val=""

  _val=$(grep '^round=' "$file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  printf '%s\n' "${_val:-01}"
}

normalize_round_padded_value() {
  local raw="$1" num

  num=$(printf '%s\n' "$raw" | sed 's/^0*//')
  num="${num:-0}"
  case "$num" in
    *[!0-9]*|"")
      echo "Error: invalid UAT remediation round value: $raw" >&2
      return 1
      ;;
  esac
  printf '%02d\n' "$num"
}

migrate_legacy_remediation_state_if_needed() {
  [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_REMED_STATE_FILE" ] || return 0

  mkdir -p "$PHASE_DIR/remediation/uat"
  cp "$LEGACY_REMED_STATE_FILE" "$STATE_FILE"
  for _mig_rd in "$PHASE_DIR/remediation"/round-*/; do
    [ -d "$_mig_rd" ] || continue
    _mig_name=$(basename "$_mig_rd")
    if [ ! -d "$PHASE_DIR/remediation/uat/$_mig_name" ]; then
      mv "$_mig_rd" "$PHASE_DIR/remediation/uat/$_mig_name"
    fi
  done
  rm -f "$LEGACY_REMED_STATE_FILE"
  reconcile_uat_state "$STATE_FILE"
}

preflight_legacy_remediation_needs_round() {
  local legacy_stage legacy_round legacy_round_padded legacy_uat legacy_uat_class

  [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_REMED_STATE_FILE" ] || return 0

  legacy_stage=$(read_state_stage_value "$LEGACY_REMED_STATE_FILE")
  case "$legacy_stage" in
    verify|done) ;;
    *)
      echo "Error: needs-round requires stage verify or done, got: $legacy_stage" >&2
      exit 1
      ;;
  esac

  legacy_round=$(read_state_round_value "$LEGACY_REMED_STATE_FILE")
  legacy_round_padded=$(normalize_round_padded_value "$legacy_round") || exit 1
  legacy_uat="$PHASE_DIR/remediation/round-${legacy_round_padded}/R${legacy_round_padded}-UAT.md"
  if [ ! -f "$legacy_uat" ]; then
    echo "Error: needs-round current round UAT evidence is missing for round $legacy_round_padded" >&2
    exit 1
  fi

  if type uat_file_status_class >/dev/null 2>&1; then
    legacy_uat_class=$(uat_file_status_class "$legacy_uat")
    if [ "$legacy_uat_class" != "issues_found" ]; then
      echo "Error: needs-round requires a finalized 'issues_found' UAT; current UAT is '$legacy_uat_class': $legacy_uat" >&2
      exit 1
    fi
  fi
}

if [ "$CMD" != "needs-round" ]; then
  migrate_legacy_remediation_state_if_needed
fi

MAJOR_STAGES=("research" "plan" "execute" "done")
MINOR_STAGES=("fix" "done")

extract_phase_num() {
  uat_phase_num_for_dir "$PHASE_DIR"
}

infer_legacy_current_round() {
  uat_infer_legacy_current_round "$PHASE_DIR"
}

resolve_legacy_round() {
  local stored_round="$1"
  uat_resolve_legacy_round "$PHASE_DIR" "$stored_round"
}

get_stage() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^stage=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$_val" ]; then
      echo "$_val"
    else
      tr -d '[:space:]' < "$STATE_FILE"
    fi
  elif [ -f "$LEGACY_STATE_FILE" ]; then
    local _val
    _val=$(grep '^stage=' "$LEGACY_STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
    if [ -n "$_val" ]; then
      echo "$_val"
    else
      cat "$LEGACY_STATE_FILE" | tr -d '[:space:]'
    fi
  else
    echo "none"
  fi
}

get_round() {
  local _val=""

  if [ -f "$STATE_FILE" ]; then
    _val=$(grep '^round=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$_val" ]; then
      if [ "$(get_layout)" = "legacy" ]; then
        resolve_legacy_round "$_val"
      else
        echo "$_val"
      fi
    elif [ "$(get_layout)" = "legacy" ]; then
      resolve_legacy_round ""
    else
      echo "01"
    fi
  else
    if [ -f "$LEGACY_STATE_FILE" ]; then
      _val=$(grep '^round=' "$LEGACY_STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
      resolve_legacy_round "$_val"
    else
      echo "01"
    fi
  fi
}

get_layout() {
  if [ -f "$STATE_FILE" ]; then
    local _val
    _val=$(grep '^layout=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    echo "${_val:-round-dir}"
  else
    if [ -f "$LEGACY_STATE_FILE" ]; then
      local _val
      _val=$(grep '^layout=' "$LEGACY_STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
      echo "${_val:-legacy}"
    else
      echo "legacy"
    fi
  fi
}

get_round_dir() {
  local round
  round=$(get_round)
  echo "$PHASE_DIR/remediation/uat/round-${round}"
}

start_new_round() {
  local current_round next_round next_round_padded
  current_round=$(get_round)
  next_round=$(( 10#$current_round + 1 ))
  next_round_padded=$(printf '%02d' "$next_round")
  mkdir -p "$PHASE_DIR/remediation/uat/round-${next_round_padded}"
  printf 'stage=research\nround=%s\nlayout=round-dir\n' "$next_round_padded" > "$STATE_FILE"
  [ -f "$LEGACY_STATE_FILE" ] && rm -f "$LEGACY_STATE_FILE"
  reconcile_uat_state "$STATE_FILE"
  echo "research"
  echo "round=${next_round_padded}"
  echo "round_dir=$PHASE_DIR/remediation/uat/round-${next_round_padded}"
  echo "research_path="
  echo "plan_path="
  echo "summary_path=$PHASE_DIR/remediation/uat/round-${next_round_padded}/R${next_round_padded}-SUMMARY.md"
}

next_stage() {
  local current="$1"
  local -a stages

  case "$current" in
    research|plan|execute) stages=("${MAJOR_STAGES[@]}") ;;
    fix)                  stages=("${MINOR_STAGES[@]}") ;;
    done)                 echo "verify"; return 0 ;;
    *)                    echo "done"; return 0 ;;
  esac

  local found=false
  for s in "${stages[@]}"; do
    if [ "$found" = true ]; then
      echo "$s"
      return 0
    fi
    if [ "$s" = "$current" ]; then
      found=true
    fi
  done

  echo "done"
}

do_init() {
  local severity="$1"
  local initial_stage
  case "$severity" in
    major|critical) initial_stage="research" ;;
    minor)          initial_stage="fix" ;;
    *)              initial_stage="research" ;;
  esac

  mkdir -p "$PHASE_DIR/remediation/uat/round-01"

  printf 'stage=%s\nround=01\nlayout=round-dir\n' "$initial_stage" > "$STATE_FILE"

  rm -f "$LEGACY_STATE_FILE"
  rm -f "$LEGACY_REMED_STATE_FILE"

  reconcile_uat_state "$STATE_FILE"

  echo "$initial_stage"

  local context_file uat_file uat_content _already_seeded
  _init_emit_context=false
  _init_context_file=""

  context_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-CONTEXT.md' 2>/dev/null | sort | head -1)
  if type latest_non_source_uat &>/dev/null; then
    uat_file=$(latest_non_source_uat "$PHASE_DIR")
  else
    uat_file=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-UAT.md' ! -name '*SOURCE-UAT.md' 2>/dev/null | sort | tail -1)
  fi

  if [ -n "$uat_file" ] && [ -f "$uat_file" ]; then
    uat_content=$(cat "$uat_file")
    uat_content=$(printf '%s\n' "$uat_content" | sed -E '/^---[[:space:]]*$/,/^---[[:space:]]*$/{
      s/^([[:space:]]*(phase|round)[[:space:]]*:[[:space:]]*)"([0-9]+)"/\1\3/
    }')

    if [ -n "$context_file" ] && [ -f "$context_file" ]; then
      _already_seeded=false
      if awk '
        BEGIN { in_fm=0; found=0 }
        NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
        in_fm && /^---[[:space:]]*$/ { exit }
        in_fm && /^pre_seeded[[:space:]]*:[[:space:]]*"?true"?[[:space:]]*$/ { found=1; exit }
        END { exit !found }
      ' "$context_file" 2>/dev/null; then
        _already_seeded=true
      fi

      if [ "$_already_seeded" = true ]; then
        awk '/^## UAT Remediation Issues[[:space:]]*$/ { exit } { print }' \
          "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        {
          echo "## UAT Remediation Issues"
          echo ""
          printf '%s\n' "$uat_content"
        } >> "$context_file"
        _init_emit_context=true
        _init_context_file="$context_file"
      else
        if head -1 "$context_file" | grep -q '^---[[:space:]]*$'; then
          awk '
            NR==1 && /^---[[:space:]]*$/ { print; next }
            !inserted && /^---[[:space:]]*$/ { print "pre_seeded: true"; inserted=1 }
            { print }
          ' "$context_file" > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        else
          {
            echo "---"
            echo "pre_seeded: true"
            echo "---"
            echo ""
            cat "$context_file"
          } > "${context_file}.tmp" && mv "${context_file}.tmp" "$context_file"
        fi

        {
          echo ""
          echo "---"
          echo ""
          echo "## UAT Remediation Issues"
          echo ""
          printf '%s\n' "$uat_content"
        } >> "$context_file"
        _init_emit_context=true
        _init_context_file="$context_file"
      fi
    else
      local phase_basename phase_num
      phase_basename=$(basename "$PHASE_DIR")
      phase_num="${phase_basename%%[^0-9]*}"
      context_file="$PHASE_DIR/${phase_num}-CONTEXT.md"

      {
        echo "---"
        echo "pre_seeded: true"
        echo "---"
        echo ""
        echo "# Phase ${phase_num}: UAT Remediation Context"
        echo ""
        echo "## UAT Remediation Issues"
        echo ""
        printf '%s\n' "$uat_content"
      } > "$context_file"
      _init_emit_context=true
      _init_context_file="$context_file"
    fi
  fi
}

emit_init_context() {
  if [ "$_init_emit_context" = true ] && [ -n "$_init_context_file" ] && [ -f "$_init_context_file" ]; then
    echo "---CONTEXT---"
    cat "$_init_context_file"
  fi
}

emit_plan_metadata() {
  local round round_dir layout research_path="" plan_path="" summary_path=""

  round=$(get_round)
  round_dir=$(get_round_dir)
  layout=$(get_layout)
  summary_path="${round_dir}/R${round}-SUMMARY.md"

  local rr_research="${round_dir}/R${round}-RESEARCH.md"
  if [ -f "$rr_research" ]; then
    research_path="$rr_research"
  elif [ "$layout" = "legacy" ]; then
    local phase_prefix
    phase_prefix=$(extract_phase_num)
    local legacy_per_plan legacy_phase_level
    legacy_per_plan=$(find "$PHASE_DIR" -maxdepth 1 -name "${phase_prefix}-*-RESEARCH.md" ! -name '.*' 2>/dev/null | sort | tail -1)
    legacy_phase_level="${PHASE_DIR}/${phase_prefix}-RESEARCH.md"
    if [ -n "$legacy_per_plan" ] && [ -f "$legacy_per_plan" ]; then
      research_path="$legacy_per_plan"
    elif [ -f "$legacy_phase_level" ]; then
      research_path="$legacy_phase_level"
    fi
  fi

  local rr_plan="${round_dir}/R${round}-PLAN.md"
  if [ -f "$rr_plan" ]; then
    plan_path="$rr_plan"
  elif [ "$layout" = "legacy" ]; then
    local phase_prefix
    phase_prefix=$(extract_phase_num)
    local legacy_plan
    legacy_plan=$(find "$PHASE_DIR" -maxdepth 1 -name "${phase_prefix}-*-PLAN.md" ! -name '.*' 2>/dev/null | sort | tail -1)
    if [ -n "$legacy_plan" ] && [ -f "$legacy_plan" ]; then
      plan_path="$legacy_plan"
    fi
  fi

  echo "round=${round}"
  echo "round_dir=${round_dir}"
  echo "research_path=${research_path}"
  echo "plan_path=${plan_path}"
  echo "summary_path=${summary_path}"
}

case "$CMD" in
  get)
    get_stage
    ;;

  advance)
    current=$(get_stage)
    if [ "$current" = "none" ]; then
      echo "$current"
    elif [ "$current" = "verify" ]; then
      start_new_round
    elif [ "$current" = "verified" ]; then
      echo "$current"
    else
      new_stage=$(next_stage "$current")
      round=$(get_round)
      layout=$(get_layout)
      mkdir -p "$(dirname "$STATE_FILE")"
      printf 'stage=%s\nround=%s\nlayout=%s\n' "$new_stage" "$round" "$layout" > "$STATE_FILE"
      [ -f "$LEGACY_STATE_FILE" ] && rm -f "$LEGACY_STATE_FILE"
      reconcile_uat_state "$STATE_FILE"
      echo "$new_stage"
    fi
    ;;

  reset)
    rm -f "$STATE_FILE" "$LEGACY_STATE_FILE"
    reconcile_uat_state "$PHASE_DIR"
    echo "none"
    ;;

  needs-round)
    if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_REMED_STATE_FILE" ]; then
      preflight_legacy_remediation_needs_round
      migrate_legacy_remediation_state_if_needed
    fi
    if [ ! -f "$STATE_FILE" ] && [ ! -f "$LEGACY_STATE_FILE" ]; then
      echo "Error: no UAT remediation state exists for $PHASE_DIR, cannot advance to next round without prior init" >&2
      exit 1
    fi
    current_stage=$(get_stage)
    case "$current_stage" in
      verify|done) ;;
      *)
        echo "Error: needs-round requires stage verify or done, got: $current_stage" >&2
        exit 1
        ;;
    esac
    if type uat_file_status_class >/dev/null 2>&1; then
      current_layout=$(get_layout)
      if [ "$current_layout" = "round-dir" ]; then
        current_round=$(get_round)
        current_round_padded=$(normalize_round_padded_value "$current_round") || exit 1
        phase_num=$(extract_phase_num)
        current_round_uat="$PHASE_DIR/remediation/uat/round-${current_round_padded}/R${current_round_padded}-UAT.md"
        current_flat_uat="$PHASE_DIR/${phase_num}-UAT-round-${current_round_padded}.md"
        current_uat_file=""
        if [ -f "$current_round_uat" ]; then
          current_uat_file="$current_round_uat"
        elif [ -n "$phase_num" ] && [ -f "$current_flat_uat" ]; then
          current_uat_file="$current_flat_uat"
        else
          echo "Error: needs-round current round UAT evidence is missing for round $current_round_padded" >&2
          exit 1
        fi
        current_uat_class=$(uat_file_status_class "$current_uat_file")
        if [ "$current_uat_class" != "issues_found" ]; then
          echo "Error: needs-round requires a finalized 'issues_found' UAT; current UAT is '$current_uat_class': $current_uat_file" >&2
          exit 1
        fi
      elif type current_uat >/dev/null 2>&1; then
        current_uat_file=$(current_uat "$PHASE_DIR")
        if [ -n "$current_uat_file" ] && [ -f "$current_uat_file" ]; then
          current_uat_class=$(uat_file_status_class "$current_uat_file")
          if [ "$current_uat_class" != "issues_found" ]; then
            echo "Error: needs-round requires a finalized 'issues_found' UAT; current UAT is '$current_uat_class': $current_uat_file" >&2
            exit 1
          fi
        fi
      fi
    fi
    start_new_round
    ;;

  current-round)
    get_round
    ;;

  init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    do_init "$SEVERITY_ARG"
    emit_plan_metadata
    emit_init_context
    ;;

  get-or-init)
    if [ -z "$SEVERITY_ARG" ]; then
      echo "Usage: uat-remediation-state.sh get-or-init <phase-dir> <major|minor>" >&2
      exit 1
    fi
    existing=$(get_stage)
    if [ "$existing" != "none" ]; then
      if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_STATE_FILE" ]; then
        _resume_round=$(get_round)
        mkdir -p "$PHASE_DIR/remediation/uat/round-${_resume_round}"
        printf 'stage=%s\nround=%s\nlayout=legacy\n' "$existing" "$_resume_round" > "$STATE_FILE"
        rm -f "$LEGACY_STATE_FILE"
        reconcile_uat_state "$STATE_FILE"
      fi
      echo "$existing"
      emit_plan_metadata
    else
      do_init "$SEVERITY_ARG"
      emit_plan_metadata
      emit_init_context
    fi
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
