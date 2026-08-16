#!/bin/bash
set -u

lifecycle_manifest_error() {
  printf 'agent_manifest_status=%s\n' "$1"
  exit 1
}

command -v jq >/dev/null 2>&1 || lifecycle_manifest_error unavailable
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$SCRIPT_DIR/lib/agent-manifest.sh" ] || lifecycle_manifest_error unavailable
. "$SCRIPT_DIR/lib/agent-manifest.sh" || lifecycle_manifest_error unavailable
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" || lifecycle_manifest_error unavailable

PLANNING_DIR=$(lbwc_resolve_control_root "${LBWC_CONTROL_ROOT:-}" "" "$PWD" 2>/dev/null || true)
[ -n "$PLANNING_DIR" ] || PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
IDLE_WAIT_SECONDS=120
COMMAND="${1:-}"
case "$COMMAND" in
  touch|check|idle|sweep|tmux-session-start) ;;
  *) exit 0 ;;
esac

lifecycle_now_epoch() {
  local value="${LBWC_LIFECYCLE_NOW:-}"
  case "$value" in
    ''|*[!0-9]*) date +%s 2>/dev/null || printf '%s\n' 0 ;;
    *) printf '%s\n' "$value" ;;
  esac
}

lifecycle_epoch_iso() {
  local epoch="$1" result=""
  if [ "$(uname)" = "Darwin" ]; then
    result=$(date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  else
    result=$(date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  fi
  [ -n "$result" ] && printf '%s\n' "$result"
}

lifecycle_timestamp_epoch() {
  local value="$1" result=""
  case "$value" in
    ''|*[!0-9]*) ;;
    *) printf '%s\n' "$value"; return 0 ;;
  esac
  if [ "$(uname)" = "Darwin" ]; then
    result=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null || true)
  fi
  [ -n "$result" ] || result=$(date -u -d "$value" +%s 2>/dev/null || true)
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

lifecycle_manifest_failure_status() {
  local manifest_path
  manifest_path=$(agent_manifest_path "$PLANNING_DIR" 2>/dev/null) || {
    printf 'unavailable\n'
    return
  }
  if [ -f "$manifest_path" ] && ! agent_manifest_read "$PLANNING_DIR" >/dev/null 2>&1; then
    printf 'malformed\n'
  else
    printf 'unavailable\n'
  fi
}

lifecycle_manifest_failure() {
  lifecycle_manifest_error "$(lifecycle_manifest_failure_status)"
}

tmux_lifecycle_error() {
  printf 'tmux_lifecycle_status=%s\n' "$1"
  return 1
}

tmux_session_start() {
  local control_root registry agent_id session_id updated now
  [ -f "$SCRIPT_DIR/lib/tmux-runtime.sh" ] || { tmux_lifecycle_error unavailable; return 1; }
  . "$SCRIPT_DIR/lib/tmux-runtime.sh" || { tmux_lifecycle_error unavailable; return 1; }
  control_root="${LBWC_CONTROL_ROOT:-$PLANNING_DIR}"
  control_root=$(lbwc_control_root_canonical_path "$control_root" 2>/dev/null) || { tmux_lifecycle_error malformed; return 1; }
  tmux_runtime_configure_existing "$control_root" 2>/dev/null || { tmux_lifecycle_error malformed; return 1; }
  registry=$(tmux_runtime_registry_read 2>/dev/null) || { tmux_lifecycle_error malformed; return 1; }
  agent_id="${LBWC_TMUX_AGENT_ID:-}"
  session_id="${CLAUDE_SESSION_ID:-}"
  [ -n "$agent_id" ] && [ -n "$session_id" ] || { tmux_lifecycle_error malformed; return 1; }
  jq -e --arg agent_id "$agent_id" --arg session_id "$session_id" 'any(.agents[]; .agent_id == $agent_id and .claude_session_id == $session_id and .state != "shutdown")' <<<"$registry" >/dev/null 2>&1 || { tmux_lifecycle_error malformed; return 1; }
  now=$(tmux_runtime_now_ms)
  tmux_runtime_lock_acquire registry 5000 30000 || { tmux_lifecycle_error unavailable; return 1; }
  registry=$(tmux_runtime_registry_read) || { tmux_runtime_lock_release registry >/dev/null 2>&1 || true; tmux_lifecycle_error malformed; return 1; }
  updated=$(jq --arg id "$agent_id" --argjson now "$now" '.agents |= map(if .agent_id == $id then .state = "running" | .heartbeat_at_ms = $now else . end)' <<<"$registry") || { tmux_runtime_lock_release registry >/dev/null 2>&1 || true; tmux_lifecycle_error malformed; return 1; }
  tmux_runtime_write_registry_route_bundle "$updated" || { tmux_runtime_lock_release registry >/dev/null 2>&1 || true; tmux_lifecycle_error unavailable; return 1; }
  tmux_runtime_lock_release registry
  printf 'tmux_lifecycle_status=running\n'
}

extract_known_agent_name() {
  local manifest="$1" candidate
  while IFS= read -r candidate; do
    agent_manifest_safe_name "$candidate" || continue
    case "$candidate" in lbwc-*) ;; *) continue ;; esac
    if jq -e --arg name "$candidate" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(printf '%s' "$INPUT" | jq -r '[
    .teammate_name, .agent_type, .agentType, .subagent_type, .subagentType,
    .agent_id, .agentId,
    .tool_input.teammate_name, .tool_input.agent_type, .tool_input.agentType,
    .tool_input.subagent_type, .tool_input.subagentType,
    .tool_input.agent_id, .tool_input.agentId
  ] | .[] | select(type == "string" and length > 0)' 2>/dev/null)
  return 1
}

start_manifest_entry() {
  local manifest="$1" name="$2" now="$3"
  jq -e --arg name "$name" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1 || return 2
  jq -c --arg name "$name" --arg now "$now" '
    .agents[$name].state = "running"
    | .agents[$name].started_at = $now
    | .agents[$name].last_activity_at = $now
    | del(.agents[$name].idle_observed_at, .agents[$name].idle_observation_token, .agents[$name].idle_observed_by)
  ' <<< "$manifest" 2>/dev/null
}

stop_manifest_entry() {
  local manifest="$1" name="$2" now="$3"
  jq -e --arg name "$name" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1 || return 2
  jq -c --arg name "$name" --arg now "$now" '
    .agents[$name].state = "used"
    | .agents[$name].last_activity_at = $now
    | .agents[$name].stopped_at = $now
  ' <<< "$manifest" 2>/dev/null
}

touch_manifest_locked() {
  local action="$1" name="$2" now_iso="$3" manifest updated result
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  if [ "$action" = "stop" ]; then
    updated=$(stop_manifest_entry "$manifest" "$name" "$now_iso")
    result=$?
  else
    updated=$(start_manifest_entry "$manifest" "$name" "$now_iso")
    result=$?
  fi
  [ "$result" -eq 0 ] || return "$result"
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || return 1
}

touch_agent() {
  local action="${1:-start}" name now_iso result manifest event expected_event
  INPUT=$(cat 2>/dev/null) || INPUT=""
  [ -n "$INPUT" ] || exit 0
  event=$(jq -r '.hook_event_name // empty' <<< "$INPUT" 2>/dev/null) || exit 0
  case "$action" in
    start) expected_event=SubagentStart ;;
    stop) expected_event=SubagentStop ;;
    *) exit 0 ;;
  esac
  [ "$event" = "$expected_event" ] || exit 0
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || lifecycle_manifest_failure
  name=$(extract_known_agent_name "$manifest") || exit 0
  now_iso=$(lifecycle_epoch_iso "$(lifecycle_now_epoch)") || exit 0
  [ -n "$now_iso" ] || exit 0
  agent_manifest_with_lock "$PLANNING_DIR" touch_manifest_locked "$action" "$name" "$now_iso"
  result=$?
  [ "$result" -eq 0 ] && exit 0
  [ "$result" -eq 2 ] && exit 0
  lifecycle_manifest_failure
  exit 0
}

lifecycle_contract_is_valid() {
  local entry="$1" contract_path contract root expected_root contract_id role task schema_version capabilities
  jq -e '.contract_enabled == true' <<< "$entry" >/dev/null 2>&1 || return 1
  contract_path=$(jq -r '.contract_path // empty' <<< "$entry" 2>/dev/null) || return 1
  [ -n "$contract_path" ] && [ -f "$contract_path" ] && [ ! -L "$contract_path" ] || return 1
  contract_path=$(cd "$(dirname "$contract_path")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$contract_path")") || return 1
  root=$(cd "$PLANNING_DIR" 2>/dev/null && pwd -P) || return 1
  case "$(basename "$root")" in
    .lbwc-planning) case "$contract_path" in "$root/.contracts/"*) ;; *) return 1 ;; esac ;;
    *) case "$contract_path" in "$root/contracts/"*) ;; *) return 1 ;; esac ;;
  esac
  expected_root=$(lbwc_control_root_project_root "$root") || return 1
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$contract_path" "$expected_root" 2>/dev/null) || return 1
  contract_id=$(jq -r '.contract_id // .id // empty' <<< "$contract")
  [ -n "$contract_id" ] && [ "$contract_id" = "$(jq -r '.contract_id // empty' <<< "$entry")" ] || return 1
  [ "$(jq -r '.contract_digest // empty' <<< "$contract")" = "$(jq -r '.contract_digest // empty' <<< "$entry")" ] || return 1
  role=$(jq -r '.role // empty' <<< "$entry")
  jq -e --arg role "$role" '(.roles | type == "array") and (.roles | index($role) != null)' <<< "$contract" >/dev/null 2>&1 || return 1
  task=$(jq -r '.task_identity // .task_id // .contract_id // empty' <<< "$contract")
  [ -n "$task" ] && [ "$task" = "$(jq -r '.task_identity // empty' <<< "$entry")" ] || return 1
  jq -e --arg role "$role" --argjson allowances "$(jq -c '.write_allowances // []' <<< "$entry")" '.allowances_by_role[$role] == $allowances' <<< "$contract" >/dev/null 2>&1 || return 1
  schema_version=$(jq -r '.schema_version' <<< "$contract")
  if [ "$schema_version" = "3" ]; then
    capabilities=$(jq -c '.capabilities // []' <<< "$entry")
    jq -e --arg role "$role" --arg runtime "$(jq -r '.runtime_kind' <<< "$entry")" --arg policy "$(jq -r '.communication_policy' <<< "$entry")" --argjson capabilities "$capabilities" '
      .runtime_kind == $runtime
      and .communication_policy == $policy
      and .capabilities_by_role[$role] == $capabilities
    ' <<< "$contract" >/dev/null 2>&1 || return 1
  fi
}

mark_idle_locked() {
  local name="$1" now_iso="$2" token="$3" manifest entry updated
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  entry=$(jq -ce --arg name "$name" '.agents[$name] // empty' <<< "$manifest" 2>/dev/null) || return 2
  jq -e '.state == "running"' <<< "$entry" >/dev/null 2>&1 || return 2
  lifecycle_contract_is_valid "$entry" || return 3
  updated=$(jq -c --arg name "$name" --arg now "$now_iso" --arg token "$token" '
    .agents[$name].idle_observed_at = $now
    | .agents[$name].idle_observation_token = $token
    | .agents[$name].idle_observed_by = "TeammateIdle"
  ' <<< "$manifest" 2>/dev/null) || return 1
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || return 1
}

expire_if_still_idle_locked() {
  local name="$1" now_iso="$2" token="$3" manifest entry updated
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  entry=$(jq -ce --arg name "$name" '.agents[$name] // empty' <<< "$manifest" 2>/dev/null) || return 2
  jq -e --arg token "$token" '.state == "running" and .idle_observed_by == "TeammateIdle" and .idle_observation_token == $token' <<< "$entry" >/dev/null 2>&1 || return 2
  lifecycle_contract_is_valid "$entry" || return 3
  updated=$(jq -c --arg name "$name" --arg now "$now_iso" '
    .agents[$name].state = "expired"
    | .agents[$name].expired_at = $now
  ' <<< "$manifest" 2>/dev/null) || return 1
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || return 1
}

idle_agent() {
  local manifest name now now_iso token result final_now_iso
  INPUT=$(cat 2>/dev/null) || INPUT=""
  [ -n "$INPUT" ] || exit 0
  [ "$(jq -r '.hook_event_name // empty' <<< "$INPUT" 2>/dev/null)" = "TeammateIdle" ] || exit 0
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || lifecycle_manifest_failure
  name=$(extract_known_agent_name "$manifest") || exit 0
  now=$(lifecycle_now_epoch)
  now_iso=$(lifecycle_epoch_iso "$now") || exit 0
  token="${now}-${BASHPID:-$$}"
  agent_manifest_with_lock "$PLANNING_DIR" mark_idle_locked "$name" "$now_iso" "$token"
  result=$?
  [ "$result" -eq 2 ] && exit 0
  [ "$result" -eq 3 ] && { printf 'agent_contract_status=invalid\n' >&2; exit 1; }
  [ "$result" -eq 0 ] || lifecycle_manifest_failure

  sleep "$IDLE_WAIT_SECONDS"

  final_now_iso=$(lifecycle_epoch_iso "$(lifecycle_now_epoch)") || exit 0
  agent_manifest_with_lock "$PLANNING_DIR" expire_if_still_idle_locked "$name" "$final_now_iso" "$token"
  result=$?
  [ "$result" -eq 2 ] && exit 0
  [ "$result" -eq 3 ] && { printf 'agent_contract_status=invalid\n' >&2; exit 1; }
  [ "$result" -eq 0 ] || lifecycle_manifest_failure
  jq -cn --arg name "$name" --arg seconds "$IDLE_WAIT_SECONDS" '{continue:false,stopReason:("LBWC stopped teammate " + $name + " after " + $seconds + " seconds of shell-observed inactivity.")}'
  exit 0
}

sweep_agents_locked() {
  local now="$1" now_iso="$2" names name entry state threshold ref_time ref_epoch age updated
  SWEEP_MANIFEST=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  names=$(jq -r '.agents | keys[]' <<< "$SWEEP_MANIFEST" 2>/dev/null) || return 1
  SWEEP_CHANGED=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    entry=$(jq -c --arg name "$name" '.agents[$name] // {}' <<< "$SWEEP_MANIFEST" 2>/dev/null) || continue
    state=$(jq -r '.state // ""' <<< "$entry" 2>/dev/null) || state=""
    case "$state" in
      registered) threshold=3600; ref_time=$(jq -r '.created_at // ""' <<< "$entry" 2>/dev/null) ;;
      running) threshold=86400; ref_time=$(jq -r '.started_at // .created_at // ""' <<< "$entry" 2>/dev/null) ;;
      *) continue ;;
    esac
    ref_epoch=$(lifecycle_timestamp_epoch "$ref_time" 2>/dev/null) || continue
    age=$((now - ref_epoch))
    [ "$age" -gt "$threshold" ] || continue
    updated=$(jq -c --arg name "$name" --arg now "$now_iso" '
      .agents[$name].state = "expired"
      | .agents[$name].expired_at = $now
    ' <<< "$SWEEP_MANIFEST" 2>/dev/null) || continue
    SWEEP_MANIFEST="$updated"
    SWEEP_CHANGED=1
  done <<< "$names"
  if [ "$SWEEP_CHANGED" -eq 1 ]; then
    agent_manifest_write "$PLANNING_DIR" "$SWEEP_MANIFEST" >/dev/null 2>&1 || return 1
  fi
}

sweep_agents() {
  local now now_iso
  now=$(lifecycle_now_epoch)
  now_iso=$(lifecycle_epoch_iso "$now") || exit 0
  [ -n "$now_iso" ] || exit 0
  agent_manifest_with_lock "$PLANNING_DIR" sweep_agents_locked "$now" "$now_iso" || lifecycle_manifest_failure
  exit 0
}

case "$COMMAND" in
  touch) touch_agent "${2:-start}" ;;
  check|idle) idle_agent ;;
  sweep) sweep_agents ;;
  tmux-session-start) tmux_session_start || exit $? ;;
esac
exit 0
