#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: remediation-round.sh <open|stage|current> <phase-dir> <qa|uat> [stage]" >&2
  exit 1
}

[ $# -ge 3 ] || usage
ACTION="$1"
PHASE_DIR="${2%/}"
KIND="$3"
case "$KIND" in qa|uat) ;; *) usage ;; esac
[ -d "$PHASE_DIR" ] || { echo "remediation-round: no phase dir: $PHASE_DIR" >&2; exit 1; }

STATE_DIR="$PHASE_DIR/remediation/$KIND"
STATE_FILE="$STATE_DIR/.${KIND}-remediation-stage"

if [ "$KIND" = "qa" ]; then
  case "$ACTION" in
    open)
      exec env QA_REMEDIATION_OUTPUT_PHASE_DIR="$PHASE_DIR" bash "$SCRIPT_DIR/qa-remediation-state.sh" open "$PHASE_DIR"
      ;;
    stage)
      exec env QA_REMEDIATION_OUTPUT_PHASE_DIR="$PHASE_DIR" bash "$SCRIPT_DIR/qa-remediation-state.sh" stage "$PHASE_DIR" "${4:-}"
      ;;
  esac
fi

state_get() {
  grep "^$1=" "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true
}

emit_meta() {
  local round="$1"
  local round_dir="$PHASE_DIR/remediation/$KIND/round-$round"
  printf 'round=%s\n' "$round"
  printf 'round_dir=%s\n' "$round_dir"
  printf 'plan_path=%s\n' "$round_dir/R${round}-PLAN.md"
  printf 'summary_path=%s\n' "$round_dir/R${round}-SUMMARY.md"
  printf 'verif_path=%s\n' "$round_dir/R${round}-VERIFICATION.md"
  printf 'uat_path=%s\n' "$round_dir/R${round}-UAT.md"
}

write_state() {
  local stage="$1" round="$2"
  mkdir -p "$STATE_DIR"
  printf 'stage=%s\nround=%s\nlayout=round-dir\n' "$stage" "$round" > "$STATE_FILE"
}

case "$ACTION" in
  current)
    [ -f "$STATE_FILE" ] || { echo "remediation-round: no active round for $KIND in $PHASE_DIR" >&2; exit 1; }
    ROUND=$(state_get round)
    ROUND="${ROUND:-01}"
    ROUND=$(printf '%02d' "$((10#$ROUND))")
    printf 'stage=%s\n' "$(state_get stage)"
    emit_meta "$ROUND"
    ;;
  stage)
    NEW_STAGE="${4:?stage action requires a stage word}"
    case "$NEW_STAGE" in plan|execute|verify|done) ;; *)
      echo "remediation-round: unknown stage: $NEW_STAGE" >&2
      exit 1
      ;;
    esac
    [ -f "$STATE_FILE" ] || { echo "remediation-round: no active round for $KIND in $PHASE_DIR" >&2; exit 1; }
    ROUND=$(state_get round)
    ROUND="${ROUND:-01}"
    ROUND=$(printf '%02d' "$((10#$ROUND))")
    write_state "$NEW_STAGE" "$ROUND"
    printf 'stage=%s\n' "$NEW_STAGE"
    emit_meta "$ROUND"
    ;;
  open)
    CONFIG="$PHASE_DIR"
    while [ "$CONFIG" != "/" ] && [ ! -f "$CONFIG/.lbwc-planning/config.json" ]; do
      CONFIG=$(dirname "$CONFIG")
    done
    CONFIG_FILE="$CONFIG/.lbwc-planning/config.json"
    if [ -f "$STATE_FILE" ]; then
      CURRENT_ROUND=$(state_get round)
      CURRENT_ROUND="${CURRENT_ROUND:-01}"
      CURRENT_STAGE=$(state_get stage)
      CURRENT_STAGE="${CURRENT_STAGE:-plan}"
    else
      CURRENT_ROUND="0"
      CURRENT_STAGE="none"
    fi
    if [ "$CURRENT_STAGE" = "plan" ] && [ -f "$STATE_FILE" ]; then
      NEXT_ROUND="$CURRENT_ROUND"
    else
      DECISION=$(bash "$SCRIPT_DIR/resolve-uat-remediation-round-limit.sh" --next-round-decision "$CONFIG_FILE" "$CURRENT_ROUND")
      NEXT_ROUND=$(printf '%s\n' "$DECISION" | grep '^next_round=' | cut -d= -f2)
      CAP_REACHED=$(printf '%s\n' "$DECISION" | grep '^cap_reached=' | cut -d= -f2)
      if [ "$CAP_REACHED" = "true" ]; then
        MAX=$(printf '%s\n' "$DECISION" | grep '^max_rounds=' | cut -d= -f2)
        echo "remediation-round: round cap reached (max_remediation_rounds=$MAX) for $PHASE_DIR" >&2
        printf '%s\n' "$DECISION"
        exit 3
      fi
    fi
    ROUND_DIR="$PHASE_DIR/remediation/$KIND/round-$NEXT_ROUND"
    mkdir -p "$ROUND_DIR"
    write_state "plan" "$NEXT_ROUND"
    printf 'stage=plan\n'
    emit_meta "$NEXT_ROUND"
    ;;
  *) usage ;;
esac
