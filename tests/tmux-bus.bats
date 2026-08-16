#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SCRIPT="$REPO_ROOT/scripts/tmux-bus.sh"
  TEST_ROOT="$(mktemp -d)"
  PROJECT_ROOT="$TEST_ROOT/project"
  CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
  mkdir -p "$CONTROL_ROOT"
  printf '%s\n' '{}' > "$CONTROL_ROOT/config.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_bus() {
  run bash "$SCRIPT" --control-root "$CONTROL_ROOT" "$@"
}

source_runtime() {
  source "$REPO_ROOT/scripts/lib/lbwc-control-root.sh"
  source "$REPO_ROOT/scripts/lib/tmux-runtime.sh"
  tmux_runtime_configure "$CONTROL_ROOT"
}

ensure_bus_layout() {
  tmux_runtime_ensure
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/inboxes"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox/main"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/transactions"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/claims"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/credentials"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/heartbeats"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/locks"
}

fixture_bus() {
  local hash registry
  source_runtime
  ensure_bus_layout
  MAIN_CAPABILITY=$(tmux_runtime_capability)
  hash=$(tmux_runtime_capability_hash "$MAIN_CAPABILITY")
  registry=$(jq -n --arg main main-session --arg hash "$hash" '{
    schema_version: 2,
    main: {agent_id: $main, session_id: $main, role: "orchestrator", capability_hash: $hash},
    tmux: {session: null, orchestrator_target: null, orchestrator_pane: null, topology: "pending", managed_session: false, ownership_token: null},
    agents: [],
    routes: {($main): {inbox: $main, tmux_target: null}}
  }')
  tmux_runtime_write_registry_route_bundle "$registry"
  tmux_runtime_initialize_inbox main-session
}

plant_agent() {
  local agent_id="$1" session_id="$2" hash registry updated
  AGENT_CAPABILITY=$(tmux_runtime_capability)
  hash=$(tmux_runtime_capability_hash "$AGENT_CAPABILITY")
  registry=$(tmux_runtime_registry_read)
  updated=$(jq --arg id "$agent_id" --arg session "$session_id" --arg hash "$hash" '
    .agents += [{
      agent_id: $id,
      parent_id: .main.agent_id,
      contract_id: "contract-1",
      generated_name: $id,
      tmux_target: "lbwc-test-main:0.1",
      tmux_pane_id: null,
      claude_session_id: $session,
      capability_hash: $hash,
      state: "registered",
      heartbeat_at_ms: null
    }]
    | .routes[$id] = {inbox: $id, tmux_target: "lbwc-test-main:0.1"}
  ' <<<"$registry")
  tmux_runtime_write_registry_route_bundle "$updated"
  tmux_runtime_initialize_inbox "$agent_id"
}

publish_main_job() {
  local recipient="$1"
  shift
  run_bus publish --to "$recipient" --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type job --correlation-id contract-1 --payload '{"brief":"work"}' "$@"
}

@test "releasing one lock leaves the remaining acquired name" {
  source_runtime
  ensure_bus_layout
  tmux_runtime_lock_acquire first 5000 30000
  tmux_runtime_lock_acquire second 5000 30000
  [ "${#TMUX_RUNTIME_LOCKS[@]}" -eq 2 ]
  tmux_runtime_lock_release first
  [ "${#TMUX_RUNTIME_LOCKS[@]}" -eq 1 ]
  [ "${TMUX_RUNTIME_LOCKS[0]}" = second ]
  tmux_runtime_lock_release second
}

@test "fixture creates one private registry with a main inbox and route" {
  fixture_bus
  helper="$REPO_ROOT/scripts/lib/tmux-private-fs.py"

  run python3 "$helper" check-directory --path "$CONTROL_ROOT/.runtime/tmux-bus"
  [ "$status" -eq 0 ]
  run python3 "$helper" check-file --path "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 2 and .main.agent_id == "main-session" and .routes["main-session"].inbox == "main-session" and .agents == []' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  [ -d "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/main-session/acked" ]
}

@test "init refuses to mint a registry without provision" {
  run_bus init --main-id main-session --main-session-id main-session
  [ "$status" -ne 0 ]
  [[ "$output" == *"bus is not provisioned"* ]]
  [ ! -e "$CONTROL_ROOT/.runtime/tmux-bus/registry.json" ]
}

@test "existing initialization requires the main capability" {
  fixture_bus
  run_bus init --main-id main-session --main-session-id main-session
  [ "$status" -ne 0 ]
  [[ "$output" == *"session and capability"* ]]

  run_bus init --main-id main-session --main-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY"
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 2 and .main.agent_id == "main-session" and .routes["main-session"].inbox == "main-session"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

@test "malformed registry fails closed without rewriting live files" {
  local runtime_bus
  fixture_bus
  runtime_bus="$CONTROL_ROOT/.runtime/tmux-bus"
  cp "$runtime_bus/registry.json" "$TEST_ROOT/registry-before.json"
  cp "$runtime_bus/routing-table.json" "$TEST_ROOT/routing-before.json"
  printf '%s\n' '{not valid json' > "$runtime_bus/registry.json"
  chmod 600 "$runtime_bus/registry.json"

  run_bus routing-refresh --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY"

  [ "$status" -ne 0 ]
  [ "$(cat "$runtime_bus/registry.json")" = '{not valid json' ]
  cmp "$TEST_ROOT/routing-before.json" "$runtime_bus/routing-table.json"
}

@test "registered principals require their own capability and deliver replies to main" {
  fixture_bus
  plant_agent agent-a child-session-a

  run_bus publish --to main-session --from-agent-id agent-a --from-session-id child-session-a --from-role agent --capability "$AGENT_CAPABILITY" --type result --correlation-id contract-1 --payload '{"result":"done"}'
  [ "$status" -eq 0 ]
  result_id="$output"
  run jq -e --arg message_id "$result_id" '.message_id == $message_id and .from.agent_id == "agent-a" and .to.agent_id == "main-session"' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/main-session/result.json"
  [ "$status" -eq 0 ]

  run_bus publish --to main-session --from-agent-id agent-a --from-session-id child-session-a --from-role agent --capability "$MAIN_CAPABILITY" --type shutdown_response --correlation-id contract-1 --payload '{}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"principal session, role, or capability"* ]]
}

@test "main consumes a sender result through the main inbox" {
  fixture_bus
  plant_agent agent-a child-session-a
  run_bus publish --to main-session --from-agent-id agent-a --from-session-id child-session-a --from-role agent --capability "$AGENT_CAPABILITY" --type result --correlation-id contract-1 --payload '{"result":"done"}'
  [ "$status" -eq 0 ]
  result_id="$output"
  run_bus poll --from agent-a --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --types result
  [ "$status" -eq 0 ]
  [ "$(jq -r '.message_id' <<<"$output")" = "$result_id" ]
  run_bus claim --agent-id main-session --session-id main-session --capability "$MAIN_CAPABILITY" --type result --lease-ms 1000
  [ "$status" -eq 0 ]
  run_bus ack --agent-id main-session --session-id main-session --capability "$MAIN_CAPABILITY" --message-id "$result_id"
  [ "$status" -eq 0 ]
}

@test "publish records a recoverable transaction before delivery and audit" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"

  run jq -e --arg message_id "$message_id" '.message_id == $message_id and .state == "committed"' "$CONTROL_ROOT/.runtime/tmux-bus/transactions/$message_id.json"
  [ "$status" -eq 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/outbox/main/$message_id.json" ]
}

@test "recover completes a prepared delivery transaction idempotently" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"
  rm "$CONTROL_ROOT/.runtime/tmux-bus/outbox/main/$message_id.json"
  jq '.state = "prepared"' "$CONTROL_ROOT/.runtime/tmux-bus/transactions/$message_id.json" > "$TEST_ROOT/transaction.json"
  chmod 600 "$TEST_ROOT/transaction.json"
  mv "$TEST_ROOT/transaction.json" "$CONTROL_ROOT/.runtime/tmux-bus/transactions/$message_id.json"

  run_bus recover --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --message-id "$message_id"
  [ "$status" -eq 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/outbox/main/$message_id.json" ]
  run_bus recover --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --message-id "$message_id"
  [ "$status" -eq 0 ]

  jq 'del(.envelope.from.session_id)' "$CONTROL_ROOT/.runtime/tmux-bus/transactions/$message_id.json" > "$TEST_ROOT/transaction.json"
  chmod 600 "$TEST_ROOT/transaction.json"
  mv "$TEST_ROOT/transaction.json" "$CONTROL_ROOT/.runtime/tmux-bus/transactions/$message_id.json"
  run_bus recover --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --message-id "$message_id"
  [ "$status" -ne 0 ]
  [[ "$output" == *"envelope is malformed"* ]]
}

@test "same inbox concurrent publish serializes without corrupting envelopes" {
  fixture_bus
  plant_agent agent-a child-session-a

  run env CONTROL_ROOT="$CONTROL_ROOT" SCRIPT="$SCRIPT" MAIN_CAPABILITY="$MAIN_CAPABILITY" bash -c '
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" publish --to agent-a --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type job --correlation-id one --payload "{\"brief\":\"one\",\"n\":1}" &
    first=$!
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" publish --to agent-a --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type job --correlation-id two --payload "{\"brief\":\"two\",\"n\":2}" &
    second=$!
    wait "$first"; first_status=$?
    wait "$second"; second_status=$?
    { [ "$first_status" -eq 0 ] && [ "$second_status" -ne 0 ]; } || { [ "$first_status" -ne 0 ] && [ "$second_status" -eq 0 ]; }
  '
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 1 and (.body.n | IN(1, 2))' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json"
  [ "$status" -eq 0 ]
}

@test "publish waits for acknowledgement backpressure or times out" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  first_id="$output"
  run_bus claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000
  [ "$status" -eq 0 ]
  env SCRIPT="$SCRIPT" CONTROL_ROOT="$CONTROL_ROOT" CAPABILITY="$AGENT_CAPABILITY" MESSAGE_ID="$first_id" bash -c 'sleep 0.05; bash "$SCRIPT" --control-root "$CONTROL_ROOT" ack --agent-id agent-a --session-id child-session-a --capability "$CAPABILITY" --message-id "$MESSAGE_ID" >/dev/null' &
  publish_main_job agent-a --timeout-ms 1000
  [ "$status" -eq 0 ]
  wait "$!"

  run_bus publish --to agent-a --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type job --correlation-id blocked --payload '{}' --timeout-ms 30
  [ "$status" -ne 0 ]
  [[ "$output" == *"timed out waiting"* ]]
}

@test "same inbox concurrent claim gives one lease and acknowledgement releases it" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"

  run env CONTROL_ROOT="$CONTROL_ROOT" SCRIPT="$SCRIPT" AGENT_CAPABILITY="$AGENT_CAPABILITY" bash -c '
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000 >/dev/null &
    first=$!
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000 >/dev/null &
    second=$!
    wait "$first"; first_status=$?
    wait "$second"; second_status=$?
    { [ "$first_status" -eq 0 ] && [ "$second_status" -ne 0 ]; } || { [ "$first_status" -ne 0 ] && [ "$second_status" -eq 0 ]; }
  '
  [ "$status" -eq 0 ]

  run_bus ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -eq 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/acked/$message_id.json" ]
  [ ! -e "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.job.claim" ]
}

@test "expired dead-owner claims are reclaimed and malformed claim state fails before acknowledgement" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"
  claim="$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.job.claim"
  mkdir "$claim"
  chmod 700 "$claim"
  printf '%s\n' "{\"message_id\":\"$message_id\",\"agent_id\":\"agent-a\",\"session_id\":\"child-session-a\",\"pid\":99999999,\"acquired_at_ms\":1,\"lease_ms\":1}" > "$claim/owner.json"
  chmod 600 "$claim/owner.json"

  run_bus claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000
  [ "$status" -eq 0 ]

  printf '%s\n' '{bad json' > "$claim/owner.json"
  run_bus ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -ne 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" ]
}

@test "ack rejects a symlinked acknowledgement directory before moving a message" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"
  run_bus claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000
  [ "$status" -eq 0 ]
  rm -rf "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/acked"
  mkdir "$TEST_ROOT/outside"
  ln -s "$TEST_ROOT/outside" "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/acked"

  run_bus ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -ne 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" ]
  [ ! -e "$TEST_ROOT/outside/$message_id.json" ]
}

@test "a symlinked inbox cannot redirect a delivered message" {
  fixture_bus
  plant_agent agent-a child-session-a
  rm -rf "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a"
  mkdir "$TEST_ROOT/outside"
  ln -s "$TEST_ROOT/outside" "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a"

  publish_main_job agent-a

  [ "$status" -ne 0 ]
  [ ! -e "$TEST_ROOT/outside/job.json" ]
}

@test "await honors millisecond timeouts and rejects unsafe or malformed state" {
  fixture_bus
  plant_agent agent-a child-session-a
  start_ms="$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')"
  run_bus await --from agent-a --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --types result --timeout-ms 30
  end_ms="$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')"
  [ "$status" -eq 1 ]
  [ $((end_ms - start_ms)) -lt 1000 ]

  chmod 644 "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  run_bus poll --from agent-a --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --types result
  [ "$status" -ne 0 ]
  [[ "$output" == *"private file"* ]]
}

@test "heartbeat updates the locked registry and stale reads one validated capture" {
  fixture_bus
  plant_agent agent-a child-session-a

  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --state idle
  [ "$status" -eq 0 ]
  run jq -e '.agents[0].state == "idle" and (.agents[0].heartbeat_at_ms | type == "number")' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -e '.from.agent_id == "agent-a" and .to.agent_id == "main-session" and .type == "heartbeat" and .body.state == "idle"' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/main-session/heartbeat.agent-a.json"
  [ "$status" -eq 0 ]
  run_bus stale --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --subject-agent-id agent-a --threshold-ms 10000
  [ "$status" -eq 0 ]
  jq '.agents[0].heartbeat_at_ms = 1' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json" > "$TEST_ROOT/registry.json"
  chmod 600 "$TEST_ROOT/registry.json"
  mv "$TEST_ROOT/registry.json" "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  run_bus stale --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --subject-agent-id agent-a --threshold-ms 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "heartbeat refuses to resurrect watchdog-failed agents" {
  fixture_bus
  plant_agent agent-a child-session-a
  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --state running
  [ "$status" -eq 0 ]
  jq '.agents[0].state = "failed"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json" > "$TEST_ROOT/registry.json"
  chmod 600 "$TEST_ROOT/registry.json"
  mv "$TEST_ROOT/registry.json" "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"

  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --state running

  [ "$status" -ne 0 ]
  [[ "$output" == *"terminal lifecycle state"* ]]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "failed"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

@test "heartbeat shutdown drops the agent route and keeps the registry valid" {
  fixture_bus
  plant_agent agent-a child-session-a

  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --state shutdown

  [ "$status" -eq 0 ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -e '.routes | keys | sort == ["main-session"]' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -e '.routes | keys | sort == ["main-session"]' "$CONTROL_ROOT/.runtime/tmux-bus/routing-table.json"
  [ "$status" -eq 0 ]
}

@test "persisted record times use epoch milliseconds after a simulated reboot" {
  fixture_bus
  plant_agent agent-a child-session-a
  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --state idle
  [ "$status" -eq 0 ]
  run jq -e '.agents[0].heartbeat_at_ms > 1000000000000' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]

  jq '.agents[0].heartbeat_at_ms = 1' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json" > "$TEST_ROOT/registry.json"
  chmod 600 "$TEST_ROOT/registry.json"
  mv "$TEST_ROOT/registry.json" "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  run_bus stale --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --subject-agent-id agent-a --threshold-ms 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"stale"* ]]
}

@test "descriptor-relative acknowledgement move never clobbers a concurrent destination" {
  fixture_bus
  plant_agent agent-a child-session-a
  helper="$REPO_ROOT/scripts/lib/tmux-private-fs.py"
  root="$CONTROL_ROOT/.runtime/tmux-bus"
  printf '%s\n' '{"source":"one"}' > "$root/inboxes/agent-a/job.json"
  chmod 600 "$root/inboxes/agent-a/job.json"
  printf '%s\n' '{"source":"two"}' > "$root/inboxes/agent-a/result.json"
  chmod 600 "$root/inboxes/agent-a/result.json"

  run env ROOT="$root" HELPER="$helper" bash -c '
    python3 "$HELPER" move --root "$ROOT" --source inboxes/agent-a/job.json --destination inboxes/agent-a/acked/race.json &
    first=$!
    python3 "$HELPER" move --root "$ROOT" --source inboxes/agent-a/result.json --destination inboxes/agent-a/acked/race.json &
    second=$!
    wait "$first"; first_status=$?
    wait "$second"; second_status=$?
    { [ "$first_status" -eq 0 ] && [ "$second_status" -ne 0 ]; } || { [ "$first_status" -ne 0 ] && [ "$second_status" -eq 0 ]; }
  '
  [ "$status" -eq 0 ]
  [ -f "$root/inboxes/agent-a/acked/race.json" ]
  [ -e "$root/inboxes/agent-a/job.json" ] || [ -e "$root/inboxes/agent-a/result.json" ]
}

@test "ack resumes both-name and orphan-claim interruption states" {
  fixture_bus
  plant_agent agent-a child-session-a
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  message_id="$output"
  run_bus claim --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --type job --lease-ms 1000
  [ "$status" -eq 0 ]

  run env LBWC_TMUX_FS_FAIL_AFTER_ACK_LINK=1 bash "$SCRIPT" --control-root "$CONTROL_ROOT" ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -ne 0 ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" ]
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/acked/$message_id.json" ]

  run_bus ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -eq 0 ]
  [ ! -e "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" ]
  [ ! -e "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.job.claim" ]

  mkdir "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.result.claim"
  chmod 700 "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.result.claim"
  printf '%s\n' "{\"message_id\":\"$message_id\",\"agent_id\":\"agent-a\",\"session_id\":\"child-session-a\"}" > "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.result.claim/owner.json"
  chmod 600 "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.result.claim/owner.json"

  run_bus ack --agent-id agent-a --session-id child-session-a --capability "$AGENT_CAPABILITY" --message-id "$message_id"
  [ "$status" -eq 0 ]
  [ ! -e "$CONTROL_ROOT/.runtime/tmux-bus/claims/agent-a.result.claim" ]
}

@test "read and global maintenance operations reject unauthenticated principals" {
  fixture_bus
  plant_agent agent-a child-session-a

  run_bus poll --from agent-a --types result
  [ "$status" -ne 0 ]
  run_bus stale --agent-id agent-a --session-id child-session-a --role agent --capability "$AGENT_CAPABILITY" --subject-agent-id agent-a --threshold-ms 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"principal session, role, or capability"* || "$output" == *"main orchestrator"* ]]
  run_bus compact --orchestrator-id agent-a --orchestrator-session-id child-session-a --orchestrator-capability "$AGENT_CAPABILITY" --retain 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"principal session, role, or capability"* || "$output" == *"main orchestrator"* ]]
}

@test "main reads only the requested agent heartbeat from its inbox" {
  fixture_bus
  plant_agent agent-a child-session-a
  agent_a_capability="$AGENT_CAPABILITY"
  plant_agent agent-b child-session-b
  agent_b_capability="$AGENT_CAPABILITY"
  run_bus heartbeat --agent-id agent-a --session-id child-session-a --capability "$agent_a_capability" --state idle
  [ "$status" -eq 0 ]
  run_bus heartbeat --agent-id agent-b --session-id child-session-b --capability "$agent_b_capability" --state running
  [ "$status" -eq 0 ]

  run_bus poll --from agent-a --agent-id main-session --session-id main-session --role orchestrator --capability "$MAIN_CAPABILITY" --types heartbeat
  [ "$status" -eq 0 ]
  run jq -e '.from.agent_id == "agent-a" and .to.agent_id == "main-session" and .type == "heartbeat"' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "persisted envelopes require sent_at and type-specific bodies" {
  fixture_bus
  plant_agent agent-a child-session-a
  run_bus publish --to agent-a --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type job --correlation-id invalid-body --payload '{}'
  [ "$status" -ne 0 ]

  publish_main_job agent-a
  [ "$status" -eq 0 ]
  jq 'del(.sent_at)' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" > "$TEST_ROOT/message.json"
  chmod 600 "$TEST_ROOT/message.json"
  mv "$TEST_ROOT/message.json" "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json"
  run_bus poll --from agent-a --agent-id agent-a --session-id child-session-a --role agent --capability "$AGENT_CAPABILITY" --types job
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed message"* ]]

  rm "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json"
  publish_main_job agent-a
  [ "$status" -eq 0 ]
  jq '.sent_at = "2026-02-30T12:00:00Z"' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json" > "$TEST_ROOT/message.json"
  chmod 600 "$TEST_ROOT/message.json"
  mv "$TEST_ROOT/message.json" "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/job.json"
  run_bus poll --from agent-a --agent-id agent-a --session-id child-session-a --role agent --capability "$AGENT_CAPABILITY" --types job
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed message"* ]]
}

@test "compact retains the newest json files including names with spaces" {
  local helper acked
  fixture_bus
  plant_agent agent-a child-session-a
  helper="$REPO_ROOT/scripts/lib/tmux-private-fs.py"
  acked="$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/acked"
  python3 "$helper" write-json --root "$CONTROL_ROOT/.runtime/tmux-bus" --relative "inboxes/agent-a/acked/old.json" --document '{"n":1}'
  sleep 0.05
  python3 "$helper" write-json --root "$CONTROL_ROOT/.runtime/tmux-bus" --relative "inboxes/agent-a/acked/name with spaces.json" --document '{"n":2}'
  sleep 0.05
  python3 "$helper" write-json --root "$CONTROL_ROOT/.runtime/tmux-bus" --relative "inboxes/agent-a/acked/newest.json" --document '{"n":3}'

  run_bus compact --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --retain 2

  [ "$status" -eq 0 ]
  [ ! -e "$acked/old.json" ]
  [ -f "$acked/name with spaces.json" ]
  [ -f "$acked/newest.json" ]
}
