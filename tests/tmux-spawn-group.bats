#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HELPER="$REPO_ROOT/scripts/tmux-spawn-group.sh"
  BUS="$REPO_ROOT/scripts/tmux-bus.sh"
  CHILD="$REPO_ROOT/tests/fixtures/tmux-child-job.sh"
  TEST_ROOT="$(mktemp -d)"
  PROJECT_ROOT="$TEST_ROOT/project"
  CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
  mkdir -p "$CONTROL_ROOT"
  printf '%s\n' '{}' > "$CONTROL_ROOT/config.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
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
  local hash registry main_id="$1"
  source_runtime
  ensure_bus_layout
  MAIN_CAPABILITY=$(tmux_runtime_capability)
  hash=$(tmux_runtime_capability_hash "$MAIN_CAPABILITY")
  registry=$(jq -n --arg main "$main_id" --arg hash "$hash" '{
    schema_version: 2,
    main: {agent_id: $main, session_id: $main, role: "orchestrator", capability_hash: $hash},
    tmux: {session: null, orchestrator_target: null, orchestrator_pane: null, topology: "pending", managed_session: false, ownership_token: null},
    agents: [],
    routes: {($main): {inbox: $main, tmux_target: null}}
  }')
  tmux_runtime_write_registry_route_bundle "$registry"
  tmux_runtime_initialize_inbox "$main_id"
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

install_dispatch_stubs() {
  local plugin="$TEST_ROOT/plugin"
  mkdir -p "$plugin/scripts/lib"
  cp "$HELPER" "$plugin/scripts/tmux-spawn-group.sh"
  cp "$BUS" "$plugin/scripts/tmux-bus.sh"
  cp "$REPO_ROOT/scripts/lib/"*.sh "$plugin/scripts/lib/" 2>/dev/null || true
  cp "$REPO_ROOT/scripts/lib/"*.py "$plugin/scripts/lib/"
  chmod +x "$plugin/scripts/tmux-spawn-group.sh" "$plugin/scripts/tmux-bus.sh"
  cat > "$plugin/scripts/tmux-preflight.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n '{tmux_session:"lbwc-test-main",topology:"detached-new-session"}'
EOF
  cat > "$plugin/scripts/tmux-agent-orchestrator.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
subcommand="\$1"
shift
capability="${MAIN_CAPABILITY}"
case "\$subcommand" in
  provision)
    jq -n --arg cap "\$capability" '{tmux_session:"lbwc-test-main",orchestrator_target:"lbwc-test-main:0.0",topology:"detached-new-session",main_capability:\$cap}'
    ;;
  split-group)
    if [ "\${SPLIT_FAIL:-}" = 1 ]; then
      printf 'split-group failed\n' >&2
      exit 1
    fi
    exit 0
    ;;
  rollback)
    printf 'rolled-back\n' > "$TEST_ROOT/rollback.txt"
    jq -n '{state:"rolled_back"}'
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$plugin/scripts/tmux-preflight.sh" "$plugin/scripts/tmux-agent-orchestrator.sh"
  STUB_HELPER="$plugin/scripts/tmux-spawn-group.sh"
}

@test "build-agents JSON uses generated names as agent_id" {
  run bash "$HELPER" build-agents --names worker-a,worker-b --contract-id contract-1 --contract-digest digest-1
  [ "$status" -eq 0 ]
  jq -e '
    length == 2
    and .[0] == {agent_id:"worker-a",generated_name:"worker-a",contract_id:"contract-1",contract_digest:"digest-1"}
    and .[1] == {agent_id:"worker-b",generated_name:"worker-b",contract_id:"contract-1",contract_digest:"digest-1"}
    and all(.[]; .agent_id == .generated_name)
  ' <<<"$output" >/dev/null
}

@test "build-agents parses SPAWN_READY generator output" {
  run bash "$HELPER" build-agents --contract-id contract-1 --contract-digest digest-1 \
    --spawn-ready-text $'ENGINEER: SPAWN_READY lbwc-web-engineer-aaaa\nCRITIC: SPAWN_READY lbwc-web-code-critic-bbbb\n'
  [ "$status" -eq 0 ]
  jq -e '.[0].agent_id == "lbwc-web-engineer-aaaa" and .[1].agent_id == "lbwc-web-code-critic-bbbb"' <<<"$output" >/dev/null
}

@test "dispatch fails closed when main id is missing" {
  run bash "$HELPER" dispatch --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" \
    --main-id '' --contract-id contract-1 --contract-digest digest-1 --names worker-a --job 'do work' --timeout-ms 1000
  [ "$status" -ne 0 ]
  [[ "$output" == *"main id is required"* ]] || [[ "$output" == *"Usage:"* ]]
}

@test "dispatch fails closed when CLAUDE_SESSION_ID is empty and main id is omitted" {
  run env -u CLAUDE_SESSION_ID bash "$HELPER" dispatch --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" \
    --contract-id contract-1 --contract-digest digest-1 --names worker-a --job 'do work' --timeout-ms 1000
  [ "$status" -ne 0 ]
}

@test "await ack uses the message id returned by await" {
  local main_id='live-claude-session'
  fixture_bus "$main_id"
  plant_agent worker-a child-session-a
  install_dispatch_stubs

  TMUX_CHILD_BUS="$BUS" TMUX_CHILD_CONTROL_ROOT="$CONTROL_ROOT" TMUX_CHILD_AGENT_ID=worker-a \
    TMUX_CHILD_SESSION_ID=child-session-a TMUX_CHILD_CAPABILITY="$AGENT_CAPABILITY" \
    TMUX_CHILD_TIMEOUT_MS=4000 bash "$CHILD" &
  child_pid=$!

  run bash "$STUB_HELPER" dispatch --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" \
    --main-id "$main_id" --main-capability "$MAIN_CAPABILITY" \
    --contract-id contract-1 --contract-digest digest-1 --names worker-a \
    --job 'do work' --timeout-ms 4000

  wait "$child_pid"
  [ "$status" -eq 0 ]
  jq -e --arg main "$main_id" '
    .status == "completed"
    and .main_id == $main
    and (.agents[0].message_id | test("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"))
    and .agents[0].type == "result"
    and .agents[0].payload.result == "child-complete"
  ' <<<"$output" >/dev/null
  acked=$(jq -r '.agents[0].message_id' <<<"$output")
  [ -f "$CONTROL_ROOT/.runtime/tmux-bus/inboxes/$main_id/acked/$acked.json" ]
}

@test "dispatch rolls back when split-group fails" {
  local main_id='live-claude-session'
  fixture_bus "$main_id"
  MAIN_CAPABILITY="$MAIN_CAPABILITY"
  install_dispatch_stubs
  SPLIT_FAIL=1 run bash "$STUB_HELPER" dispatch --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" \
    --main-id "$main_id" --main-capability "$MAIN_CAPABILITY" \
    --contract-id contract-1 --contract-digest digest-1 --names worker-a \
    --job 'do work' --timeout-ms 1000
  [ "$status" -ne 0 ]
  [ -f "$TEST_ROOT/rollback.txt" ]
}
