#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/session-start.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  export CLAUDE_SESSION_ID="session-start-${BATS_TEST_NUMBER}-$$"
  ROOT_LINK="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID}"
  rm -rf "$ROOT_LINK"
}

teardown() {
  rm -rf "$TEST_ROOT" "$ROOT_LINK"
  unset CLAUDE_SESSION_ID
}

run_session_start() {
  (
    cd "$REPO_ROOT"
    LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT"
  )
}

run_session_start_from() {
  local script_dir="$1"
  (
    cd "$REPO_ROOT"
    LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$script_dir/session-start.sh"
  )
}

@test "session-start fails clearly when a required root link cannot be created" {
  local plugin_root="$TEST_ROOT/plugin"
  mkdir -p "$plugin_root"
  cp -R "$REPO_ROOT/scripts" "$plugin_root/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$plugin_root/scripts/ensure-plugin-root-link.sh"
  chmod +x "$plugin_root/scripts/ensure-plugin-root-link.sh"

  run run_session_start_from "$plugin_root/scripts"

  [ "$status" -eq 1 ]
  [[ "$output" == *"LBWC: SessionStart plugin root link bootstrap failed"* ]]
}

@test "session-start creates the exact session plugin root link" {
  local canonical_root
  canonical_root=$(cd "$REPO_ROOT" && pwd -P)

  run run_session_start

  [ "$status" -eq 0 ]
  [ -L "$ROOT_LINK" ]
  [ "$(readlink "$ROOT_LINK")" = "$canonical_root" ]
}

@test "session-start: cold start with no planning dir exits 0 and reports init needed" {
  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"no ${PLANNING_DIR}/ directory found"* ]]
}

@test "session-start: warm start with an existing project reports a phase brief" {
  mkdir -p "$PLANNING_DIR"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc phase"* ]]
}

@test "session-start: resume brief names the next command for a phase needing a plan" {
  mkdir -p "$PLANNING_DIR/phases/01-test"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"missing PLAN.md"* ]]
  [[ "$output" == *"/plan 01"* ]]
}

@test "session-start: needs_discussion routes to /discuss, not /plan" {
  mkdir -p "$PLANNING_DIR/phases/01-test"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"
  printf '# Roadmap\n\n### Phase 01: Test\n\n| Phase | Status |\n| 01 | pending |\n' > "$PLANNING_DIR/ROADMAP.md"
  printf '{"require_phase_discussion": true}\n' > "$PLANNING_DIR/config.json"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"missing CONTEXT.md"* ]]
  [[ "$output" == *"/discuss 01"* ]]
  [[ "$output" != *"/plan 01"* ]]
}

@test "session-start: phase setup failure is unavailable status, not missing planning" {
  local shim_dir="$TEST_ROOT/scripts-phase-detect-setup-failure"
  cp -R "$REPO_ROOT/scripts" "$shim_dir"
  cat > "$shim_dir/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'phase_detect_error=true' 'phase_detect_reason=setup_failed'
exit 1
EOF
  chmod +x "$shim_dir/phase-detect.sh"

  run run_session_start_from "$shim_dir"

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: phase status unavailable (setup_failed)."* ]]
  [[ "$output" != *"no ${PLANNING_DIR}/ directory found"* ]]
}

@test "session-start: surfaces a malformed agent manifest" {
  mkdir -p "$PLANNING_DIR"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"
  printf '{not valid json\n' > "$PLANNING_DIR/.agent-manifest.json"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: agent manifest status malformed."* ]]
}

@test "session-start: surfaces an unavailable agent manifest" {
  local shim_dir="$TEST_ROOT/scripts-agent-manifest-unavailable"
  cp -R "$REPO_ROOT/scripts" "$shim_dir"
  cat > "$shim_dir/agent-lifecycle.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'agent_manifest_status=unavailable'
exit 1
EOF
  chmod +x "$shim_dir/agent-lifecycle.sh"

  run run_session_start_from "$shim_dir"

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: agent manifest status unavailable."* ]]
}

fixture_session_bus() {
  local control_root="$1" hash registry
  source "$REPO_ROOT/scripts/lib/lbwc-control-root.sh"
  source "$REPO_ROOT/scripts/lib/tmux-runtime.sh"
  tmux_runtime_configure "$control_root"
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

plant_unbound_agent() {
  local agent_id="$1" capability="$2" hash registry updated
  hash=$(tmux_runtime_capability_hash "$capability")
  registry=$(tmux_runtime_registry_read)
  updated=$(jq --arg id "$agent_id" --arg hash "$hash" '
    .agents += [{
      agent_id: $id, parent_id: .main.agent_id, contract_id: "contract-a", generated_name: $id,
      tmux_target: "lbwc-test-main:0.1", tmux_pane_id: null, claude_session_id: null,
      capability_hash: $hash, state: "registered", heartbeat_at_ms: null
    }]
    | .routes[$id] = {inbox: $id, tmux_target: "lbwc-test-main:0.1"}
  ' <<<"$registry")
  tmux_runtime_write_registry_route_bundle "$updated"
  tmux_runtime_initialize_inbox "$agent_id"
}

write_credential() {
  local agent_id="$1" capability="$2"
  jq -n --arg agent_id "$agent_id" --arg contract_id contract-a --arg capability "$capability" '{agent_id:$agent_id,contract_id:$contract_id,capability:$capability}' > "$TEST_ROOT/credential.json"
  python3 "$REPO_ROOT/scripts/lib/tmux-private-fs.py" write-json --root "$TMUX_RUNTIME_BUS_ROOT" --relative "credentials/$agent_id.json" --document "$(cat "$TEST_ROOT/credential.json")"
}

@test "session-start bind fails when the credential file is missing" {
  local control_root="$TEST_ROOT/tmux-project/.lbwc-planning"
  mkdir -p "$control_root"
  printf '%s\n' '{}' > "$control_root/config.json"
  fixture_session_bus "$control_root"
  plant_unbound_agent agent-a 0123456789abcdef0123456789abcdef

  run env LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$control_root" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=actual-child-session bash "$SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"tmux bind failed"* ]]
}

@test "session-start consumes a one-shot credential and records a heartbeat" {
  local control_root="$TEST_ROOT/tmux-project/.lbwc-planning" agent_capability
  mkdir -p "$control_root"
  printf '%s\n' '{}' > "$control_root/config.json"
  fixture_session_bus "$control_root"
  agent_capability='0123456789abcdef0123456789abcdef'
  plant_unbound_agent agent-a "$agent_capability"
  write_credential agent-a "$agent_capability"

  run env LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$control_root" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=actual-child-session bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -e "$control_root/.runtime/tmux-bus/credentials/agent-a.json" ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .claude_session_id == "actual-child-session" and .state == "running" and (.heartbeat_at_ms | type == "number")' "$control_root/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]

  write_credential agent-a "$agent_capability"
  run env LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$control_root" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=second-child-session bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"tmux bind failed"* ]]
}

@test "session-start bind fails on a mismatched credential" {
  local control_root="$TEST_ROOT/tmux-project/.lbwc-planning"
  mkdir -p "$control_root"
  printf '%s\n' '{}' > "$control_root/config.json"
  fixture_session_bus "$control_root"
  plant_unbound_agent agent-a 0123456789abcdef0123456789abcdef
  write_credential agent-a fedcba9876543210fedcba9876543210

  run env LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$control_root" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=actual-child-session bash "$SCRIPT"

  [ "$status" -ne 0 ]
}

@test "concurrent SessionStart attempts bind a credential at most once" {
  local control_root="$TEST_ROOT/tmux-project/.lbwc-planning" agent_capability
  mkdir -p "$control_root"
  printf '%s\n' '{}' > "$control_root/config.json"
  fixture_session_bus "$control_root"
  agent_capability='0123456789abcdef0123456789abcdef'
  plant_unbound_agent agent-a "$agent_capability"
  write_credential agent-a "$agent_capability"

  run env SESSION_START="$SCRIPT" CONTROL_ROOT="$control_root" PLANNING_DIR="$PLANNING_DIR" bash -c '
    LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$CONTROL_ROOT" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=concurrent-child-session bash "$SESSION_START" > "$CONTROL_ROOT/first-session-start.log" 2>&1 &
    first=$!
    LBWC_TMUX_AGENT=1 LBWC_TMUX_AGENT_ID=agent-a LBWC_TMUX_CONTRACT_ID=contract-a LBWC_TMUX_CONTROL_ROOT="$CONTROL_ROOT" LBWC_PLANNING_DIR="$PLANNING_DIR" CLAUDE_SESSION_ID=concurrent-child-session bash "$SESSION_START" > "$CONTROL_ROOT/second-session-start.log" 2>&1 &
    second=$!
    wait "$first"; first_status=$?
    wait "$second"; second_status=$?
    { [ "$first_status" -eq 0 ] && [ "$second_status" -ne 0 ]; } || { [ "$first_status" -ne 0 ] && [ "$second_status" -eq 0 ]; }
  '

  [ "$status" -eq 0 ]
  [ ! -e "$control_root/.runtime/tmux-bus/credentials/agent-a.json" ]
  run jq -e '.agents[] | select(.agent_id == "agent-a") | .claude_session_id == "concurrent-child-session"' "$control_root/.runtime/tmux-bus/registry.json"
  [ "$status" -eq 0 ]
}

