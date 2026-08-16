#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

fail() {
  printf 'tmux-spawn-group: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: tmux-spawn-group.sh <build-agents|dispatch> [options]' >&2
  printf '%s\n' '  build-agents --names NAME[,NAME...] --contract-id ID --contract-digest DIGEST' >&2
  printf '%s\n' '               [--spawn-ready-text TEXT] [--spawn-ready-file PATH]' >&2
  printf '%s\n' '  dispatch --project-root PATH --control-root PATH --main-id ID --contract-id ID --contract-digest DIGEST --job TEXT --timeout-ms MS' >&2
  printf '%s\n' '           [--names NAME[,NAME...]] [--spawn-ready-text TEXT] [--spawn-ready-file PATH] [--main-capability TOKEN] [--run-id ID]' >&2
  exit 2
}

require_token() {
  local value="$1" label="$2"
  [ -n "$value" ] || fail "$label is required"
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "$label is invalid"
}

parse_spawn_ready_names() {
  local text="$1"
  printf '%s\n' "$text" | awk '/SPAWN_READY / { print $NF }'
}

collect_names() {
  local from_text from_file name
  NAMES=()
  if [ -n "$names_csv" ]; then
    IFS=',' read -r -a NAMES <<<"$names_csv"
  fi
  from_text="$spawn_ready_text"
  if [ -n "$spawn_ready_file" ]; then
    [ -f "$spawn_ready_file" ] || fail "spawn-ready file is missing: $spawn_ready_file"
    from_file=$(cat "$spawn_ready_file")
    from_text="${from_text:+$from_text$'\n'}$from_file"
  fi
  if [ -n "$from_text" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      NAMES+=("$name")
    done < <(parse_spawn_ready_names "$from_text")
  fi
  [ "${#NAMES[@]}" -gt 0 ] || fail 'no SPAWN_READY names supplied'
  for name in "${NAMES[@]}"; do
    require_token "$name" 'generated agent name'
  done
}

build_agents_json() {
  local name json='[]'
  require_token "$contract_id" 'contract id'
  require_token "$contract_digest" 'contract digest'
  collect_names
  for name in "${NAMES[@]}"; do
    json=$(jq -c --arg id "$name" --arg contract_id "$contract_id" --arg contract_digest "$contract_digest" \
      '. + [{agent_id:$id, generated_name:$id, contract_id:$contract_id, contract_digest:$contract_digest}]' <<<"$json")
  done
  jq -e 'length > 0 and all(.[]; .agent_id == .generated_name and (.agent_id | type == "string") and (.contract_id | type == "string") and (.contract_digest | type == "string"))' >/dev/null <<<"$json" || fail 'agents JSON is malformed'
  printf '%s\n' "$json"
}

bus() {
  bash "$SCRIPT_DIR/tmux-bus.sh" --control-root "$control_root" "$@"
}

orchestrator() {
  bash "$SCRIPT_DIR/tmux-agent-orchestrator.sh" "$@" --project-root "$project_root" --control-root "$control_root"
}

rollback_split() {
  [ -n "$main_capability" ] || return 0
  orchestrator rollback --run-id "$run_id" --orchestrator-id "$main_id" --orchestrator-session-id "$main_id" --orchestrator-capability "$main_capability" >/dev/null || true
}

await_ack_one() {
  local agent_id="$1" awaited message_id message_type payload
  awaited=$(bus await --from "$agent_id" --agent-id "$main_id" --session-id "$main_id" --role orchestrator --capability "$main_capability" --types result,error --timeout-ms "$timeout_ms") || fail "await failed for $agent_id"
  message_id=$(jq -r '.message_id // empty' <<<"$awaited")
  message_type=$(jq -r '.type // empty' <<<"$awaited")
  payload=$(jq -c '.body' <<<"$awaited")
  [[ "$message_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "await returned an invalid message id for $agent_id"
  case "$message_type" in result|error) ;; *) fail "await returned an unexpected type for $agent_id" ;; esac
  bus claim --agent-id "$main_id" --session-id "$main_id" --capability "$main_capability" --type "$message_type" --lease-ms 5000 >/dev/null || fail "claim failed for $agent_id"
  bus ack --agent-id "$main_id" --session-id "$main_id" --capability "$main_capability" --message-id "$message_id" >/dev/null || fail "ack failed for $agent_id"
  jq -nc --arg agent_id "$agent_id" --arg message_id "$message_id" --arg type "$message_type" --argjson payload "$payload" \
    '{agent_id:$agent_id,generated_name:$agent_id,message_id:$message_id,type:$type,payload:$payload}'
}

dispatch() {
  local agents_json preflight provision session job_payload item agent_id results='[]' result_entry status='completed'
  require_token "$main_id" 'main id'
  require_token "$contract_id" 'contract id'
  require_token "$contract_digest" 'contract digest'
  [ -n "$project_root" ] || fail '--project-root is required'
  [ -n "$control_root" ] || fail '--control-root is required'
  [ -n "$job" ] || fail '--job is required'
  [[ "$timeout_ms" =~ ^[1-9][0-9]*$ ]] || fail '--timeout-ms must be a positive millisecond count'
  [ -d "$project_root" ] || fail "project root does not exist: $project_root"
  run_id="${run_id:-$contract_id}"
  require_token "$run_id" 'run id'
  agents_json=$(build_agents_json)
  job_payload=$(jq -nc --arg brief "$job" '{brief:$brief}')

  bash "$SCRIPT_DIR/tmux-preflight.sh" --project-root "$project_root" --control-root "$control_root" --main-id "$main_id" >/dev/null || fail 'preflight failed'

  if [ -n "$main_capability" ]; then
    provision=$(orchestrator provision --main-id "$main_id" --orchestrator-id "$main_id" --orchestrator-session-id "$main_id" --orchestrator-capability "$main_capability") || fail 'provision failed'
  else
    provision=$(orchestrator provision --main-id "$main_id") || fail 'provision failed'
    main_capability=$(jq -r '.main_capability // empty' <<<"$provision")
  fi
  [ -n "$main_capability" ] || fail 'provision did not return a main capability'
  session=$(jq -r '.tmux_session // empty' <<<"$provision")
  [ -n "$session" ] || fail 'provision did not return a tmux session'

  if ! orchestrator split-group --session "$session" --agents "$agents_json" --orchestrator-id "$main_id" --orchestrator-session-id "$main_id" --orchestrator-capability "$main_capability"; then
    rollback_split
    fail 'split-group failed'
  fi

  while IFS= read -r item; do
    agent_id=$(jq -r '.agent_id' <<<"$item")
    bus publish --to "$agent_id" --from-agent-id "$main_id" --from-session-id "$main_id" --from-role orchestrator --capability "$main_capability" --type job --correlation-id "$contract_id" --payload "$job_payload" >/dev/null || fail "publish failed for $agent_id"
    result_entry=$(await_ack_one "$agent_id") || fail "await/ack failed for $agent_id"
    [ "$(jq -r '.type' <<<"$result_entry")" = result ] || status='failed'
    results=$(jq -c --argjson entry "$result_entry" '. + [$entry]' <<<"$results")
  done < <(jq -c '.[]' <<<"$agents_json")

  jq -n --arg status "$status" --arg main_id "$main_id" --arg main_capability "$main_capability" --arg session "$session" --arg contract_id "$contract_id" --argjson agents "$results" \
    '{status:$status,main_id:$main_id,main_capability:$main_capability,tmux_session:$session,contract_id:$contract_id,agents:$agents}'
}

[ "$#" -gt 0 ] || usage
subcommand="$1"
shift

project_root=''
control_root=''
main_id=''
main_capability=''
contract_id=''
contract_digest=''
names_csv=''
spawn_ready_text=''
spawn_ready_file=''
job=''
timeout_ms=''
run_id=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root) [ "$#" -ge 2 ] || usage; project_root="$2"; shift 2 ;;
    --control-root) [ "$#" -ge 2 ] || usage; control_root="$2"; shift 2 ;;
    --main-id) [ "$#" -ge 2 ] || usage; main_id="$2"; shift 2 ;;
    --main-capability) [ "$#" -ge 2 ] || usage; main_capability="$2"; shift 2 ;;
    --contract-id) [ "$#" -ge 2 ] || usage; contract_id="$2"; shift 2 ;;
    --contract-digest) [ "$#" -ge 2 ] || usage; contract_digest="$2"; shift 2 ;;
    --names) [ "$#" -ge 2 ] || usage; names_csv="$2"; shift 2 ;;
    --spawn-ready-text) [ "$#" -ge 2 ] || usage; spawn_ready_text="$2"; shift 2 ;;
    --spawn-ready-file) [ "$#" -ge 2 ] || usage; spawn_ready_file="$2"; shift 2 ;;
    --job) [ "$#" -ge 2 ] || usage; job="$2"; shift 2 ;;
    --timeout-ms) [ "$#" -ge 2 ] || usage; timeout_ms="$2"; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id="$2"; shift 2 ;;
    *) usage ;;
  esac
done

case "$subcommand" in
  build-agents) build_agents_json ;;
  dispatch) dispatch ;;
  *) usage ;;
esac
