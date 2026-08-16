#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
source "$SCRIPT_DIR/lib/lbwc-control-root.sh"
source "$SCRIPT_DIR/lib/tmux-runtime.sh"

fail() {
  printf 'tmux-watchdog: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: tmux-bus-watchdog.sh --control-root PATH check --orchestrator-id ID --orchestrator-session-id ID --orchestrator-capability TOKEN --stale-after-ms MS --shutdown-timeout-ms MS' >&2
  exit 2
}

pane_exists() {
  tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1
}

persist_shutdown() {
  local agent_id="$1" registry updated
  tmux_runtime_lock_acquire registry 5000 30000 || return 1
  registry=$(tmux_runtime_registry_read) || {
    tmux_runtime_lock_release registry >/dev/null 2>&1 || true
    return 1
  }
  updated=$(jq --arg agent_id "$agent_id" '
    .main.agent_id as $main_id
    | .agents |= map(if .agent_id == $agent_id then .state = "shutdown" | .watchdog_cleanup_pending = false else . end)
    | .routes |= with_entries(.key as $route_id | select($route_id == $main_id or $route_id != $agent_id))
  ' <<<"$registry") || {
    tmux_runtime_lock_release registry >/dev/null 2>&1 || true
    return 1
  }
  tmux_runtime_write_registry_route_bundle "$updated" || {
    tmux_runtime_lock_release registry >/dev/null 2>&1 || true
    return 1
  }
  tmux_runtime_lock_release registry
}

wait_for_pane_exit() {
  local target="$1" deadline="$2"
  while pane_exists "$target"; do
    tmux_runtime_deadline_expired "$deadline" && return 1
    sleep 0.01
  done
}

shutdown_request_exists() {
  local agent_id="$1" path
  path="$(tmux_runtime_inbox "$agent_id")/shutdown_request.json"
  [ -e "$path" ] || return 1
  tmux_runtime_private_file "$path" || return 1
  jq -e --arg agent_id "$agent_id" --arg correlation_id "watchdog-$agent_id" '.type == "shutdown_request" and .to.agent_id == $agent_id and .correlation_id == $correlation_id' "$path" >/dev/null
}

shutdown_stale_agent() {
  local agent_id="$1" target="$2" deadline cleanup_failed=0 shutdown_requested=false registry
  if ! tmux_runtime_lock_acquire "watchdog.$agent_id" 5000 30000; then
    watchdog_failures+=("cannot acquire stale agent cleanup lock: $agent_id")
    return 1
  fi
  registry=$(tmux_runtime_registry_read) || {
    watchdog_failures+=("runtime registry is malformed")
    tmux_runtime_lock_release "watchdog.$agent_id" >/dev/null 2>&1 || true
    return 1
  }
  if ! jq -e --arg agent_id "$agent_id" 'any(.agents[]; .agent_id == $agent_id and .state == "failed" and .watchdog_cleanup_pending == true)' <<<"$registry" >/dev/null; then
    tmux_runtime_lock_release "watchdog.$agent_id" >/dev/null 2>&1 || true
    return 0
  fi
  if shutdown_request_exists "$agent_id"; then
    shutdown_requested=true
  elif bash "$SCRIPT_DIR/tmux-bus.sh" --control-root "$control_root" publish --to "$agent_id" --from-agent-id "$orchestrator_id" --from-session-id "$orchestrator_session_id" --from-role orchestrator --capability "$orchestrator_capability" --type shutdown_request --correlation-id "watchdog-$agent_id" --payload '{"reason":"watchdog stale heartbeat"}' --timeout-ms "$shutdown_timeout_ms" >/dev/null 2>&1; then
    shutdown_requested=true
  else
    watchdog_failures+=("cannot request stale agent shutdown: $agent_id")
    cleanup_failed=1
  fi
  if pane_exists "$target"; then
    deadline=$(tmux_runtime_deadline_after "$shutdown_timeout_ms")
    if [ "$shutdown_requested" = true ]; then
      bash "$SCRIPT_DIR/tmux-bus.sh" --control-root "$control_root" await --from "$agent_id" --agent-id "$orchestrator_id" --session-id "$orchestrator_session_id" --role orchestrator --capability "$orchestrator_capability" --types shutdown_response --timeout-ms "$shutdown_timeout_ms" >/dev/null 2>&1 || true
    fi
    if ! wait_for_pane_exit "$target" "$deadline"; then
      if ! tmux kill-pane -t "$target" >/dev/null 2>&1; then
        watchdog_failures+=("cannot terminate stale agent pane after shutdown timeout: $agent_id")
        cleanup_failed=1
      elif pane_exists "$target"; then
        watchdog_failures+=("stale agent pane remains after forced shutdown: $agent_id")
        cleanup_failed=1
      fi
    fi
  fi
  if [ "$cleanup_failed" -eq 0 ]; then
    if ! persist_shutdown "$agent_id"; then
      watchdog_failures+=("cannot persist stale agent shutdown state: $agent_id")
      cleanup_failed=1
    fi
  fi
  tmux_runtime_lock_release "watchdog.$agent_id" >/dev/null 2>&1 || true
  [ "$cleanup_failed" -eq 0 ]
}

[ "$#" -ge 3 ] || usage
[ "$1" = '--control-root' ] || usage
control_root="$2"
command="$3"
shift 3

orchestrator_id=''
orchestrator_session_id=''
orchestrator_capability=''
stale_after_ms=''
shutdown_timeout_ms=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --orchestrator-id) [ "$#" -ge 2 ] || usage; orchestrator_id="$2"; shift 2 ;;
    --orchestrator-session-id) [ "$#" -ge 2 ] || usage; orchestrator_session_id="$2"; shift 2 ;;
    --orchestrator-capability) [ "$#" -ge 2 ] || usage; orchestrator_capability="$2"; shift 2 ;;
    --stale-after-ms) [ "$#" -ge 2 ] || usage; stale_after_ms="$2"; shift 2 ;;
    --shutdown-timeout-ms) [ "$#" -ge 2 ] || usage; shutdown_timeout_ms="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ "$command" = check ] || usage
for value in "$orchestrator_id" "$orchestrator_session_id" "$orchestrator_capability" "$stale_after_ms" "$shutdown_timeout_ms"; do
  [ -n "$value" ] || usage
done
[[ "$stale_after_ms" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$shutdown_timeout_ms" =~ ^[1-9][0-9]*$ ]] || usage

tmux_runtime_configure_existing "$control_root" >/dev/null 2>&1 || fail 'runtime registry is malformed'
trap tmux_runtime_cleanup_locks EXIT
tmux_runtime_require_bus || fail 'runtime registry is malformed'
tmux_runtime_lock_acquire registry 5000 30000
registry=$(tmux_runtime_registry_read) || fail 'runtime registry is malformed'
tmux_runtime_principal_valid "$registry" "$orchestrator_id" "$orchestrator_session_id" orchestrator "$orchestrator_capability" || fail 'main orchestrator session and capability are required'
now=$(tmux_runtime_now_ms)
dead_ids='[]'
while IFS= read -r agent; do
  [ -n "$agent" ] || continue
  agent_id=$(jq -r '.agent_id' <<<"$agent")
  pane_id=$(jq -r '.tmux_pane_id // empty' <<<"$agent")
  [ -n "$pane_id" ] || continue
  pane_exists "$pane_id" && continue
  dead_ids=$(jq --arg id "$agent_id" '. + [$id]' <<<"$dead_ids")
done < <(jq -c '.agents[] | select(.state != "shutdown" and .state != "failed") | {agent_id,tmux_pane_id}' <<<"$registry")
stale=$(jq -c --argjson now "$now" --argjson threshold "$stale_after_ms" --argjson dead_ids "$dead_ids" '[.agents[] | select(.state != "shutdown" and ((.state == "failed" and .watchdog_cleanup_pending == true) or (.state != "failed" and ((.heartbeat_at_ms == null or (.heartbeat_at_ms + $threshold) <= $now) or (.agent_id as $id | $dead_ids | index($id)))))) | {agent_id, tmux_target, report_failure: (.state != "failed")}]' <<<"$registry")
if [ "$(jq 'length' <<<"$stale")" -eq 0 ]; then
  tmux_runtime_lock_release registry
  jq -n '{state: "healthy", stale_agents: []}'
  exit 0
fi
newly_failed=$(jq -c '[.[] | select(.report_failure)]' <<<"$stale")
if [ "$(jq 'length' <<<"$newly_failed")" -gt 0 ]; then
  updated=$(jq --argjson newly_failed "$newly_failed" --argjson now "$now" '
    ($newly_failed | map(.agent_id)) as $agent_ids
    | .agents |= map(. as $agent | if ($agent_ids | index($agent.agent_id)) then .state = "failed" | .failure_reason = "watchdog_stale_heartbeat" | .watchdog_cleanup_pending = true | .watchdog_failure_reported_at_ms = $now else . end)
  ' <<<"$registry") || fail 'cannot prepare stale agent failure state'
  tmux_runtime_write_registry_route_bundle "$updated" || fail 'cannot persist stale agent failure'
fi
tmux_runtime_lock_release registry

watchdog_failures=()
while IFS= read -r agent; do
  agent_id=$(jq -r '.agent_id' <<<"$agent")
  target=$(jq -r '.tmux_target' <<<"$agent")
  if ! shutdown_stale_agent "$agent_id" "$target"; then
    :
  fi
done < <(jq -c '.[]' <<<"$stale")

if [ "$(jq 'length' <<<"$newly_failed")" -gt 0 ]; then
  error_message="TMUX watchdog marked stale agents failed and requested shutdown: $(jq -r 'map(.agent_id) | join(", ")' <<<"$newly_failed")"
  if ! bash "$SCRIPT_DIR/tmux-bus.sh" --control-root "$control_root" publish --to "$orchestrator_id" --from-agent-id "$orchestrator_id" --from-session-id "$orchestrator_session_id" --from-role orchestrator --capability "$orchestrator_capability" --type error --correlation-id watchdog --payload "$(jq -n --arg message "$error_message" '{message:$message}')" --timeout-ms "$shutdown_timeout_ms" >/dev/null 2>&1; then
    watchdog_failures+=('cannot publish stale agent error envelope')
  fi
  notification=$(jq -n --argjson stale "$newly_failed" '{notification_type: "tmux_watchdog_stale_agents_failed", title: "TMUX watchdog failed stale agents", message: ("The watchdog marked stale TMUX agents as failed: " + ($stale | map(.agent_id) | join(", ")) + ". Shutdown was requested and stale panes will be terminated after the configured timeout.")}')
  notification_path="$control_root/.notification-log.jsonl"
  notification_count=0
  if [ -e "$notification_path" ]; then
    notification_count=$(jq -s 'length' "$notification_path" 2>/dev/null) || notification_count=-1
  fi
  if ! printf '%s\n' "$notification" | LBWC_PLANNING_DIR="$control_root" bash "$SCRIPT_DIR/notification-log.sh" >/dev/null 2>&1; then
    watchdog_failures+=('cannot append stale agent failure notification')
  else
    updated_notification_count=0
    if [ -e "$notification_path" ]; then
      updated_notification_count=$(jq -s 'length' "$notification_path" 2>/dev/null) || updated_notification_count=-1
    fi
    if [ "$notification_count" -lt 0 ] || [ "$updated_notification_count" -ne $((notification_count + 1)) ]; then
      watchdog_failures+=('cannot append stale agent failure notification')
    fi
  fi
fi

for watchdog_failure in "${watchdog_failures[@]}"; do
  printf 'tmux-watchdog: %s\n' "$watchdog_failure" >&2
done
jq -n --argjson stale "$stale" '{state: "stale_agents_shutdown", stale_agents: ($stale | map(.agent_id))}'
exit 1
