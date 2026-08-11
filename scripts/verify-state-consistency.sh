#!/usr/bin/env bash
set -u

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIFT_COUNT=0

drift() {
  printf 'DRIFT %s: %s\n' "$1" "$2"
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

skip() {
  printf 'SKIP %s: %s not found\n' "$1" "$2"
}

phase_dirs() {
  find "$PLANNING_DIR/phases" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' -print 2>/dev/null | sort
}

phase_dir_for_number() {
  local number
  number=$(printf '%02d' "$((10#$1))" 2>/dev/null) || return 1
  find "$PLANNING_DIR/phases" -mindepth 1 -maxdepth 1 -type d \
    -name "$number-*" -print -quit 2>/dev/null
}

count_plan_files() {
  find "$1" -maxdepth 1 -type f \( -name '*-PLAN.md' -o -name 'PLAN.md' \) -print 2>/dev/null | wc -l | tr -d '[:space:]'
}

count_summary_files() {
  find "$1" -maxdepth 1 -type f \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) -print 2>/dev/null | wc -l | tr -d '[:space:]'
}

check_state() {
  local state_file="$PLANNING_DIR/STATE.md" phase plans_done plans_total phase_dir actual_plans actual_summaries
  [[ -f "$state_file" ]] || return 0
  phase=$(grep '^Phase:' "$state_file" | head -1 | sed -E 's/^Phase:[[:space:]]*([0-9]+).*/\1/' | tr -d '[:space:]')
  plans_done=$(grep '^Plans:' "$state_file" | head -1 | sed -E 's/^Plans:[[:space:]]*([0-9]+)\/([0-9]+).*/\1/' | tr -d '[:space:]')
  plans_total=$(grep '^Plans:' "$state_file" | head -1 | sed -E 's/^Plans:[[:space:]]*([0-9]+)\/([0-9]+).*/\2/' | tr -d '[:space:]')
  if [[ ! "$phase" =~ ^[0-9]+$ ]]; then
    drift "STATE" "Phase field is missing or invalid"
    return 0
  fi
  phase_dir=$(phase_dir_for_number "$phase")
  if [[ -z "$phase_dir" ]]; then
    drift "STATE" "Phase $phase has no directory"
    return 0
  fi
  actual_plans=$(count_plan_files "$phase_dir")
  actual_summaries=$(count_summary_files "$phase_dir")
  if [[ ! "$plans_done" =~ ^[0-9]+$ || ! "$plans_total" =~ ^[0-9]+$ || "$plans_total" -ne "$actual_plans" || "$plans_done" -ne "$actual_summaries" ]]; then
    drift "STATE" "Plans is ${plans_done:-invalid}/${plans_total:-invalid}, disk is $actual_summaries/$actual_plans"
  fi
}

check_roadmap() {
  local roadmap="$PLANNING_DIR/ROADMAP.md" line number phase_dir name
  [[ -f "$roadmap" ]] || return 0
  while IFS= read -r line; do
    number=$(printf '%s\n' "$line" | sed -nE 's/^### Phase[[:space:]]+([0-9]+).*/\1/p' | tr -d '[:space:]')
    [[ "$number" =~ ^[0-9]+$ ]] || continue
    phase_dir=$(phase_dir_for_number "$number")
    [[ -n "$phase_dir" ]] || drift "ROADMAP" "Phase $number has no directory"
  done < "$roadmap"
  while IFS= read -r phase_dir; do
    name=$(basename "$phase_dir")
    number=$((10#${name%%-*}))
    grep -qE "^### Phase[[:space:]]+0*$number([:]|[[:space:]])" "$roadmap" || drift "ROADMAP" "directory $name is not listed"
  done < <(phase_dirs)
}

check_manifest() {
  local manifest="$PLANNING_DIR/.agent-manifest.json"
  [[ -f "$manifest" ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    skip "agent_manifest" "jq"
    return 0
  fi
  while IFS=$'\t' read -r agent_id state timestamp; do
    [[ -n "$agent_id" ]] || continue
    if [[ -z "$timestamp" ]]; then
      drift "agent_manifest" "$agent_id has active state $state without timestamp"
    elif ! date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${timestamp%%.*}Z" '+%s' >/dev/null 2>&1; then
      drift "agent_manifest" "$agent_id has invalid timestamp $timestamp"
    else
      local epoch now
      epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${timestamp%%.*}Z" '+%s' 2>/dev/null || echo 0)
      now=$(date '+%s')
      (( now - epoch > 86400 )) && drift "agent_manifest" "$agent_id is $state and older than 24h"
    fi
  done < <(jq -r '(.agents // .) | if type == "array" then .[] else to_entries[] | .value end | select(.state == "registered" or .state == "running") | [(.id // .agent_id // .name // "unknown"), .state, (.timestamp // .last_activity_at // .created_at // .registered_at // .updated_at // "")] | @tsv' "$manifest" 2>/dev/null)
}

check_deviq() {
  [[ -d "$PLANNING_DIR/deviq" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    skip "deviq" "python3"
    return 0
  fi
  python3 "$SCRIPT_DIR/lib/deviq-record.py" verify --root "$PLANNING_DIR/deviq" >/dev/null 2>&1 || drift "deviq" "hash chain verification failed"
}

check_remediation() {
  local state_file round stage_value round_dir summary_path
  while IFS= read -r state_file; do
    round=$(grep '^round=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    stage_value=$(grep '^stage=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    [[ "$round" =~ ^[0-9]+$ ]] || { drift "remediation" "$state_file has invalid round"; continue; }
    round=$(printf '%02d' "$((10#$round))")
    round_dir="$(dirname "$state_file")/round-$round"
    [[ -d "$round_dir" ]] || drift "remediation" "$state_file points at missing round-$round"
    summary_path="$round_dir/R${round}-SUMMARY.md"
    [[ "$stage_value" != verify || -f "$summary_path" ]] || drift "remediation" "$state_file is verify without $summary_path"
  done < <(find "$PLANNING_DIR/phases" -type f \( -path '*/remediation/qa/.qa-remediation-stage' -o -path '*/remediation/uat/.uat-remediation-stage' \) -print 2>/dev/null)
}

[[ -d "$PLANNING_DIR" ]] || { printf 'state_consistency=no_planning_dir\n'; exit 0; }
check_state
check_roadmap
check_manifest
check_deviq
check_remediation

if (( DRIFT_COUNT == 0 )); then
  printf 'state_consistency=ok\n'
  exit 0
fi
exit 1