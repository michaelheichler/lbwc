#!/usr/bin/env bash
set -euo pipefail
set -E
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/lbwc-control-root.sh"
source "$SCRIPT_DIR/lib/tmux-runtime.sh"

usage() {
  printf '%s\n' 'Usage: tmux-doctor.sh --project-root PATH --control-root PATH' >&2
  exit 2
}

emit() {
  jq -n --arg status "$1" --arg detail "$2" '{status: $status, detail: $detail}'
  exit 0
}

require_option_value() {
  [ "$#" -ge 2 ] || usage
}

pane_exists() {
  tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1
}

routing_table_valid() {
  local registry="$1" path="$2"
  tmux_runtime_private_file "$path" >/dev/null 2>&1 || return 1
  jq -e --argjson registry "$registry" '
    def token: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");
    def target: . == null or (type == "string" and test("^[A-Za-z0-9][A-Za-z0-9:._-]*$"));
    . as $table | .schema_version == 1 and (.routes | type == "object")
    and ((.routes | keys | sort) == ($registry.routes | keys | sort))
    and all(.routes | to_entries[]; .key | token)
    and all(.routes | to_entries[]; . as $route | ($route.value | type == "object" and .agent_id == $route.key and (.inbox == $route.key) and ((.session_id == null) or (.session_id | token)) and ((.contract_id == null) or (.contract_id | token)) and (.tmux_target | target)))
    and (.routes[($registry.main.agent_id)].session_id == $registry.main.session_id)
    and (.routes[($registry.main.agent_id)].contract_id == null)
    and all($registry.agents[] | select(.state != "shutdown"); . as $agent | ($table.routes[$agent.agent_id].session_id == $agent.claude_session_id and $table.routes[$agent.agent_id].contract_id == $agent.contract_id))
  ' "$path" >/dev/null 2>&1
}

project_root=""
requested_control_root=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      require_option_value "$@"
      project_root="$2"
      shift 2
      ;;
    --control-root)
      require_option_value "$@"
      requested_control_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[ -n "$project_root" ] || usage
[ -n "$requested_control_root" ] || usage
[ -d "$project_root" ] || usage
command -v jq >/dev/null 2>&1 || usage

project_root=$(cd "$project_root" && pwd -P)

if [ ! -d "$requested_control_root" ]; then
  emit PASS 'no tmux runtime'
fi

control_root=$(lbwc_control_root_validate "$requested_control_root" 0 2>/dev/null) || emit PASS 'no tmux runtime'
resolved_project_root=$(lbwc_control_root_project_root "$control_root" 2>/dev/null) || emit PASS 'no tmux runtime'
[ "$resolved_project_root" = "$project_root" ] || emit PASS 'no tmux runtime'

registry_path="$control_root/.runtime/tmux-bus/registry.json"
if [ ! -e "$registry_path" ]; then
  emit PASS 'no tmux runtime'
fi

tmux_runtime_configure "$control_root" >/dev/null 2>&1 || emit FAIL 'malformed registry'
registry_path=$(tmux_runtime_path registry.json)
routing_path=$(tmux_runtime_path routing-table.json)

if ! tmux_runtime_registry_valid "$registry_path"; then
  emit FAIL 'malformed registry'
fi

registry=$(tmux_runtime_helper read-json --root "$TMUX_RUNTIME_BUS_ROOT" --source registry.json) || emit FAIL 'malformed registry'

findings=()
worst=PASS
routing_ok=false

bump_warn() {
  findings+=("$1")
  [ "$worst" = FAIL ] || worst=WARN
}

if routing_table_valid "$registry" "$routing_path"; then
  routing_ok=true
else
  bump_warn 'malformed route'
fi

session=$(jq -r '.tmux.session // empty' <<<"$registry")
session_present=false
expected_panes=$(jq '
  ([.tmux.orchestrator_target | select(. != null)] | length)
  + ([.agents[] | select(.state != "shutdown" and .tmux_pane_id != null)] | length)
' <<<"$registry")
present_panes=0

if [ "$routing_ok" = true ] && [ -n "$session" ]; then
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session" >/dev/null 2>&1; then
    session_present=true
  else
    bump_warn "missing tmux session: $session"
  fi
  if [ "$session_present" = true ]; then
    orchestrator_target=$(jq -r '.tmux.orchestrator_target // empty' <<<"$registry")
    if [ -n "$orchestrator_target" ]; then
      if pane_exists "$orchestrator_target"; then
        present_panes=$((present_panes + 1))
      else
        bump_warn "missing pane: $orchestrator_target"
      fi
    fi
    while IFS= read -r pane_id; do
      [ -n "$pane_id" ] || continue
      if pane_exists "$pane_id"; then
        present_panes=$((present_panes + 1))
      else
        bump_warn "missing pane: $pane_id"
      fi
    done < <(jq -r '.agents[] | select(.state != "shutdown" and .tmux_pane_id != null) | .tmux_pane_id' <<<"$registry")
  fi
fi

config_path="$control_root/config.json"
threshold_seconds=$(jq -r '.tmux_execution.heartbeat_stale_seconds // 120' "$config_path" 2>/dev/null || printf 120)
[[ "$threshold_seconds" =~ ^[1-9][0-9]*$ ]] || threshold_seconds=120
threshold_ms=$((threshold_seconds * 1000))
now=$(tmux_runtime_now_ms)

while IFS= read -r agent_id; do
  [ -n "$agent_id" ] || continue
  bump_warn "stale heartbeat: $agent_id"
done < <(jq -r --argjson now "$now" --argjson threshold "$threshold_ms" '
  .agents[]
  | select(.state != "shutdown" and .heartbeat_at_ms != null and (.heartbeat_at_ms + $threshold) <= $now)
  | .agent_id
' <<<"$registry")

if [ "${#findings[@]}" -gt 0 ]; then
  detail=$(printf '%s; ' "${findings[@]}")
  emit "$worst" "${detail%; }"
fi

backend=$(jq -r '.agent_execution_mode // "in_process"' "$config_path" 2>/dev/null || printf 'in_process')
case "$backend" in
  in_process|tmux|ask) ;;
  *) backend=in_process ;;
esac
agent_total=$(jq '[.agents[]] | length' <<<"$registry")
running=$(jq '[.agents[] | select(.state == "running")] | length' <<<"$registry")
idle=$(jq '[.agents[] | select(.state == "idle")] | length' <<<"$registry")
failed=$(jq '[.agents[] | select(.state == "failed")] | length' <<<"$registry")
if [ -n "$session" ]; then
  emit PASS "backend=${backend} session=${session} panes=${present_panes}/${expected_panes} agents=${agent_total} running:${running} idle:${idle} failed:${failed} heartbeats=fresh"
fi
emit PASS "backend=${backend} session=none agents=${agent_total} running:${running} idle:${idle} failed:${failed} heartbeats=fresh"
