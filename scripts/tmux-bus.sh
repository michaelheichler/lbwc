#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib/lbwc-control-root.sh"
source "$SCRIPT_DIR/lib/tmux-runtime.sh"

readonly MESSAGE_TYPES='job result heartbeat error shutdown_request shutdown_response'

envelope_validation() {
  jq -e '
    def token: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");
    def body_valid:
      if .type == "job" then (.body | type == "object" and (.brief | type == "string"))
      elif .type == "result" then (.body | type == "object" and (.result | type == "string"))
      elif .type == "error" then (.body | type == "object" and (.message | type == "string"))
      elif .type == "heartbeat" then (.body | type == "object" and (.state | IN("registered", "running", "idle", "failed", "shutdown")))
      elif .type == "shutdown_request" then (.body | type == "object" and (.reason | type == "string"))
      else (.body | type == "object" and (.acknowledged | type == "boolean")) end;
    .schema_version == 1
    and (.message_id | type == "string" and test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"))
    and (.correlation_id | token)
    and (.from | type == "object" and (.agent_id | token) and (.session_id | token) and (.role | IN("orchestrator", "agent")))
    and (.to | type == "object" and (.agent_id | token))
    and (.type | IN("job", "result", "heartbeat", "error", "shutdown_request", "shutdown_response"))
    and (.sent_at | type == "string")
    and (.sent_at as $sent_at | ($sent_at | fromdateiso8601 | strftime("%Y-%m-%dT%H:%M:%SZ")) == $sent_at)
    and body_valid
  '
}

fail() {
  printf 'tmux-bus: %s\n' "$1" >&2
  exit 1
}

require_tools() {
  local tool
  for tool in jq uuidgen mktemp mv mkdir chmod date sleep perl shasum cut id rm rmdir python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "required command is unavailable: $tool"
  done
}

valid_message_type() {
  case " $MESSAGE_TYPES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_envelope_file() {
  local path="$1"
  tmux_runtime_private_file "$path"
  envelope_validation < "$path" >/dev/null 2>&1 || fail "malformed message: $path"
}

validate_envelope_document() {
  envelope_validation >/dev/null 2>&1
}

envelope_document() {
  local message_id="$1" recipient="$2" agent_id="$3" session_id="$4" role="$5" message_type="$6" correlation_id="$7" payload="$8"
  jq -n \
    --arg message_id "$message_id" \
    --arg recipient "$recipient" \
    --arg agent_id "$agent_id" \
    --arg session_id "$session_id" \
    --arg role "$role" \
    --arg message_type "$message_type" \
    --arg correlation_id "$correlation_id" \
    --arg sent_at "$(tmux_runtime_iso_now)" \
    --argjson body "$payload" \
    '{schema_version: 1, message_id: $message_id, correlation_id: $correlation_id, from: {agent_id: $agent_id, session_id: $session_id, role: $role}, to: {agent_id: $recipient}, type: $message_type, sent_at: $sent_at, body: $body}'
}

transaction_document() {
  local message_id="$1" envelope="$2"
  jq -n --argjson created_at_ms "$(tmux_runtime_now_ms)" --argjson envelope "$envelope" --arg message_id "$message_id" \
    '{schema_version: 1, kind: "delivery", message_id: $message_id, state: "prepared", created_at_ms: $created_at_ms, envelope: $envelope}'
}

transaction_path() {
  printf '%s/transactions/%s.json\n' "$TMUX_RUNTIME_BUS_ROOT" "$1"
}

write_routing_table() {
  tmux_runtime_write_routing_table "$1" || fail 'cannot write routing table'
}

read_routing_table() {
  local registry="$1" path="$TMUX_RUNTIME_BUS_ROOT/routing-table.json"
  tmux_runtime_private_file "$path" || fail 'routing table is unavailable'
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
  ' "$path" >/dev/null 2>&1 || fail 'routing table is malformed or does not match the registry'
  cat "$path"
}

require_principal() {
  local agent_id="$1" session_id="$2" role="$3" capability="$4" main_only="$5" registry
  tmux_runtime_require_bus
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  tmux_runtime_principal_valid "$registry" "$agent_id" "$session_id" "$role" "$capability" || fail 'principal session, role, or capability is invalid'
  if [ "$main_only" = true ]; then
    [ "$role" = orchestrator ] && [ "$agent_id" = "$(jq -r '.main.agent_id' <<<"$registry")" ] || fail 'operation requires the main orchestrator'
  fi
  read_routing_table "$registry" >/dev/null
  tmux_runtime_lock_release registry
  printf '%s\n' "$registry"
}

deliver_transaction() {
  local message_id="$1" transaction_path transaction envelope recipient sender message_type inbox destination audit existing registry routes
  transaction_path=$(transaction_path "$message_id")
  tmux_runtime_private_file "$transaction_path"
  jq -e '.schema_version == 1 and .kind == "delivery" and (.state | IN("prepared", "committed")) and .message_id == $id and (.envelope | type == "object")' --arg id "$message_id" "$transaction_path" >/dev/null 2>&1 || fail "delivery transaction is malformed: $message_id"
  transaction=$(cat "$transaction_path")
  envelope=$(jq -c '.envelope' <<<"$transaction")
  validate_envelope_document <<<"$envelope" || fail "delivery transaction envelope is malformed: $message_id"
  recipient=$(jq -r '.to.agent_id' <<<"$envelope")
  sender=$(jq -r '.from.agent_id' <<<"$envelope")
  message_type=$(jq -r '.type' <<<"$envelope")
  registry=$(tmux_runtime_registry_read)
  routes=$(read_routing_table "$registry")
  inbox=$(tmux_runtime_inbox "$(jq -r --arg recipient "$recipient" '.routes[$recipient].inbox' <<<"$routes")")
  tmux_runtime_private_directory "$inbox"
  tmux_runtime_private_directory "$inbox/acked"
  if [ "$message_type" = heartbeat ]; then
    destination="$inbox/heartbeat.$sender.json"
  else
    destination="$inbox/$message_type.json"
  fi
  audit="$TMUX_RUNTIME_BUS_ROOT/outbox/main/$message_id.json"
  for existing in "$destination" "$audit"; do
    if [ -e "$existing" ]; then
      validate_envelope_file "$existing"
      if [ "$(jq -r '.message_id' "$existing")" != "$message_id" ]; then
        [ "$existing" = "$destination" ] && [ "$message_type" = heartbeat ] || fail "delivery destination is occupied: $existing"
        tmux_runtime_atomic_json "$existing" "$envelope"
      fi
    else
      tmux_runtime_atomic_json "$existing" "$envelope"
    fi
  done
  transaction=$(jq '.state = "committed" | .committed_at_ms = $now' --argjson now "$(tmux_runtime_now_ms)" <<<"$transaction")
  tmux_runtime_atomic_json "$transaction_path" "$transaction"
}

command_init() {
  local main_id="$1" main_session_id="$2" existing_capability="$3" registry
  tmux_runtime_valid_token "$main_id" || fail "invalid main id"
  tmux_runtime_valid_token "$main_session_id" || fail "invalid main session id"
  [ -e "$TMUX_RUNTIME_BUS_ROOT/registry.json" ] || fail 'bus is not provisioned'
  tmux_runtime_require_bus || fail 'bus is not provisioned'
  tmux_runtime_lock_acquire init 5000 30000
  registry=$(tmux_runtime_registry_read)
  jq -e --arg main "$main_id" '.main.agent_id == $main' <<<"$registry" >/dev/null || fail "existing registry belongs to another main session"
  tmux_runtime_principal_valid "$registry" "$main_id" "$main_session_id" orchestrator "$existing_capability" || fail 'orchestrator session and capability are required for an existing bus'
  read_routing_table "$registry" >/dev/null
  tmux_runtime_initialize_inbox "$main_id"
  tmux_runtime_lock_release init
  jq -n --arg state 'already_initialized' '{state: $state}'
}

command_routing_refresh() {
  local agent_id="$1" session_id="$2" capability="$3" registry
  tmux_runtime_require_bus
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  tmux_runtime_principal_valid "$registry" "$agent_id" "$session_id" orchestrator "$capability" || fail 'orchestrator session and capability are required to refresh routes'
  [ "$agent_id" = "$(jq -r '.main.agent_id' <<<"$registry")" ] || fail 'routing refresh requires the main orchestrator'
  write_routing_table "$registry"
  tmux_runtime_lock_release registry
}

command_publish() {
  local recipient="$1" agent_id="$2" session_id="$3" role="$4" capability="$5" message_type="$6" correlation_id="$7" payload="$8" publish_timeout_ms="$9" registry inbox message_id envelope transaction lock_name deadline now
  for value in "$recipient" "$agent_id" "$session_id" "$correlation_id"; do
    tmux_runtime_valid_token "$value" || fail "invalid message identifier"
  done
  case "$role" in orchestrator|agent) ;; *) fail "invalid sender role" ;; esac
  valid_message_type "$message_type" || fail "invalid message type"
  if [ "$role" = orchestrator ]; then
    case "$message_type" in job|shutdown_request|error) ;; *) fail "orchestrator cannot publish message type: $message_type" ;; esac
  else
    case "$message_type" in result|error|heartbeat|shutdown_response) ;; *) fail "agent cannot publish message type: $message_type" ;; esac
  fi
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$payload" || fail "payload must be a JSON object"
  [[ "$publish_timeout_ms" =~ ^[1-9][0-9]*$ ]] || fail "publish timeout must be milliseconds"
  registry=$(require_principal "$agent_id" "$session_id" "$role" "$capability" false)
  jq -e --arg recipient "$recipient" '.routes[$recipient].inbox == $recipient' <<<"$registry" >/dev/null || fail "no route for recipient: $recipient"
  inbox=$(tmux_runtime_inbox "$recipient")
  tmux_runtime_private_directory "$inbox"
  tmux_runtime_private_directory "$inbox/acked"
  message_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
  [[ "$message_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "cannot generate message identifier"
  envelope=$(envelope_document "$message_id" "$recipient" "$agent_id" "$session_id" "$role" "$message_type" "$correlation_id" "$payload")
  transaction=$(transaction_document "$message_id" "$envelope")
  lock_name="delivery.$recipient.$message_type"
  deadline=$(tmux_runtime_deadline_after "$publish_timeout_ms")
  while :; do
    tmux_runtime_deadline_expired "$deadline" && fail "timed out waiting for $message_type inbox slot: $recipient"
    now=$(tmux_runtime_deadline_remaining "$deadline")
    tmux_runtime_lock_acquire "$lock_name" "$now" 30000
    if [ "$message_type" = heartbeat ] || [ ! -e "$inbox/$message_type.json" ]; then
      break
    fi
    tmux_runtime_lock_release "$lock_name"
    sleep 0.01
  done
  tmux_runtime_atomic_json "$(transaction_path "$message_id")" "$transaction"
  printf '%s\n' "$message_id"
  deliver_transaction "$message_id"
  tmux_runtime_lock_release "$lock_name"
}

poll_messages() {
  local requester_id="$1" requested_sender="$2" types_csv="$3" registry inbox main_id type file first sender_filter
  tmux_runtime_valid_token "$requested_sender" || fail "invalid requested sender id"
  registry=$(tmux_runtime_registry_read)
  jq -e --arg id "$requester_id" '.routes[$id].inbox == $id' <<<"$registry" >/dev/null || fail "no route for authenticated principal: $requester_id"
  main_id=$(jq -r '.main.agent_id' <<<"$registry")
  sender_filter=''
  if [ "$requester_id" = "$main_id" ] && [ "$requested_sender" != "$main_id" ] && [[ ",$types_csv," == *,result,* || ",$types_csv," == *,error,* || ",$types_csv," == *,heartbeat,* || ",$types_csv," == *,shutdown_response,* ]]; then
    inbox=$(tmux_runtime_inbox "$main_id")
    sender_filter="$requested_sender"
  else
    [ "$requester_id" = "$requested_sender" ] || fail 'principal cannot read another agent inbox'
    inbox=$(tmux_runtime_inbox "$requester_id")
  fi
  tmux_runtime_private_directory "$inbox"
  first=true
  IFS=',' read -r -a types <<<"$types_csv"
  for type in "${types[@]}"; do
    valid_message_type "$type" || fail "invalid message type"
    if [ "$type" = heartbeat ]; then
      for file in "$inbox"/heartbeat.*.json; do
        [ -e "$file" ] || continue
        validate_envelope_file "$file"
        [ "$(jq -r '.to.agent_id' "$file")" = "$(basename "$inbox")" ] || fail "message recipient does not match inbox"
        [ -z "$sender_filter" ] || [ "$(jq -r '.from.agent_id' "$file")" = "$sender_filter" ] || continue
        [ "$first" = true ] || printf '\n'
        cat "$file"
        first=false
      done
      continue
    fi
    file="$inbox/$type.json"
    [ -e "$file" ] || continue
    validate_envelope_file "$file"
    [ "$(jq -r '.to.agent_id' "$file")" = "$(basename "$inbox")" ] || fail "message recipient does not match inbox"
    [ -z "$sender_filter" ] || [ "$(jq -r '.from.agent_id' "$file")" = "$sender_filter" ] || continue
    [ "$first" = true ] || printf '\n'
    cat "$file"
    first=false
  done
}

command_claim() {
  local agent_id="$1" session_id="$2" capability="$3" message_type="$4" lease_ms="$5" registry inbox message claim lock_name now owner role
  for value in "$agent_id" "$session_id"; do tmux_runtime_valid_token "$value" || fail "invalid claim identifier"; done
  valid_message_type "$message_type" || fail "invalid message type"
  [[ "$lease_ms" =~ ^[1-9][0-9]*$ ]] || fail "claim lease must be milliseconds"
  role=agent
  tmux_runtime_require_bus
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  [ "$agent_id" != "$(jq -r '.main.agent_id' <<<"$registry")" ] || role=orchestrator
  tmux_runtime_principal_valid "$registry" "$agent_id" "$session_id" "$role" "$capability" || fail "sender capability does not match a registered principal"
  read_routing_table "$registry" >/dev/null
  tmux_runtime_lock_release registry
  inbox=$(tmux_runtime_inbox "$agent_id")
  message="$inbox/$message_type.json"
  claim="$TMUX_RUNTIME_BUS_ROOT/claims/$agent_id.$message_type.claim"
  lock_name="delivery.$agent_id.$message_type"
  tmux_runtime_lock_acquire "$lock_name" 5000 30000
  [ -e "$message" ] || fail "message is unavailable for claim"
  validate_envelope_file "$message"
  if [ -e "$claim" ]; then
    tmux_runtime_existing_private_directory "$claim"
    tmux_runtime_private_file "$claim/owner.json"
    if ! tmux_runtime_lock_recoverable "$claim" owner.json; then
      tmux_runtime_lock_release "$lock_name"
      fail "agent inbox is already claimed: $agent_id"
    fi
  fi
  now=$(tmux_runtime_deadline_now_ms)
  owner=$(jq -n --arg message_id "$(jq -r '.message_id' "$message")" --arg agent "$agent_id" --arg session "$session_id" --argjson pid "$$" --argjson acquired "$now" --argjson lease "$lease_ms" '{message_id: $message_id, agent_id: $agent, session_id: $session, pid: $pid, acquired_at_ms: $acquired, lease_ms: $lease}')
  python3 "$TMUX_RUNTIME_HELPER" publish-directory --root "$TMUX_RUNTIME_BUS_ROOT" --relative "claims/$agent_id.$message_type.claim" --document "$owner" || fail "cannot publish inbox claim"
  cat "$message"
  tmux_runtime_lock_release "$lock_name"
}

command_ack() {
  local agent_id="$1" session_id="$2" capability="$3" message_id="$4" registry inbox type file claim claim_data lock_name role
  tmux_runtime_valid_token "$agent_id" || fail "invalid agent id"
  tmux_runtime_valid_token "$session_id" || fail "invalid session id"
  [[ "$message_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "invalid message id"
  tmux_runtime_require_bus
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  role=agent
  [ "$agent_id" != "$(jq -r '.main.agent_id' <<<"$registry")" ] || role=orchestrator
  tmux_runtime_principal_valid "$registry" "$agent_id" "$session_id" "$role" "$capability" || fail "sender capability does not match a registered principal"
  read_routing_table "$registry" >/dev/null
  tmux_runtime_lock_release registry
  inbox=$(tmux_runtime_inbox "$agent_id")
  if [ -e "$inbox/acked/$message_id.json" ]; then
    tmux_runtime_private_file "$inbox/acked/$message_id.json"
    for type in $MESSAGE_TYPES; do
      file="$inbox/$type.json"
      [ -e "$file" ] || continue
      validate_envelope_file "$file"
      [ "$(jq -r '.message_id' "$file")" = "$message_id" ] || continue
      lock_name="delivery.$agent_id.$type"
      tmux_runtime_lock_acquire "$lock_name" 5000 30000
      python3 "$TMUX_RUNTIME_HELPER" complete-ack --root "$TMUX_RUNTIME_BUS_ROOT" --source "inboxes/$agent_id/$type.json" --destination "inboxes/$agent_id/acked/$message_id.json" || fail "cannot recover acknowledgement message"
      tmux_runtime_lock_release "$lock_name"
      break
    done
    for type in $MESSAGE_TYPES; do
      claim="$TMUX_RUNTIME_BUS_ROOT/claims/$agent_id.$type.claim"
      [ -e "$claim" ] || continue
      tmux_runtime_existing_private_directory "$claim"
      tmux_runtime_private_file "$claim/owner.json"
      claim_data=$(cat "$claim/owner.json")
      jq -e --arg message "$message_id" --arg agent "$agent_id" --arg session "$session_id" '.message_id == $message and .agent_id == $agent and .session_id == $session' <<<"$claim_data" >/dev/null || continue
      rm -f "$claim/owner.json"
      rmdir "$claim" || fail "cannot release recovered claim"
    done
    printf '%s\n' "$message_id"
    return 0
  fi
  for type in $MESSAGE_TYPES; do
    file="$inbox/$type.json"
    [ -e "$file" ] || continue
    lock_name="delivery.$agent_id.$type"
    tmux_runtime_lock_acquire "$lock_name" 5000 30000
    validate_envelope_file "$file"
    [ "$(jq -r '.message_id' "$file")" = "$message_id" ] || { tmux_runtime_lock_release "$lock_name"; continue; }
    claim="$TMUX_RUNTIME_BUS_ROOT/claims/$agent_id.$type.claim"
    tmux_runtime_existing_private_directory "$claim"
    tmux_runtime_private_file "$claim/owner.json"
    claim_data=$(cat "$claim/owner.json")
    jq -e --arg message "$message_id" --arg agent "$agent_id" --arg session "$session_id" '.message_id == $message and .agent_id == $agent and .session_id == $session and (.pid | type == "number") and (.acquired_at_ms | type == "number") and (.lease_ms | type == "number" and . > 0)' <<<"$claim_data" >/dev/null || fail "agent claim is malformed: $agent_id"
    tmux_runtime_private_directory "$inbox/acked"
    [ ! -L "$inbox/acked" ] || fail "symbolic link is not permitted at acknowledgement"
    python3 "$TMUX_RUNTIME_HELPER" complete-ack --root "$TMUX_RUNTIME_BUS_ROOT" --source "inboxes/$agent_id/$type.json" --destination "inboxes/$agent_id/acked/$message_id.json" || fail "cannot acknowledge message"
    tmux_runtime_private_file "$inbox/acked/$message_id.json"
    rm -f "$claim/owner.json"
    rmdir "$claim" || fail "cannot release claim"
    tmux_runtime_lock_release "$lock_name"
    printf '%s\n' "$message_id"
    return 0
  done
  fail "message is not available for acknowledgement: $message_id"
}

command_await() {
  local requester_id="$1" session_id="$2" role="$3" capability="$4" requested_sender="$5" types="$6" timeout_ms="$7" deadline output registry
  [[ "$timeout_ms" =~ ^[1-9][0-9]*$ ]] || fail "timeout must be a positive number of milliseconds"
  registry=$(require_principal "$requester_id" "$session_id" "$role" "$capability" false)
  deadline=$(tmux_runtime_deadline_after "$timeout_ms")
  while :; do
    output=$(poll_messages "$requester_id" "$requested_sender" "$types")
    [ -z "$output" ] || { printf '%s\n' "$output"; return 0; }
    tmux_runtime_deadline_expired "$deadline" && fail "timed out awaiting message from $requested_sender"
    sleep 0.005
  done
}

command_heartbeat() {
  local agent_id="$1" session_id="$2" capability="$3" state="$4" registry updated main_id heartbeat_lock current_state
  case "$state" in registered|running|idle|failed|shutdown) ;; *) fail "invalid agent state" ;; esac
  tmux_runtime_require_bus
  heartbeat_lock="heartbeat.$agent_id"
  tmux_runtime_lock_acquire "$heartbeat_lock" 5000 30000
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  tmux_runtime_principal_valid "$registry" "$agent_id" "$session_id" agent "$capability" || fail "sender capability does not match a registered principal"
  read_routing_table "$registry" >/dev/null
  current_state=$(jq -r --arg id "$agent_id" '.agents[] | select(.agent_id == $id) | .state' <<<"$registry")
  case "$current_state" in
    registered|running|idle) ;;
    failed|shutdown) fail "agent is in a terminal lifecycle state: $agent_id" ;;
    *) fail "agent lifecycle state is malformed: $agent_id" ;;
  esac
  main_id=$(jq -r '.main.agent_id' <<<"$registry")
  updated=$(jq --arg id "$agent_id" --arg state "$state" --argjson now "$(tmux_runtime_now_ms)" '.agents |= map(if .agent_id == $id then .state = $state | .heartbeat_at_ms = $now else . end)' <<<"$registry")
  tmux_runtime_registry_write "$updated"
  tmux_runtime_lock_release registry
  command_publish "$main_id" "$agent_id" "$session_id" agent "$capability" heartbeat heartbeat "$(jq -n --arg state "$state" '{state: $state}')" 5000 >/dev/null
  tmux_runtime_lock_release "$heartbeat_lock"
}

command_stale() {
  local requester_id="$1" session_id="$2" role="$3" capability="$4" agent_id="$5" threshold_ms="$6" registry heartbeat now
  tmux_runtime_valid_token "$agent_id" || fail "invalid agent id"
  [[ "$threshold_ms" =~ ^[1-9][0-9]*$ ]] || fail "stale threshold must be milliseconds"
  registry=$(require_principal "$requester_id" "$session_id" "$role" "$capability" true)
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  read_routing_table "$registry" >/dev/null
  heartbeat=$(jq -r --arg id "$agent_id" '.agents[] | select(.agent_id == $id) | .heartbeat_at_ms' <<<"$registry")
  tmux_runtime_lock_release registry
  [[ "$heartbeat" =~ ^[0-9]+$ ]] || fail "agent has no heartbeat: $agent_id"
  now=$(tmux_runtime_now_ms)
  if [ "$now" -ge $((heartbeat + threshold_ms)) ]; then
    printf 'stale: %s\n' "$agent_id"
    return 1
  fi
  printf 'fresh: %s\n' "$agent_id"
}

command_recover() {
  local agent_id="$1" session_id="$2" capability="$3" message_id="$4" lock_name registry
  [[ "$message_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || fail "invalid message id"
  registry=$(require_principal "$agent_id" "$session_id" orchestrator "$capability" true)
  lock_name="recovery.$message_id"
  tmux_runtime_lock_acquire "$lock_name" 5000 30000
  deliver_transaction "$message_id"
  tmux_runtime_lock_release "$lock_name"
  printf '%s\n' "$message_id"
}

compact_directory() {
  local directory="$1" retain="$2" name count=0
  [ -d "$directory" ] || return 0
  tmux_runtime_private_directory "$directory"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    tmux_runtime_private_file "$directory/$name"
    count=$((count + 1))
    [ "$count" -le "$retain" ] || rm -f "$directory/$name" || fail "cannot compact retained message: $directory/$name"
  done < <(python3 "$TMUX_RUNTIME_HELPER" list-json --path "$directory")
}

command_compact() {
  local requester_id="$1" session_id="$2" capability="$3" retain="$4" registry agent_id
  [[ "$retain" =~ ^[0-9]+$ ]] || fail "retain must be a non-negative integer"
  registry=$(require_principal "$requester_id" "$session_id" orchestrator "$capability" true)
  tmux_runtime_lock_acquire retention 5000 30000
  registry=$(tmux_runtime_registry_read)
  read_routing_table "$registry" >/dev/null
  compact_directory "$TMUX_RUNTIME_BUS_ROOT/outbox/main" "$retain"
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    compact_directory "$(tmux_runtime_inbox "$agent_id")/acked" "$retain"
  done < <(jq -r '.routes | keys[]' <<<"$registry")
  tmux_runtime_lock_release retention
}

command_bind() {
  local agent_id="$1" session_id="$2" capability="$3" contract_id="$4" registry updated
  for value in "$agent_id" "$session_id" "$contract_id"; do
    tmux_runtime_valid_token "$value" || fail 'invalid bind identifier'
  done
  tmux_runtime_require_bus
  tmux_runtime_lock_acquire registry 5000 30000
  registry=$(tmux_runtime_registry_read)
  read_routing_table "$registry" >/dev/null
  jq -e --arg agent "$agent_id" --arg contract "$contract_id" --arg capability "$(tmux_runtime_capability_hash "$capability")" 'any(.agents[]; .agent_id == $agent and .contract_id == $contract and .claude_session_id == null and .capability_hash == $capability and .state != "shutdown")' <<<"$registry" >/dev/null || fail 'bind is invalid or already consumed'
  updated=$(jq --arg agent "$agent_id" --arg session "$session_id" '.agents |= map(if .agent_id == $agent then .claude_session_id = $session else . end)' <<<"$registry")
  tmux_runtime_write_registry_route_bundle "$updated" || fail 'cannot publish bound agent routing'
  tmux_runtime_lock_release registry
}

usage() {
  printf '%s\n' 'Usage: tmux-bus.sh --control-root PATH <init|bind|routing-refresh|publish|poll|claim|ack|await|heartbeat|stale|recover|compact> [options]' >&2
  exit 2
}

main() {
  local control_root command
  require_tools
  [ "$#" -ge 3 ] || usage
  [ "$1" = '--control-root' ] || usage
  control_root="$2"
  command="$3"
  shift 3
  tmux_runtime_configure "$control_root"
  trap tmux_runtime_cleanup_locks EXIT
  case "$command" in
    init) if [ "$#" -eq 4 ] && [ "$1" = '--main-id' ] && [ "$3" = '--main-session-id' ]; then command_init "$2" "$4" ''; elif [ "$#" -eq 6 ] && [ "$1" = '--main-id' ] && [ "$3" = '--main-session-id' ] && [ "$5" = '--orchestrator-capability' ]; then command_init "$2" "$4" "$6"; else usage; fi ;;
    bind) [ "$#" -eq 8 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--capability' ] && [ "$7" = '--contract-id' ] || usage; command_bind "$2" "$4" "$6" "$8" ;;
    routing-refresh) [ "$#" -eq 6 ] && [ "$1" = '--orchestrator-id' ] && [ "$3" = '--orchestrator-session-id' ] && [ "$5" = '--orchestrator-capability' ] || usage; command_routing_refresh "$2" "$4" "$6" ;;
    publish) if [ "$#" -eq 16 ] && [ "$1" = '--to' ] && [ "$3" = '--from-agent-id' ] && [ "$5" = '--from-session-id' ] && [ "$7" = '--from-role' ] && [ "$9" = '--capability' ] && [ "${11}" = '--type' ] && [ "${13}" = '--correlation-id' ] && [ "${15}" = '--payload' ]; then command_publish "$2" "$4" "$6" "$8" "${10}" "${12}" "${14}" "${16}" 5000; elif [ "$#" -eq 18 ] && [ "${17}" = '--timeout-ms' ]; then command_publish "$2" "$4" "$6" "$8" "${10}" "${12}" "${14}" "${16}" "${18}"; else usage; fi ;;
    poll) [ "$#" -eq 12 ] && [ "$1" = '--from' ] && [ "$3" = '--agent-id' ] && [ "$5" = '--session-id' ] && [ "$7" = '--role' ] && [ "$9" = '--capability' ] && [ "${11}" = '--types' ] || usage; require_principal "$4" "$6" "$8" "${10}" false >/dev/null; poll_messages "$4" "$2" "${12}" ;;
    claim) [ "$#" -eq 10 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--capability' ] && [ "$7" = '--type' ] && [ "$9" = '--lease-ms' ] || usage; command_claim "$2" "$4" "$6" "$8" "${10}" ;;
    ack) [ "$#" -eq 8 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--capability' ] && [ "$7" = '--message-id' ] || usage; command_ack "$2" "$4" "$6" "$8" ;;
    await) [ "$#" -eq 14 ] && [ "$1" = '--from' ] && [ "$3" = '--agent-id' ] && [ "$5" = '--session-id' ] && [ "$7" = '--role' ] && [ "$9" = '--capability' ] && [ "${11}" = '--types' ] && [ "${13}" = '--timeout-ms' ] || usage; command_await "$4" "$6" "$8" "${10}" "$2" "${12}" "${14}" ;;
    heartbeat) if [ "$#" -eq 8 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--capability' ] && [ "$7" = '--state' ]; then command_heartbeat "$2" "$4" "$6" "$8"; elif [ "$#" -eq 7 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--capability-stdin' ] && [ "$6" = '--state' ]; then IFS= read -r capability || fail 'heartbeat capability input is unavailable'; command_heartbeat "$2" "$4" "$capability" "$7"; else usage; fi ;;
    stale) [ "$#" -eq 12 ] && [ "$1" = '--agent-id' ] && [ "$3" = '--session-id' ] && [ "$5" = '--role' ] && [ "$7" = '--capability' ] && [ "$9" = '--subject-agent-id' ] && [ "${11}" = '--threshold-ms' ] || usage; command_stale "$2" "$4" "$6" "$8" "${10}" "${12}" ;;
    recover) [ "$#" -eq 8 ] && [ "$1" = '--orchestrator-id' ] && [ "$3" = '--orchestrator-session-id' ] && [ "$5" = '--orchestrator-capability' ] && [ "$7" = '--message-id' ] || usage; command_recover "$2" "$4" "$6" "$8" ;;
    compact) [ "$#" -eq 8 ] && [ "$1" = '--orchestrator-id' ] && [ "$3" = '--orchestrator-session-id' ] && [ "$5" = '--orchestrator-capability' ] && [ "$7" = '--retain' ] || usage; command_compact "$2" "$4" "$6" "$8" ;;
    *) usage ;;
  esac
}

main "$@"
