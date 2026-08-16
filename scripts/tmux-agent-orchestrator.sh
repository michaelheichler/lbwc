#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
source "$SCRIPT_DIR/lib/lbwc-control-root.sh"
source "$SCRIPT_DIR/lib/tmux-runtime.sh"
source "$SCRIPT_DIR/lib/agent-manifest.sh"

fail() {
  printf 'tmux orchestrator error: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: tmux-agent-orchestrator.sh <provision|split-agent|split-group|focus-orchestrator|kill-agent|kill-session|status|rollback> --project-root PATH --control-root PATH [options]' >&2
  exit 2
}

require_tmux() {
  local tool
  for tool in tmux jq claude uuidgen shasum cut id mktemp perl date mkdir chmod mv rm rmdir python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "required command is unavailable: $tool"
  done
}

resolve_context() {
  [ -d "$project_root" ] || fail "project root does not exist: $project_root"
  PROJECT_ROOT=$(cd "$project_root" && pwd -P)
  tmux_runtime_configure "$requested_control_root"
}

ensure_runtime_layout() {
  tmux_runtime_ensure || return 1
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/inboxes"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox/main"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/transactions"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/claims"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/credentials"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/heartbeats"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/locks"
}

tmux_session_exists() {
  tmux has-session -t "$1" >/dev/null 2>&1
}

tmux_pane_exists() {
  local pane_id
  pane_id=$(tmux display-message -p -t "$1" '#{pane_id}' 2>/dev/null || true)
  [[ "$pane_id" =~ ^%[0-9]+$ ]]
}

new_registry() {
  local main_id="$1" capability_hash="$2"
  jq -n --arg main "$main_id" --arg hash "$capability_hash" '
    {schema_version: 2, main: {agent_id: $main, session_id: $main, role: "orchestrator", capability_hash: $hash}, tmux: {session: null, orchestrator_target: null, orchestrator_pane: null, topology: "pending", managed_session: false, ownership_token: null}, agents: [], routes: {($main): {inbox: $main, tmux_target: null}}}'
}

require_main_orchestrator() {
  local registry
  tmux_runtime_require_bus
  registry=$(tmux_runtime_registry_read)
  tmux_runtime_principal_valid "$registry" "$orchestrator_id" "$orchestrator_session_id" orchestrator "$orchestrator_capability" || fail 'main orchestrator session and capability are required'
  [ "$orchestrator_id" = "$(jq -r '.main.agent_id' <<<"$registry")" ] || fail 'operation requires the main orchestrator'
}

tmux_layout_config() {
  layout=$(jq -r '.tmux_execution.layout // .tmux.layout // "tiled"' "$TMUX_RUNTIME_CONTROL_ROOT/config.json")
  case "$layout" in tiled|even-horizontal|even-vertical|main-horizontal|main-vertical) ;; *) fail 'tmux layout is invalid' ;; esac
  max_agents=$(jq -r '.tmux_execution.max_agents // .tmux.max_agents // 3' "$TMUX_RUNTIME_CONTROL_ROOT/config.json")
  [[ "$max_agents" =~ ^[1-4]$ ]] || fail 'tmux max_agents must be between 1 and 4'
}

apply_tmux_layout() {
  tmux select-layout -t "$1" "$layout"
}

configure_pane_borders() {
  tmux set-option -t "$1" pane-border-status top && tmux set-option -t "$1" pane-border-format '#{pane_title}'
}

teardown_intent_path() {
  printf '%s/transactions/teardown-%s.json\n' "$TMUX_RUNTIME_BUS_ROOT" "$1"
}

write_teardown_intent() {
  local name="$1" target="$2" state="$3" path
  path=$(teardown_intent_path "$name")
  tmux_runtime_atomic_json "$path" "$(jq -n --arg target "$target" --arg state "$state" --argjson updated_at "$(tmux_runtime_now_ms)" '{schema_version: 1, kind: "teardown", target: $target, state: $state, updated_at: $updated_at}')"
}

teardown_process_stopped() {
  local name="$1" target="$2" path
  path=$(teardown_intent_path "$name")
  tmux_runtime_private_file "$path" || return 1
  jq -e --arg target "$target" '.schema_version == 1 and .kind == "teardown" and .target == $target and .state == "process_stopped"' "$path" >/dev/null 2>&1
}

clear_teardown_intent() {
  rm -f "$(teardown_intent_path "$1")"
}

persist_shutdown_agents() {
  local registry="$1" agent_ids="$2" updated agent_id
  updated=$(jq --argjson agent_ids "$agent_ids" '
    .main.agent_id as $main_id
    | .agents |= map(if (.agent_id as $agent_id | $agent_ids | index($agent_id)) then .state = "shutdown" | .tmux_pane_id = null else . end)
    | .routes |= with_entries(.key as $agent_id | select($agent_id == $main_id or ($agent_ids | index($agent_id) | not)))
  ' <<<"$registry") || return 1
  tmux_runtime_write_registry_route_bundle "$updated" || return 1
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    rm -rf "$(tmux_runtime_inbox "$agent_id")" || return 1
  done < <(jq -r '.[]' <<<"$agent_ids")
}

rollback_provision() {
  local managed="$1" session="$2" created_registry="$3" main_inbox="$4" created_runtime="$5" original_registry="$6"
  if [ "$managed" = true ] && [ -n "$session" ]; then
    tmux kill-session -t "$session" >/dev/null 2>&1 || true
  fi
  if [ "$created_registry" = true ]; then
    rm -f "$TMUX_RUNTIME_BUS_ROOT/registry.json" "$TMUX_RUNTIME_BUS_ROOT/routing-table.json"
  fi
  [ -z "$main_inbox" ] || rm -rf "$TMUX_RUNTIME_BUS_ROOT/inboxes/$main_inbox"
  if [ -n "$original_registry" ]; then
    tmux_runtime_atomic_json "$TMUX_RUNTIME_BUS_ROOT/registry.json" "$original_registry" >/dev/null 2>&1 || true
    tmux_runtime_write_routing_table "$original_registry" >/dev/null 2>&1 || true
  fi
  if [ "$created_runtime" = true ]; then
    rmdir "$TMUX_RUNTIME_BUS_ROOT/inboxes" "$TMUX_RUNTIME_BUS_ROOT/outbox/main" "$TMUX_RUNTIME_BUS_ROOT/outbox" "$TMUX_RUNTIME_BUS_ROOT/transactions" "$TMUX_RUNTIME_BUS_ROOT/claims" "$TMUX_RUNTIME_BUS_ROOT/credentials" "$TMUX_RUNTIME_BUS_ROOT/heartbeats" "$TMUX_RUNTIME_BUS_ROOT/locks" "$TMUX_RUNTIME_BUS_ROOT" "$TMUX_RUNTIME_ROOT" 2>/dev/null || true
  fi
}

provision() {
  local preflight session topology target pane managed=false ownership='' capability hash registry original_registry='' updated attached_pane new_registry=false created_runtime=false main_inbox=''
  [ -n "$main_id" ] || fail '--main-id is required for provision'
  tmux_runtime_valid_token "$main_id" || fail 'main id is invalid'
  preflight=$(bash "$SCRIPT_DIR/tmux-preflight.sh" --project-root "$PROJECT_ROOT" --control-root "$TMUX_RUNTIME_CONTROL_ROOT" --main-id "$main_id") || exit $?
  [ -e "$TMUX_RUNTIME_ROOT" ] || created_runtime=true
  ensure_runtime_layout || fail 'cannot initialize private tmux runtime'
  tmux_runtime_lock_acquire registry 5000 30000
  if [ -e "$TMUX_RUNTIME_BUS_ROOT/registry.json" ]; then
    registry=$(tmux_runtime_registry_read)
    original_registry="$registry"
    jq -e --arg id "$main_id" '.main.agent_id == $id' <<<"$registry" >/dev/null || fail 'existing registry belongs to another main id'
    tmux_runtime_principal_valid "$registry" "$orchestrator_id" "$orchestrator_session_id" orchestrator "$orchestrator_capability" || fail 'main orchestrator session and capability are required for existing provision'
    capability=''
  else
    capability=$(tmux_runtime_capability)
    hash=$(tmux_runtime_capability_hash "$capability")
    registry=$(new_registry "$main_id" "$hash")
    new_registry=true
  fi
  session=$(jq -r '.tmux_session' <<<"$preflight")
  topology=$(jq -r '.topology' <<<"$preflight")
  case "$topology" in
    attached-existing-tmux)
      attached_pane="${TMUX_PANE:-}"
      [ -n "$attached_pane" ] || fail 'attached orchestration pane is unavailable'
      target=$(tmux display-message -p -t "$attached_pane" '#{session_name}:#{window_index}.#{pane_index}') || fail 'cannot resolve attached orchestrator pane'
      pane=$(tmux display-message -p -t "$attached_pane" '#{pane_index}') || fail 'cannot resolve attached orchestrator pane index'
      managed=false
      ownership=''
      ;;
    detached-new-session)
      tmux new-session -d -s "$session" -n orchestrator -c "$PROJECT_ROOT" || fail "cannot create detached tmux session: $session"
      target=$(tmux display-message -p -t "$session:0.0" '#{session_name}:#{window_index}.#{pane_index}') || { rollback_provision true "$session" "$new_registry" '' "$created_runtime" "$original_registry"; fail 'cannot resolve detached orchestrator pane'; }
      pane=$(tmux display-message -p -t "$target" '#{pane_index}') || { rollback_provision true "$session" "$new_registry" '' "$created_runtime" "$original_registry"; fail 'cannot resolve detached orchestrator pane index'; }
      ownership=$(tmux_runtime_capability)
      tmux set-option -t "$session" @lbwc_ownership_token "$ownership" || { rollback_provision true "$session" "$new_registry" '' "$created_runtime" "$original_registry"; fail 'cannot mark owned tmux session'; }
      tmux select-pane -t "$target" -T 'LBWC orchestrator' || { rollback_provision true "$session" "$new_registry" '' "$created_runtime" "$original_registry"; fail 'cannot label orchestrator pane'; }
      managed=true
      ;;
    *) fail "unsupported topology: $topology" ;;
  esac
  updated=$(jq --arg session "$session" --arg target "$target" --arg pane "$pane" --arg topology "$topology" --arg ownership "$ownership" --argjson managed "$managed" '
    .tmux = {session: $session, orchestrator_target: $target, orchestrator_pane: $pane, topology: $topology, managed_session: $managed, ownership_token: (if $managed then $ownership else null end)}
    | .routes[.main.agent_id].tmux_target = $target' <<<"$registry")
  tmux_layout_config
  configure_pane_borders "$session" || { tmux_runtime_lock_release registry || true; rollback_provision "$managed" "$session" "$new_registry" '' "$created_runtime" "$original_registry"; fail 'cannot configure pane borders'; }
  if [ "$new_registry" = true ] && ! tmux_runtime_initialize_inbox "$main_id"; then
    tmux_runtime_lock_release registry || true
    rollback_provision "$managed" "$session" "$new_registry" "$main_id" "$created_runtime" "$original_registry"
    fail 'cannot initialize main inbox for provisioned session'
  fi
  [ "$new_registry" = false ] || main_inbox="$main_id"
  if ! tmux_runtime_write_registry_route_bundle "$updated"; then
    tmux_runtime_lock_release registry || true
    rollback_provision "$managed" "$session" "$new_registry" "$main_inbox" "$created_runtime" "$original_registry"
    fail 'cannot publish provisioned registry and routing table'
  fi
  tmux_runtime_lock_release registry
  jq -n --arg session "$session" --arg target "$target" --arg topology "$topology" --arg capability "$capability" '{tmux_session: $session, orchestrator_target: $target, topology: $topology, main_capability: $capability}'
}

add_agent_entry() {
  local registry="$1" agent_id="$2" generated_name="$3" contract_id="$4" target="$5" pane_id="$6" capability_hash="$7"
  jq --arg id "$agent_id" --arg generated "$generated_name" --arg contract "$contract_id" --arg target "$target" --arg pane_id "$pane_id" --arg hash "$capability_hash" '
    .agents += [{agent_id: $id, parent_id: .main.agent_id, contract_id: $contract, generated_name: $generated, tmux_target: $target, tmux_pane_id: $pane_id, claude_session_id: null, capability_hash: $hash, state: "registered", heartbeat_at_ms: null}]
    | .routes[$id] = {inbox: $id, tmux_target: $target}' <<<"$registry"
}

prepare_agent_pane() {
  local orchestrator_target="$1" agent_id="$2" contract_id="$3" pane_id target
  pane_id=$(tmux split-window -e LBWC_TMUX_AGENT=1 -e "LBWC_TMUX_CONTROL_ROOT=$TMUX_RUNTIME_CONTROL_ROOT" -e "LBWC_TMUX_AGENT_ID=$agent_id" -e "LBWC_TMUX_CONTRACT_ID=$contract_id" -t "$orchestrator_target" -c "$PROJECT_ROOT" -P -F '#{pane_id}') || return 1
  [[ "$pane_id" =~ ^%[0-9]+$ ]] || return 1
  target=$(tmux display-message -p -t "$pane_id" '#{session_name}:#{window_index}.#{pane_index}') || { tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true; return 1; }
  if ! tmux select-pane -t "$pane_id" -T "$agent_id"; then
    tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    return 1
  fi
  jq -n --arg pane_id "$pane_id" --arg target "$target" '{pane_id: $pane_id, target: $target}'
}

launch_agent() {
  local orchestrator_target="$1" target="$2" generated_name="$3" command
  printf -v command 'exec claude --agent %q' "$generated_name"
  tmux send-keys -t "$target" "$command" C-m && tmux select-pane -t "$orchestrator_target"
}

rollback_split_group() {
  local original_registry="$1" original_routing="$2" pane_ids="$3" agent_ids="$4" pane_id agent_id
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] && write_teardown_intent "$agent_id" "$agent_id" prepared || true
  done <<<"$agent_ids"
  while IFS= read -r pane_id; do
    [ -n "$pane_id" ] && tmux kill-pane -t "$pane_id" >/dev/null 2>&1 || true
  done <<<"$pane_ids"
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    rm -rf "$TMUX_RUNTIME_BUS_ROOT/inboxes/$agent_id"
    python3 "$TMUX_RUNTIME_HELPER" delete --root "$TMUX_RUNTIME_BUS_ROOT" --relative "credentials/$agent_id.json" >/dev/null 2>&1 || true
  done <<<"$agent_ids"
  tmux_runtime_atomic_json "$TMUX_RUNTIME_BUS_ROOT/registry.json" "$original_registry" >/dev/null 2>&1 || true
  tmux_runtime_atomic_json "$TMUX_RUNTIME_BUS_ROOT/routing-table.json" "$original_routing" >/dev/null 2>&1 || true
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] && clear_teardown_intent "$agent_id"
  done <<<"$agent_ids"
}

split_validation_error() {
  SPLIT_VALIDATION_ERROR="$1"
  return 1
}

validate_split_group_definitions() {
  local definitions="$1" manifest_path manifest item agent_id generated_name contract_id contract_digest entry contract_path contract definition_path definition_digest
  SPLIT_VALIDATION_ERROR=''
  jq -e '
    type == "array" and length > 0
    and all(.[];
      type == "object"
      and ((keys | sort) == ["agent_id", "contract_digest", "contract_id", "generated_name"])
      and (.agent_id | type == "string")
      and (.generated_name | type == "string")
      and (.contract_id | type == "string")
      and (.contract_digest | type == "string" and test("^[0-9a-f]{64}$"))
    )
    and (([.[].agent_id] | length) == ([.[].agent_id] | unique | length))
  ' >/dev/null 2>&1 <<<"$definitions" || { split_validation_error 'agent group definitions must contain exact agent, generated, contract, and digest identities'; return 1; }

  manifest_path=$(agent_manifest_path "$TMUX_RUNTIME_CONTROL_ROOT") || { split_validation_error 'generated agent manifest is unavailable'; return 1; }
  [ -f "$manifest_path" ] && [ ! -L "$manifest_path" ] || { split_validation_error 'generated agent manifest is missing'; return 1; }
  manifest=$(jq -ce 'select(type == "object" and (.agents | type == "object"))' "$manifest_path" 2>/dev/null) || { split_validation_error 'generated agent manifest is malformed'; return 1; }

  while IFS= read -r item; do
    agent_id=$(jq -r '.agent_id' <<<"$item")
    generated_name=$(jq -r '.generated_name' <<<"$item")
    contract_id=$(jq -r '.contract_id' <<<"$item")
    contract_digest=$(jq -r '.contract_digest' <<<"$item")
    for value in "$agent_id" "$generated_name" "$contract_id"; do
      tmux_runtime_valid_token "$value" || { split_validation_error 'agent group contains an invalid identifier'; return 1; }
    done
    [ "$agent_id" = "$generated_name" ] || { split_validation_error 'agent and generated identities must match'; return 1; }
    entry=$(jq -ce --arg name "$agent_id" '.agents[$name] | select(type == "object")' <<<"$manifest" 2>/dev/null) || { split_validation_error "generated agent is not registered: $agent_id"; return 1; }
    [ "$(jq -r '.name // empty' <<<"$entry")" = "$agent_id" ] || { split_validation_error 'generated manifest identity does not match agent id'; return 1; }
    [ "$(jq -r '.contract_id // empty' <<<"$entry")" = "$contract_id" ] || { split_validation_error 'contract identity does not match generated manifest'; return 1; }
    [ "$(jq -r '.contract_digest // empty' <<<"$entry")" = "$contract_digest" ] || { split_validation_error 'contract digest does not match generated manifest'; return 1; }
    jq -e '
      .schema_version == 3
      and .state == "registered"
      and .contract_enabled == true
      and .definition_authority == "generated-definition"
      and .runtime_kind == "native-team"
      and .communication_policy == "native-team"
    ' <<<"$entry" >/dev/null 2>&1 || { split_validation_error 'generated manifest entry is not an unconsumed schema 3 native-team definition'; return 1; }
    jq -e '
      . as $entry
      | (.execution | type == "object")
      and .execution.role == $entry.role
      and .execution.model == $entry.model
      and .execution.effort == $entry.effort
      and .execution.max_turns == $entry.max_turns
      and .execution.contract_id == $entry.contract_id
      and .execution.contract_digest == $entry.contract_digest
      and .execution.task_identity == $entry.task_identity
    ' <<<"$entry" >/dev/null 2>&1 || { split_validation_error 'generated agent execution identity does not match the manifest'; return 1; }
    contract_path=$(jq -r '.contract_path // empty' <<<"$entry")
    [ -n "$contract_path" ] || { split_validation_error 'generated agent contract path is missing'; return 1; }
    contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$contract_path" "$PROJECT_ROOT" 2>/dev/null) || { split_validation_error 'generated agent contract is missing, stale, or tampered'; return 1; }
    jq -e --arg id "$contract_id" --arg digest "$contract_digest" --arg control_root "$TMUX_RUNTIME_CONTROL_ROOT" '
      .schema_version == 3
      and .state == "dispatched"
      and .runtime_kind == "native-team"
      and .communication_policy == "native-team"
      and .control_root == $control_root
      and .contract_id == $id
      and .contract_digest == $digest
      and .task_identity == $id
      and .requested_backend == "tmux"
      and .resolved_backend == "tmux"
    ' <<<"$contract" >/dev/null 2>&1 || { split_validation_error 'generated agent contract does not match the schema 3 native-team pipeline'; return 1; }
    jq -e --arg name "$agent_id" --arg control_root "$TMUX_RUNTIME_CONTROL_ROOT" \
      --arg requested "$(jq -r '.requested_backend' <<<"$contract")" \
      --arg resolved "$(jq -r '.resolved_backend' <<<"$contract")" '
      . as $entry
      | ($entry.execution | type == "object")
      and $entry.execution.requested_backend == $requested
      and $entry.execution.resolved_backend == $resolved
      and ($entry.execution.tmux_bootstrap | type == "object")
      and $entry.execution.tmux_bootstrap.child_identity == $name
      and $entry.execution.tmux_bootstrap.contract_id == $entry.contract_id
      and $entry.execution.tmux_bootstrap.control_root == $control_root
    ' <<<"$entry" >/dev/null 2>&1 || { split_validation_error 'generated agent backend metadata does not match the contract'; return 1; }
    definition_path=$(jq -r '.definition_path // empty' <<<"$entry")
    [ "$definition_path" = "$PROJECT_ROOT/.claude/agents/$agent_id.md" ] || { split_validation_error 'generated definition path is invalid'; return 1; }
    [ -f "$definition_path" ] && [ ! -L "$definition_path" ] || { split_validation_error 'generated definition is missing'; return 1; }
    definition_digest=$(shasum -a 256 "$definition_path" | cut -d ' ' -f 1) || { split_validation_error 'cannot hash generated definition'; return 1; }
    [ "$definition_digest" = "$(jq -r '.definition_sha256 // empty' <<<"$entry")" ] || { split_validation_error 'generated definition digest does not match manifest'; return 1; }
  done < <(jq -c '.[]' <<<"$definitions")
}

split_agent_definition() {
  local manifest_path manifest entry
  manifest_path=$(agent_manifest_path "$TMUX_RUNTIME_CONTROL_ROOT") || fail 'generated agent manifest is unavailable'
  [ -f "$manifest_path" ] && [ ! -L "$manifest_path" ] || fail 'generated agent manifest is missing'
  manifest=$(jq -ce 'select(type == "object" and (.agents | type == "object"))' "$manifest_path" 2>/dev/null) || fail 'generated agent manifest is malformed'
  entry=$(jq -ce --arg name "$agent_id" '.agents[$name] | select(type == "object")' <<<"$manifest" 2>/dev/null) || fail "generated agent is not registered: $agent_id"
  jq -cn --arg id "$agent_id" --arg generated "$generated_agent" \
    --arg contract_id "$(jq -r '.contract_id // empty' <<<"$entry")" \
    --arg contract_digest "$(jq -r '.contract_digest // empty' <<<"$entry")" \
    '[{agent_id:$id,generated_name:$generated,contract_id:$contract_id,contract_digest:$contract_digest}]'
}

split_group() {
  local definitions="$1" registry original_registry original_routing orchestrator_target current_session item agent_id generated contract_id prepared target pane_id capability hash credential index created_pane_ids=() created_agent_ids=() created_generated_names=() capabilities='[]'
  agent_manifest_with_lock "$TMUX_RUNTIME_CONTROL_ROOT" validate_split_group_definitions "$definitions" || fail "${SPLIT_VALIDATION_ERROR:-generated agent validation failed}"
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  original_registry="$registry"
  original_routing=$(cat "$TMUX_RUNTIME_BUS_ROOT/routing-table.json")
  tmux_layout_config
  [ $(( $(jq '[.agents[] | select(.state != "shutdown")] | length' <<<"$registry") + $(jq 'length' <<<"$definitions") )) -le "$max_agents" ] || fail "tmux agent limit exceeded: $max_agents"
  current_session=$(jq -r '.tmux.session' <<<"$registry")
  [ "$session" = "$current_session" ] || fail 'session does not match registry'
  orchestrator_target=$(jq -r '.tmux.orchestrator_target' <<<"$registry")
  tmux_pane_exists "$orchestrator_target" || fail 'registered orchestrator pane does not exist'
  while IFS= read -r item; do
    agent_id=$(jq -r '.agent_id' <<<"$item")
    generated=$(jq -r '.generated_name' <<<"$item")
    contract_id=$(jq -r '.contract_id' <<<"$item")
    for value in "$agent_id" "$generated" "$contract_id"; do tmux_runtime_valid_token "$value" || fail 'agent group contains an invalid identifier'; done
    jq -e --arg id "$agent_id" 'all(.agents[]; .agent_id != $id) and .main.agent_id != $id' <<<"$registry" >/dev/null || fail "agent is already registered: $agent_id"
    capability=$(tmux_runtime_capability)
    hash=$(tmux_runtime_capability_hash "$capability")
    credential=$(jq -n --arg agent_id "$agent_id" --arg contract_id "$contract_id" --arg capability "$capability" '{agent_id:$agent_id,contract_id:$contract_id,capability:$capability}')
    tmux_runtime_atomic_json "$TMUX_RUNTIME_BUS_ROOT/credentials/$agent_id.json" "$credential" || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot publish agent capability: $agent_id"
    }
    created_agent_ids+=("$agent_id")
    prepared=$(prepare_agent_pane "$orchestrator_target" "$agent_id" "$contract_id") || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot start generated agent: $agent_id"
    }
    pane_id=$(jq -r '.pane_id' <<<"$prepared") || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot resolve generated agent pane identity: $agent_id"
    }
    target=$(jq -r '.target' <<<"$prepared") || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot resolve generated agent target: $agent_id"
    }
    [[ "$pane_id" =~ ^%[0-9]+$ ]] && tmux_runtime_valid_target "$target" || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "generated agent pane identity is invalid: $agent_id"
    }
    created_pane_ids+=("$pane_id")
    created_generated_names+=("$generated")
    capabilities=$(jq --arg id "$agent_id" --arg capability "$capability" '. + [{agent_id: $id, capability: $capability}]' <<<"$capabilities")
    if ! tmux_runtime_initialize_inbox "$agent_id" || ! registry=$(add_agent_entry "$registry" "$agent_id" "$generated" "$contract_id" "$target" "$pane_id" "$hash"); then
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot prepare generated agent runtime state"
    fi
  done < <(jq -c '.[]' <<<"$definitions")
  if ! tmux_runtime_write_registry_route_bundle "$registry"; then
    rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
    fail 'cannot publish generated agent registry and routing table'
  fi
  for ((index = 0; index < ${#created_pane_ids[@]}; index++)); do
    launch_agent "$orchestrator_target" "${created_pane_ids[$index]}" "${created_generated_names[$index]}" || {
      rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
      fail "cannot launch generated agent: ${created_agent_ids[$index]}"
    }
  done
  if ! apply_tmux_layout "$current_session"; then
    rollback_split_group "$original_registry" "$original_routing" "$(printf '%s\n' "${created_pane_ids[@]}")" "$(printf '%s\n' "${created_agent_ids[@]}")"
    fail 'cannot arrange generated agent panes'
  fi
  tmux_runtime_lock_release registry
  jq -n --argjson agents "$capabilities" '{state: "registered", agents: $agents}'
}

split_agent() {
  local definitions
  [ -n "$agent_id" ] || fail '--name is required for split-agent'
  [ -n "$generated_agent" ] || fail '--agent is required for split-agent'
  [ "$agent_id" = "$generated_agent" ] || fail 'agent and generated identities must match'
  definitions=$(split_agent_definition) || fail 'cannot resolve generated agent manifest identity'
  split_group "$definitions"
}

focus_orchestrator() {
  local registry target
  require_main_orchestrator
  registry=$(tmux_runtime_registry_read)
  target=$(jq -r '.tmux.orchestrator_target' <<<"$registry")
  tmux_pane_exists "$target" || fail 'registered orchestrator pane does not exist'
  tmux select-pane -t "$target" || fail 'cannot focus orchestrator pane'
  jq -n --arg target "$target" '{orchestrator_target: $target}'
}

kill_agent() {
  local registry agent_state pane_id remaining_pane_id agent_id
  require_main_orchestrator
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  agent_state=$(jq -r --arg target "$target" '.agents[] | select(.tmux_target == $target) | .state' <<<"$registry")
  agent_id=$(jq -r --arg target "$target" '.agents[] | select(.tmux_target == $target) | .agent_id' <<<"$registry")
  [ -n "$agent_state" ] || fail 'active agent target is not registered'
  pane_id=$(jq -r --arg target "$target" '.agents[] | select(.tmux_target == $target) | .tmux_pane_id' <<<"$registry")
  if [ "$pane_id" = null ]; then
    [ "$agent_state" = shutdown ] || fail 'registered agent pane identity is invalid'
    tmux_runtime_lock_release registry
    jq -n --arg target "$target" '{tmux_target: $target, state: "shutdown"}'
    return 0
  fi
  [[ "$pane_id" =~ ^%[0-9]+$ ]] || fail 'registered agent pane identity is invalid'
  write_teardown_intent "$agent_id" "$target" prepared || fail 'cannot persist agent teardown intent'
  if tmux_pane_exists "$pane_id"; then
    tmux kill-pane -t "$pane_id" || fail 'cannot kill owned agent pane'
    remaining_pane_id=$(tmux display-message -p -t "$pane_id" '#{pane_id}' 2>/dev/null || true)
    [ "$remaining_pane_id" != "$pane_id" ] || fail 'owned agent pane remains after kill request'
    write_teardown_intent "$agent_id" "$target" process_stopped || fail 'cannot persist stopped agent teardown intent'
  else
    write_teardown_intent "$agent_id" "$target" process_stopped || fail 'cannot persist absent agent shutdown state'
  fi
  persist_shutdown_agents "$registry" "$(jq -n --arg agent_id "$agent_id" '[ $agent_id ]')" || fail 'cannot persist agent shutdown state; retry to finalize teardown'
  clear_teardown_intent "$agent_id"
  tmux_runtime_lock_release registry
  jq -n --arg target "$target" '{tmux_target: $target, state: "shutdown"}'
}

kill_session() {
  local registry registered_session managed ownership marker agent_target agent_pane_id agent_id active_agents active_agent_ids snapshot_agent intent_name='session'
  require_main_orchestrator
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  registered_session=$(jq -r '.tmux.session' <<<"$registry")
  [ "$session" = "$registered_session" ] || fail 'session does not match registry'
  managed=$(jq -r '.tmux.managed_session' <<<"$registry")
  active_agent_ids=$(jq -c '[.agents[] | select(.state != "shutdown") | .agent_id]' <<<"$registry")
  write_teardown_intent "$intent_name" "$session" prepared || fail 'cannot persist session teardown intent'
  if [ "$managed" = true ] && tmux_session_exists "$session"; then
    ownership=$(jq -r '.tmux.ownership_token' <<<"$registry")
    marker=$(tmux show-options -v -t "$session" @lbwc_ownership_token 2>/dev/null || true)
    [ "$marker" = "$ownership" ] || fail 'owned tmux session is missing its provisioning ownership marker'
    tmux kill-session -t "$session" || fail 'cannot kill owned tmux session'
    tmux_session_exists "$session" && fail 'owned tmux session remains after kill request'
    write_teardown_intent "$intent_name" "$session" process_stopped || fail 'cannot persist stopped session teardown intent'
  elif [ "$managed" = true ]; then
    teardown_process_stopped "$intent_name" "$session" || fail 'owned tmux session is unavailable; refusing false shutdown'
  elif [ "$managed" = false ]; then
    active_agents='[]'
    while IFS= read -r agent; do
      agent_id=$(jq -r '.agent_id' <<<"$agent")
      agent_target=$(jq -r '.tmux_target' <<<"$agent")
      agent_pane_id=$(jq -r '.tmux_pane_id' <<<"$agent")
      [ -n "$agent_target" ] || fail 'registered external agent target is unavailable'
      [[ "$agent_pane_id" =~ ^%[0-9]+$ ]] || fail 'registered external agent pane identity is invalid'
      if tmux_pane_exists "$agent_pane_id"; then
        write_teardown_intent "$agent_id" "$agent_target" prepared || fail 'cannot persist external agent teardown intent'
        active_agents=$(jq --arg agent_id "$agent_id" --arg target "$agent_target" --arg pane_id "$agent_pane_id" '. + [{agent_id:$agent_id,tmux_target:$target,pane_id:$pane_id}]' <<<"$active_agents") || fail 'cannot snapshot external agent teardown'
      else
        write_teardown_intent "$agent_id" "$agent_target" prepared || fail 'cannot persist absent external agent teardown intent'
        write_teardown_intent "$agent_id" "$agent_target" process_stopped || fail 'cannot persist absent external agent shutdown state'
      fi
  done < <(jq -c '.agents[] | select(.state != "shutdown") | {agent_id, tmux_target, tmux_pane_id}' <<<"$registry")
    while IFS= read -r snapshot_agent; do
      agent_id=$(jq -r '.agent_id' <<<"$snapshot_agent")
      agent_target=$(jq -r '.tmux_target' <<<"$snapshot_agent")
      agent_pane_id=$(jq -r '.pane_id' <<<"$snapshot_agent")
      if tmux_pane_exists "$agent_pane_id"; then
        tmux kill-pane -t "$agent_pane_id" || fail 'cannot kill owned agent pane in external session'
        tmux_pane_exists "$agent_pane_id" && fail 'owned agent pane remains in external session'
      fi
      write_teardown_intent "$agent_id" "$agent_target" process_stopped || fail 'cannot persist stopped external agent teardown intent'
    done < <(jq -c '.[]' <<<"$active_agents")
    persist_shutdown_agents "$registry" "$active_agent_ids" || fail 'cannot persist session shutdown state; retry to finalize teardown'
    while IFS= read -r agent_id; do
      [ -n "$agent_id" ] && clear_teardown_intent "$agent_id"
    done < <(jq -r '.[]' <<<"$active_agent_ids")
    clear_teardown_intent "$intent_name"
    tmux_runtime_lock_release registry
    jq -n '{state: "agents_shutdown", external_session_preserved: true}'
    return 0
  fi
  persist_shutdown_agents "$registry" "$(jq -c '[.agents[].agent_id]' <<<"$registry")" || fail 'cannot persist session shutdown state; retry to finalize teardown'
  clear_teardown_intent "$intent_name"
  tmux_runtime_lock_release registry
  jq -n '{state: "shutdown", external_session_preserved: false}'
}

rollback() {
  local registry
  [ -n "$run_id" ] || fail '--run-id is required for rollback'
  tmux_runtime_valid_token "$run_id" || fail 'run id is invalid'
  require_main_orchestrator
  registry=$(tmux_runtime_registry_read)
  session=$(jq -r '.tmux.session // empty' <<<"$registry")
  if [ -z "$session" ]; then
    jq -n --arg run_id "$run_id" '{state: "rolled_back", run_id: $run_id, tmux_session: null}'
    return 0
  fi
  kill_session
}

status() {
  local registry
  require_main_orchestrator
  registry=$(tmux_runtime_registry_read)
  jq '.' <<<"$registry"
}

[ "$#" -gt 0 ] || usage
subcommand="$1"
shift
project_root=''
requested_control_root=''
main_id=''
session=''
agent_id=''
generated_agent=''
target=''
definitions=''
orchestrator_id=''
orchestrator_session_id=''
orchestrator_capability=''
run_id=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root) [ "$#" -ge 2 ] || usage; project_root="$2"; shift 2 ;;
    --control-root) [ "$#" -ge 2 ] || usage; requested_control_root="$2"; shift 2 ;;
    --main-id) [ "$#" -ge 2 ] || usage; main_id="$2"; shift 2 ;;
    --session) [ "$#" -ge 2 ] || usage; session="$2"; shift 2 ;;
    --name) [ "$#" -ge 2 ] || usage; agent_id="$2"; shift 2 ;;
    --agent) [ "$#" -ge 2 ] || usage; generated_agent="$2"; shift 2 ;;
    --agents) [ "$#" -ge 2 ] || usage; definitions="$2"; shift 2 ;;
    --target) [ "$#" -ge 2 ] || usage; target="$2"; shift 2 ;;
    --orchestrator-id) [ "$#" -ge 2 ] || usage; orchestrator_id="$2"; shift 2 ;;
    --orchestrator-session-id) [ "$#" -ge 2 ] || usage; orchestrator_session_id="$2"; shift 2 ;;
    --orchestrator-capability) [ "$#" -ge 2 ] || usage; orchestrator_capability="$2"; shift 2 ;;
    --run-id) [ "$#" -ge 2 ] || usage; run_id="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$project_root" ] || fail '--project-root is required'
[ -n "$requested_control_root" ] || fail '--control-root is required'
case "$subcommand" in provision|split-agent|split-group|focus-orchestrator|kill-agent|kill-session|status|rollback) ;; *) usage ;; esac
require_tmux
resolve_context
trap tmux_runtime_cleanup_locks EXIT

case "$subcommand" in
  provision) provision ;;
  split-agent) [ -n "$session" ] || fail '--session is required'; require_main_orchestrator; split_agent ;;
  split-group) [ -n "$session" ] || fail '--session is required'; [ -n "$definitions" ] || fail '--agents is required'; require_main_orchestrator; split_group "$definitions" ;;
  focus-orchestrator) focus_orchestrator ;;
  kill-agent) [ -n "$target" ] || fail '--target is required'; kill_agent ;;
  kill-session) [ -n "$session" ] || fail '--session is required'; kill_session ;;
  status) status ;;
  rollback) rollback ;;
esac
