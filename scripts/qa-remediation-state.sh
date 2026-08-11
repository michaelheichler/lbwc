#!/usr/bin/env bash

set -euo pipefail

CMD="${1:-}"
PHASE_DIR="${2:-}"
REQUESTED_STAGE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_PHASE_DIR="${QA_REMEDIATION_OUTPUT_PHASE_DIR:-$PHASE_DIR}"
OUTPUT_PHASE_DIR="${OUTPUT_PHASE_DIR%/}"

if [ -z "$CMD" ] || [ -z "$PHASE_DIR" ]; then
  echo "Usage: qa-remediation-state.sh <get|get-or-init|advance|reset|init|needs-round|open|stage> <phase-dir> [stage]" >&2
  exit 1
fi

case "$PHASE_DIR" in
  */.lbwc-planning/milestones/*|.lbwc-planning/milestones/*)
    echo "Error: refusing to operate on archived milestone path: $PHASE_DIR" >&2
    exit 1
    ;;
esac

if [[ "$PHASE_DIR" != /* ]]; then
  PHASE_DIR="$(pwd -P)/$PHASE_DIR"
fi
PHASE_DIR="$(cd "$PHASE_DIR" 2>/dev/null && pwd -P)"
case "$PHASE_DIR" in
  */.lbwc-planning/phases/*) ;;
  *)
    echo "Error: QA remediation phase must be under active .lbwc-planning/phases/: $PHASE_DIR" >&2
    exit 1
    ;;
esac

STATE_DIR="$PHASE_DIR/remediation/qa"
STATE_FILE="$STATE_DIR/.qa-remediation-stage"
LOCK_DIR="$STATE_DIR/.qa-remediation.lock"
STAGES=(plan execute verify "done")
LOCK_HELD=false

release_lock() {
  if [ "$LOCK_HELD" = true ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

lock_owner_alive() {
  local owner
  owner=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
  case "$owner" in
    ''|*[!0-9]*|0) return 1 ;;
  esac
  kill -0 "$owner" 2>/dev/null
}

lock_mtime() {
  local mtime
  mtime=$(stat -c %Y "$LOCK_DIR" 2>/dev/null) || mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null) || return 1
  case "$mtime" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$mtime"
}

reclaim_stale_lock() {
  local stale_seconds now mtime age stale_dir
  lock_owner_alive && return 0
  if [ -f "$LOCK_DIR/pid" ]; then
    stale_dir="${LOCK_DIR}.stale.${BASHPID:-$$}"
  else
    stale_seconds="${QA_REMEDIATION_LOCK_STALE_SECONDS:-30}"
    case "$stale_seconds" in ''|*[!0-9]*) stale_seconds=30 ;; esac
    now=$(date +%s 2>/dev/null || printf '0')
    mtime=$(lock_mtime 2>/dev/null || printf '0')
    age=$((now - mtime))
    [ "$age" -gt "$stale_seconds" ] || return 0
    stale_dir="${LOCK_DIR}.stale.${BASHPID:-$$}"
  fi
  if mv "$LOCK_DIR" "$stale_dir" 2>/dev/null; then
    rm -f "$stale_dir/pid" 2>/dev/null || true
    rmdir "$stale_dir" 2>/dev/null || true
  fi
}

acquire_lock() {
  local attempts=0
  mkdir -p "$STATE_DIR"
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    reclaim_stale_lock
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 200 ]; then
      echo "Error: timed out acquiring QA remediation lock: $LOCK_DIR" >&2
      return 1
    fi
    sleep 0.01
  done
  if ! printf '%s\n' "${BASHPID:-$$}" > "$LOCK_DIR/pid"; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
    echo "Error: unable to record QA remediation lock owner: $LOCK_DIR" >&2
    return 1
  fi
  LOCK_HELD=true
  trap release_lock EXIT HUP INT TERM
}

state_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE" 2>/dev/null || true
}

get_stage() {
  local value stage
  value="$(state_value stage)"
  for stage in "${STAGES[@]}"; do
    [ "$value" = "$stage" ] && { printf '%s\n' "$value"; return; }
  done
  printf '%s\n' none
}

get_round() {
  local round
  round="$(state_value round)"
  [[ "$round" =~ ^[0-9]+$ ]] || round=1
  printf '%02d\n' "$((10#$round))"
}

round_started_at_commit() {
  state_value round_started_at_commit
}

source_verification_path() {
  state_value source_verification_path
}

source_fail_count() {
  state_value source_fail_count
}

capture_source_verification_path() {
  bash "$SCRIPT_DIR/resolve-verification-path.sh" authoritative "$PHASE_DIR" 2>/dev/null || true
}

count_source_failures() {
  local verification_path="$1" failed
  [ -r "$verification_path" ] || { printf '0\n'; return; }
  failed=$(sed -n '/^---$/,/^---$/{ /^failed:/{ s/^failed:[[:space:]]*//; p; q; }; }' "$verification_path" | tr -d '[:space:]')
  case "$failed" in
    ''|*[!0-9]*) awk -F'|' '/\|[[:space:]]*FAIL[[:space:]]*\|/ { count++ } END { print count + 0 }' "$verification_path" ;;
    *) printf '%s\n' "$failed" ;;
  esac
}

known_issue_metadata() {
  bash "$SCRIPT_DIR/track-known-issues.sh" status "$PHASE_DIR"
}

input_mode_for() {
  local failures="$1" known_count="$2"
  if [ "$failures" -gt 0 ] && [ "$known_count" -gt 0 ]; then printf 'both\n'
  elif [ "$failures" -gt 0 ]; then printf 'verification\n'
  elif [ "$known_count" -gt 0 ]; then printf 'known-issues\n'
  else printf 'none\n'
  fi
}

write_state() {
  local stage="$1" round="$2" commit="${3:-}" source_path source_failures known_metadata known_count input_mode tmp
  source_path="$(source_verification_path)"
  source_failures="$(source_fail_count)"
  if [ -z "$source_path" ]; then
    source_path="$(capture_source_verification_path)"
    source_failures="$(count_source_failures "$source_path")"
  fi
  source_failures="${source_failures:-0}"
  known_metadata="$(known_issue_metadata)"
  known_count=$(printf '%s\n' "$known_metadata" | awk -F= '$1 == "known_issues_count" { print $2; exit }')
  known_count="${known_count:-0}"
  input_mode="$(input_mode_for "$source_failures" "$known_count")"
  tmp=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
  if printf 'stage=%s\nround=%s\nround_started_at_commit=%s\nsource_verification_path=%s\nsource_fail_count=%s\ninput_mode=%s\n' "$stage" "$round" "$commit" "$source_path" "$source_failures" "$input_mode" > "$tmp"; then
    mv "$tmp" "$STATE_FILE"
  else
    rm -f "$tmp"
    return 1
  fi
}

emit_metadata() {
  local round round_dir source_path source_failures known_metadata known_count input_mode
  round="$(get_round)"
  round_dir="$STATE_DIR/round-$round"
  source_path="$(source_verification_path)"
  source_failures="$(source_fail_count)"
  source_failures="${source_failures:-0}"
  known_metadata="$(known_issue_metadata)"
  known_count=$(printf '%s\n' "$known_metadata" | awk -F= '$1 == "known_issues_count" { print $2; exit }')
  known_count="${known_count:-0}"
  input_mode="$(input_mode_for "$source_failures" "$known_count")"
  printf 'round=%s\n' "$round"
  printf 'round_dir=%s\n' "$round_dir"
  printf 'round_started_at_commit=%s\n' "$(round_started_at_commit)"
  printf 'source_verification_path=%s\nsource_fail_count=%s\n' "$source_path" "$source_failures"
  printf '%s\n' "$known_metadata"
  printf 'input_mode=%s\n' "$input_mode"
  printf 'plan_path=%s/R%s-PLAN.md\nsummary_path=%s/R%s-SUMMARY.md\nverification_path=%s/R%s-VERIFICATION.md\n' "$round_dir" "$round" "$round_dir" "$round" "$round_dir" "$round"
}

emit_driver_metadata() {
  local round round_dir
  round="$(get_round)"
  round_dir="$OUTPUT_PHASE_DIR/remediation/qa/round-$round"
  printf 'round=%s\n' "$round"
  printf 'round_dir=%s\n' "$round_dir"
  printf 'plan_path=%s/R%s-PLAN.md\n' "$round_dir" "$round"
  printf 'summary_path=%s/R%s-SUMMARY.md\n' "$round_dir" "$round"
  printf 'verif_path=%s/R%s-VERIFICATION.md\n' "$round_dir" "$round"
  printf 'uat_path=%s/R%s-UAT.md\n' "$round_dir" "$round"
}

capture_commit() {
  git -C "$PHASE_DIR" rev-parse HEAD 2>/dev/null || true
}

next_stage() {
  case "$(get_stage)" in
    plan) printf 'execute\n' ;;
    execute) printf 'verify\n' ;;
    verify) printf 'done\n' ;;
    done) printf 'done\n' ;;
    *) return 1 ;;
  esac
}

find_config_file() {
  local config_dir="$PHASE_DIR"
  while [ "$config_dir" != / ] && [ ! -f "$config_dir/.lbwc-planning/config.json" ]; do
    config_dir=$(dirname "$config_dir")
  done
  printf '%s/.lbwc-planning/config.json\n' "$config_dir"
}

next_round_decision() {
  local round="$1" config_file
  config_file="$(find_config_file)"
  bash "$SCRIPT_DIR/resolve-uat-remediation-round-limit.sh" --next-round-decision "$config_file" "$round"
}

emit_round_cap() {
  local decision="$1" max
  max=$(printf '%s\n' "$decision" | awk -F= '/^max_rounds=/{print $2; exit}')
  echo "remediation-round: round cap reached (max_remediation_rounds=$max) for $OUTPUT_PHASE_DIR" >&2
  printf '%s\n' "$decision"
}

open_round() {
  local stage round decision next_round cap_reached
  acquire_lock
  stage="$(get_stage)"
  round="$(get_round)"
  if [ "$stage" = plan ] && [ -f "$STATE_FILE" ]; then
    mkdir -p "$STATE_DIR/round-$round"
    printf 'stage=plan\n'
    emit_driver_metadata
    return 0
  fi
  [ -f "$STATE_FILE" ] || round=0
  decision="$(next_round_decision "$round")" || return 1
  next_round=$(printf '%s\n' "$decision" | awk -F= '/^next_round=/{print $2; exit}')
  cap_reached=$(printf '%s\n' "$decision" | awk -F= '/^cap_reached=/{print $2; exit}')
  [ "$cap_reached" != true ] || { emit_round_cap "$decision"; return 3; }
  mkdir -p "$STATE_DIR/round-$next_round"
  write_state plan "$next_round" "$(capture_commit)"
  printf 'stage=plan\n'
  emit_driver_metadata
}

set_requested_stage() {
  local current round anchor
  case "$REQUESTED_STAGE" in
    plan|execute|verify|done) ;;
    *) echo "remediation-round: unknown stage: $REQUESTED_STAGE" >&2; return 1 ;;
  esac
  acquire_lock
  [ -f "$STATE_FILE" ] || { echo "remediation-round: no active round for qa in $OUTPUT_PHASE_DIR" >&2; return 1; }
  current="$(get_stage)"
  case "$current:$REQUESTED_STAGE" in
    plan:execute|execute:verify|verify:done|plan:plan|execute:execute|verify:verify|done:done) ;;
    *) echo "remediation-round: illegal QA stage transition: $current -> $REQUESTED_STAGE" >&2; return 1 ;;
  esac
  round="$(get_round)"
  anchor="$(round_started_at_commit)"
  write_state "$REQUESTED_STAGE" "$round" "$anchor"
  printf 'stage=%s\n' "$REQUESTED_STAGE"
  emit_driver_metadata
}

case "$CMD" in
  get)
    stage="$(get_stage)"
    printf '%s\n' "$stage"
    [ "$stage" = none ] || emit_metadata
    ;;
  init|get-or-init)
    acquire_lock
    stage="$(get_stage)"
    if [ "$stage" = none ]; then
      mkdir -p "$STATE_DIR/round-01"
      write_state plan 01 "$(capture_commit)"
      stage=plan
    fi
    printf '%s\n' "$stage"
    emit_metadata
    ;;
  advance)
    acquire_lock
    stage="$(next_stage)"
    write_state "$stage" "$(get_round)" "$(round_started_at_commit)"
    printf '%s\n' "$stage"
    emit_metadata
    ;;
  needs-round)
    acquire_lock
    round="$(get_round)"
    round=$(printf '%02d' "$((10#$round + 1))")
    mkdir -p "$STATE_DIR/round-$round"
    write_state plan "$round" "$(capture_commit)"
    printf 'plan\n'
    emit_metadata
    ;;
  open)
    open_round
    ;;
  stage)
    set_requested_stage
    ;;
  reset)
    acquire_lock
    rm -f "$STATE_FILE"
    printf 'none\n'
    ;;
  *)
    echo "Error: unknown command: $CMD" >&2
    exit 1
    ;;
esac
