#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/tmux-bus-watchdog.sh"
  TEST_ROOT="$(mktemp -d)"
  TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
  CONTROL_ROOT="$TEST_ROOT/project/.lbwc-planning"
  mkdir -p "$CONTROL_ROOT"
  printf '%s\n' '{}' > "$CONTROL_ROOT/config.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

fixture_watchdog_bus() {
  local hash registry
  source "$REPO_ROOT/scripts/lib/lbwc-control-root.sh"
  source "$REPO_ROOT/scripts/lib/tmux-runtime.sh"
  tmux_runtime_configure "$CONTROL_ROOT"
  tmux_runtime_ensure
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/inboxes"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/outbox/main"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/transactions"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/claims"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/credentials"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/heartbeats"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/locks"
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

plant_bound_agent() {
  local target="$1" pane_id="$2" hash registry updated
  AGENT_CAPABILITY=$(tmux_runtime_capability)
  hash=$(tmux_runtime_capability_hash "$AGENT_CAPABILITY")
  registry=$(tmux_runtime_registry_read)
  updated=$(jq --arg target "$target" --arg pane "$pane_id" --arg hash "$hash" --argjson heartbeat 1 '
    .agents += [{
      agent_id: "agent-a",
      parent_id: .main.agent_id,
      contract_id: "contract-a",
      generated_name: "agent-a",
      tmux_target: $target,
      tmux_pane_id: (if $pane == "" then null else $pane end),
      claude_session_id: "agent-session",
      capability_hash: $hash,
      state: "running",
      heartbeat_at_ms: $heartbeat
    }]
    | .routes["agent-a"] = {inbox: "agent-a", tmux_target: $target}
  ' <<<"$registry")
  tmux_runtime_write_registry_route_bundle "$updated" || return 1
  tmux_runtime_initialize_inbox agent-a
}

write_tmux_shim() {
  local tmux_bin="$TEST_ROOT/bin"
  mkdir -p "$tmux_bin"
  cat > "$tmux_bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) [ -e "$LBWC_TEST_TMUX_MARKER" ] && printf '%%1\n' ;;
  kill-pane) [ "${LBWC_TEST_TMUX_KILL_FAIL:-0}" = 1 ] && exit 1; rm -f "$LBWC_TEST_TMUX_MARKER" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$tmux_bin/tmux"
  printf '%s\n' "$tmux_bin"
}

@test "tmux watchdog: fails closed on a malformed runtime registry" {
  CONTROL_ROOT="$TEST_ROOT/control"
  mkdir -p "$CONTROL_ROOT/.runtime/tmux-bus"
  printf '{not valid json\n' > "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"

  run bash "$SCRIPT" \
    --control-root "$CONTROL_ROOT" \
    check \
    --orchestrator-id main-session \
    --orchestrator-session-id main-session \
    --orchestrator-capability 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
    --stale-after-ms 120000 \
    --shutdown-timeout-ms 5000

  [ "$status" -ne 0 ]
  [ "$output" = "tmux-watchdog: runtime registry is malformed" ]
}

@test "tmux watchdog: emits an error envelope and records one actionable notification when stale agents shut down" {
  fixture_watchdog_bus
  plant_bound_agent missing:0.1 ''
  run jq -e '.agents | length == 1' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 120000 --shutdown-timeout-ms 5000
  [ "$status" -eq 1 ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -e '.type == "error" and .from.role == "orchestrator" and .to.agent_id == "main-session" and (.body.message | contains("agent-a"))' "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/main-session/error.json"
  [ "$status" -eq 0 ]
  run jq -s -e 'length == 1 and .[0].type == "tmux_watchdog_stale_agents_failed" and .[0].title == "TMUX watchdog failed stale agents" and (.[0].message | contains("agent-a"))' "$CONTROL_ROOT/.notification-log.jsonl"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 120000 --shutdown-timeout-ms 5000
  [ "$status" -eq 0 ]
  run jq -s -e 'length == 1' "$CONTROL_ROOT/.notification-log.jsonl"
  [ "$status" -eq 0 ]
}

@test "tmux watchdog: concurrent checks notify once and preserve one terminal transition" {
  local result
  fixture_watchdog_bus
  plant_bound_agent missing:0.1 ''
  result="$TEST_ROOT/concurrent-result"

  run env SCRIPT="$SCRIPT" CONTROL_ROOT="$CONTROL_ROOT" MAIN_CAPABILITY="$MAIN_CAPABILITY" RESULT="$result" bash -c '
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 50 > "$RESULT.one" 2>&1 &
    first=$!
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 50 > "$RESULT.two" 2>&1 &
    second=$!
    wait "$first" || true
    wait "$second" || true
  '

  [ "$status" -eq 0 ]
  run jq -s -e 'length == 1 and .[0].type == "tmux_watchdog_stale_agents_failed"' "$CONTROL_ROOT/.notification-log.jsonl"
  [ "$status" -eq 0 ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

@test "tmux watchdog: honors graceful acknowledgement before forced pane termination" {
  local tmux_bin marker output_file
  tmux_bin=$(write_tmux_shim)
  marker="$TEST_ROOT/pane-present"
  output_file="$TEST_ROOT/watchdog-output"
  : > "$marker"
  fixture_watchdog_bus
  plant_bound_agent test:0.1 '%1'

  run timeout 15 env PATH="$tmux_bin:$PATH" LBWC_TEST_TMUX_MARKER="$marker" SCRIPT="$SCRIPT" BUS="$REPO_ROOT/scripts/tmux-bus.sh" CONTROL_ROOT="$CONTROL_ROOT" MAIN_CAPABILITY="$MAIN_CAPABILITY" AGENT_CAPABILITY="$AGENT_CAPABILITY" OUTPUT_FILE="$output_file" bash -c '
    bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 1000 > "$OUTPUT_FILE" 2>&1 &
    watchdog=$!
    for ((attempt = 0; attempt < 800; attempt++)); do
      [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/shutdown_request.json" ] && break
      sleep 0.01
    done
    [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/agent-a/shutdown_request.json" ] || { cat "$OUTPUT_FILE"; exit 1; }
    bash "$BUS" --control-root "$CONTROL_ROOT" publish --to main-session --from-agent-id agent-a --from-session-id agent-session --from-role agent --capability "$AGENT_CAPABILITY" --type shutdown_response --correlation-id watchdog --payload "{\"acknowledged\":true}" >/dev/null
    rm -f "$LBWC_TEST_TMUX_MARKER"
    wait "$watchdog" || true
  '

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

@test "tmux watchdog: kills a stale pane after the graceful shutdown timeout" {
  local tmux_bin marker
  tmux_bin=$(write_tmux_shim)
  marker="$TEST_ROOT/pane-present"
  : > "$marker"
  fixture_watchdog_bus
  plant_bound_agent test:0.1 '%1'

  run timeout 5 env PATH="$tmux_bin:$PATH" LBWC_TEST_TMUX_MARKER="$marker" bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 30

  [ "$status" -eq 1 ]
  [ ! -e "$marker" ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown"' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

@test "tmux watchdog: completes teardown after a busy error inbox without retrying terminal reports" {
  fixture_watchdog_bus
  plant_bound_agent missing:0.1 ''
  run bash "$REPO_ROOT/scripts/tmux-bus.sh" --control-root "$CONTROL_ROOT" publish --to main-session --from-agent-id main-session --from-session-id main-session --from-role orchestrator --capability "$MAIN_CAPABILITY" --type error --correlation-id occupied --payload '{"message":"occupied"}'
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 30

  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot publish stale agent error envelope"* ]]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown" and .watchdog_cleanup_pending == false' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  run jq -s -e 'length == 1 and .[0].type == "tmux_watchdog_stale_agents_failed"' "$CONTROL_ROOT/.notification-log.jsonl"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 30
  [ "$status" -eq 0 ]
  run jq -s -e 'length == 1' "$CONTROL_ROOT/.notification-log.jsonl"
  [ "$status" -eq 0 ]
}

@test "tmux watchdog: retries pending teardown without repeating a failed notification" {
  local tmux_bin marker
  tmux_bin=$(write_tmux_shim)
  marker="$TEST_ROOT/pane-present"
  : > "$marker"
  fixture_watchdog_bus
  plant_bound_agent test:0.1 '%1'
  chmod 500 "$CONTROL_ROOT"

  run env PATH="$tmux_bin:$PATH" LBWC_TEST_TMUX_MARKER="$marker" LBWC_TEST_TMUX_KILL_FAIL=1 bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 30
  chmod 700 "$CONTROL_ROOT"

  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot append stale agent failure notification"* ]]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "failed" and .watchdog_cleanup_pending == true' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  [ ! -e "$CONTROL_ROOT/.notification-log.jsonl" ]

  run env PATH="$tmux_bin:$PATH" LBWC_TEST_TMUX_MARKER="$marker" bash "$SCRIPT" --control-root "$CONTROL_ROOT" check --orchestrator-id main-session --orchestrator-session-id main-session --orchestrator-capability "$MAIN_CAPABILITY" --stale-after-ms 1 --shutdown-timeout-ms 30

  [ "$status" -eq 1 ]
  [ ! -e "$marker" ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .state == "shutdown" and .watchdog_cleanup_pending == false' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
  [ ! -e "$CONTROL_ROOT/.notification-log.jsonl" ]
}
