#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
CANONICAL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

TMUX_BIND_JSON=""

bind_tmux_bootstrap() {
  local agent_id contract_id capability control_root actual_session credential
  [ -z "${LBWC_TMUX_AGENT:-}" ] || [ "${LBWC_TMUX_AGENT}" = '1' ] || { echo 'LBWC: SessionStart tmux agent mode is invalid' >&2; return 1; }
  [ "${LBWC_TMUX_AGENT:-}" = '1' ] || return 0
  agent_id="${LBWC_TMUX_AGENT_ID:-}"
  contract_id="${LBWC_TMUX_CONTRACT_ID:-}"
  control_root="${LBWC_TMUX_CONTROL_ROOT:-}"
  actual_session="${CLAUDE_SESSION_ID:-}"
  for value in "$agent_id" "$contract_id" "$control_root"; do
    [ -n "$value" ] || { echo 'LBWC: SessionStart tmux bind is missing' >&2; return 1; }
  done
  [ -n "$actual_session" ] || { echo 'LBWC: SessionStart cannot bind tmux agent without CLAUDE_SESSION_ID' >&2; return 1; }
  [[ "$actual_session" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'LBWC: SessionStart received an invalid Claude session ID' >&2; return 1; }
  [[ "$agent_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$contract_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'LBWC: SessionStart tmux bind is malformed' >&2; return 1; }
  source "$CANONICAL_ROOT/scripts/lib/lbwc-control-root.sh"
  control_root=$(lbwc_control_root_validate "$control_root" 0) || { echo 'LBWC: SessionStart tmux bind control root is invalid' >&2; return 1; }
  source "$CANONICAL_ROOT/scripts/lib/tmux-runtime.sh"
  tmux_runtime_configure_existing "$control_root" || { echo 'LBWC: SessionStart tmux runtime is unavailable' >&2; return 1; }
  credential=$(tmux_runtime_credential_read "$agent_id") || { echo 'LBWC: SessionStart tmux bind failed' >&2; return 1; }
  capability=$(jq -r '.capability // empty' <<<"$credential")
  jq -e --arg agent_id "$agent_id" --arg contract_id "$contract_id" --arg capability "$capability" '.agent_id == $agent_id and .contract_id == $contract_id and .capability == $capability' <<<"$credential" >/dev/null 2>&1 || { echo 'LBWC: SessionStart tmux bind is malformed' >&2; return 1; }
  [[ "$capability" =~ ^[0-9a-f]{32}$ ]] || { echo 'LBWC: SessionStart tmux bind is malformed' >&2; return 1; }
  bash "$CANONICAL_ROOT/scripts/tmux-bus.sh" --control-root "$control_root" bind --agent-id "$agent_id" --session-id "$actual_session" --capability "$capability" --contract-id "$contract_id" || { echo 'LBWC: SessionStart tmux bind failed' >&2; return 1; }
  tmux_runtime_credential_delete "$agent_id" || { echo 'LBWC: SessionStart cannot consume the bound tmux credential' >&2; return 1; }
  bash "$CANONICAL_ROOT/scripts/tmux-bus.sh" --control-root "$control_root" heartbeat --agent-id "$agent_id" --session-id "$actual_session" --capability "$capability" --state running >/dev/null || { echo 'LBWC: SessionStart tmux heartbeat failed' >&2; return 1; }
  TMUX_BIND_JSON=$(jq -cn --arg agent_id "$agent_id" --arg session_id "$actual_session" --arg control_root "$control_root" --arg capability "$capability" '{agent_id:$agent_id,session_id:$session_id,control_root:$control_root,capability:$capability,role:"agent"}')
  capability=''
}

if [ -f "$CANONICAL_ROOT/scripts/hook-wrapper.sh" ] && \
  [ -f "$CANONICAL_ROOT/scripts/ensure-plugin-root-link.sh" ] && \
  ! bash "$CANONICAL_ROOT/scripts/ensure-plugin-root-link.sh" \
    "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}" "$CANONICAL_ROOT" >/dev/null 2>&1; then
  echo "LBWC: SessionStart plugin root link bootstrap failed" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"lbwc: jq not found. Install jq (brew install jq / apt install jq) -- quality gates are degraded until then."}}'
  exit 0
fi

bind_tmux_bootstrap || exit 1

pd_field() {
  printf '%s\n' "$PHASE_OUT" | grep -m1 "^$1=" | sed "s/^[^=]*=//"
}

PHASE_OUT=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null)
PLANNING_EXISTS=$(pd_field planning_dir_exists)
PROJECT_EXISTS=$(pd_field project_exists)
NEXT_PHASE=$(pd_field next_phase)
NEXT_PHASE_STATE=$(pd_field next_phase_state)
PHASE_COUNT=$(pd_field phase_count)
PHASE_DETECT_ERROR=$(pd_field phase_detect_error)
PHASE_DETECT_REASON=$(pd_field phase_detect_reason)

MAP_TOOLS_ROUTE=""
if [ -x "$SCRIPT_DIR/probe-map-tools.sh" ]; then
  MAP_TOOLS_RAW=$(bash "$SCRIPT_DIR/probe-map-tools.sh" 2>/dev/null) || MAP_TOOLS_RAW=""
  [ -n "$MAP_TOOLS_RAW" ] && MAP_TOOLS_ROUTE=$(printf '%s' "$MAP_TOOLS_RAW" | jq -r '.hookSpecificOutput.additionalContext | fromjson? | .recommended_route // empty' 2>/dev/null)
fi

MAP_STALE_CTX=""
if [ -x "$SCRIPT_DIR/map-staleness.sh" ]; then
  MAP_STALE_CTX=$(bash "$SCRIPT_DIR/map-staleness.sh" 2>/dev/null) || MAP_STALE_CTX=""
fi

TEMP_RUN_CLEANUP=""
if [ -x "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$PROJECT_ROOT" ]; then
    TEMP_RUN_CLEANUP=$(bash "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" cleanup --project-root "$PROJECT_ROOT" 2>/dev/null || true)
  fi
fi

SWEPT_COUNT=0
MANIFEST_FILE="$PLANNING_DIR/.agent-manifest.json"
count_expired() {
  [ -f "$MANIFEST_FILE" ] || { echo 0; return; }
  jq -r '[.agents[]? | select(.state == "expired")] | length' "$MANIFEST_FILE" 2>/dev/null || echo 0
}
BEFORE_EXPIRED=$(count_expired)
LIFECYCLE_OUT=$(bash "$SCRIPT_DIR/agent-lifecycle.sh" sweep 2>&1)
LIFECYCLE_STATUS=$?
AGENT_MANIFEST_STATUS=$(printf '%s\n' "$LIFECYCLE_OUT" | grep -m1 '^agent_manifest_status=' | sed 's/^[^=]*=//')
AFTER_EXPIRED=$(count_expired)
[ "${BEFORE_EXPIRED:-0}" -ge 0 ] 2>/dev/null || BEFORE_EXPIRED=0
[ "${AFTER_EXPIRED:-0}" -ge 0 ] 2>/dev/null || AFTER_EXPIRED=0
SWEPT_COUNT=$((AFTER_EXPIRED - BEFORE_EXPIRED))
[ "$SWEPT_COUNT" -lt 0 ] && SWEPT_COUNT=0

if [ "${PHASE_DETECT_ERROR:-}" = "true" ]; then
  CTX="lbwc: phase status unavailable (${PHASE_DETECT_REASON:-unknown})."
elif [ "${PLANNING_EXISTS:-false}" != "true" ]; then
  CTX="lbwc: no ${PLANNING_DIR}/ directory found. Run project init to set up planning."
elif [ "${PROJECT_EXISTS:-false}" != "true" ]; then
  CTX="lbwc: planning dir exists but PROJECT.md is not filled in yet."
else
  ARTIFACT="unknown"
  NEXT_CMD=""
  case "${NEXT_PHASE_STATE:-unknown}" in
    needs_discussion)
      ARTIFACT="CONTEXT.md"; NEXT_CMD="/discuss ${NEXT_PHASE:-}" ;;
    needs_plan_and_execute)
      ARTIFACT="PLAN.md"; NEXT_CMD="/plan ${NEXT_PHASE:-}" ;;
    needs_execute)
      ARTIFACT="SUMMARY.md"; NEXT_CMD="/build ${NEXT_PHASE:-}" ;;
    needs_verification|needs_qa_remediation|needs_reverification)
      ARTIFACT="VERIFICATION.md"; NEXT_CMD="/qa ${NEXT_PHASE:-}" ;;
    needs_uat_remediation)
      ARTIFACT="UAT.md"; NEXT_CMD="/uat ${NEXT_PHASE:-}" ;;
    all_done)
      ARTIFACT="none"; NEXT_CMD="/plan (next phase)" ;;
    no_phases)
      ARTIFACT="ROADMAP.md phase"; NEXT_CMD="" ;;
  esac

  if [ -n "$NEXT_CMD" ]; then
    CTX="lbwc phase ${NEXT_PHASE:-none}/${PHASE_COUNT:-0}: missing ${ARTIFACT}. Next: ${NEXT_CMD}"
  else
    CTX="lbwc phase ${NEXT_PHASE:-none}/${PHASE_COUNT:-0}, state: ${NEXT_PHASE_STATE:-unknown}."
  fi
fi

[ -n "${TMUX_BIND_JSON:-}" ] && CTX="$CTX lbwc tmux bind: ${TMUX_BIND_JSON}."
[ -n "$MAP_TOOLS_ROUTE" ] && CTX="$CTX Map tools route: ${MAP_TOOLS_ROUTE}."
[ -n "$MAP_STALE_CTX" ] && CTX="$CTX ${MAP_STALE_CTX}"
[ "$SWEPT_COUNT" -gt 0 ] && CTX="$CTX Swept ${SWEPT_COUNT} stale agent(s) from the manifest."
[ "$LIFECYCLE_STATUS" -ne 0 ] && [ -n "$AGENT_MANIFEST_STATUS" ] && CTX="$CTX lbwc: agent manifest status ${AGENT_MANIFEST_STATUS}."
[ -n "$TEMP_RUN_CLEANUP" ] && CTX="$CTX Temporary agent run cleanup inspected retained state."

jq -n --arg ctx "$CTX" '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
exit 0
