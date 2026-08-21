#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOCTOR="$REPO_ROOT/commands/doctor.md"
  TEST_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
  PLUGIN_ROOT="$TEST_ROOT/plugin"
  PLUGIN_SCRIPTS="$PLUGIN_ROOT/scripts"
  PROJECT_ROOT="$TEST_ROOT/project"
  FAKE_BIN="$TEST_ROOT/bin"
  COMMAND_SESSION_ID="doctor-${BATS_TEST_NUMBER}-$$"
  ROOT_LINK="/tmp/.lbwc-plugin-root-link-${COMMAND_SESSION_ID}"
  CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
  DOCTOR_HELPER="$REPO_ROOT/scripts/tmux-doctor.sh"
  mkdir -p "$PLUGIN_SCRIPTS/lib" "$PROJECT_ROOT/.lbwc-planning" "$FAKE_BIN"
  printf '%s\n' '{}' > "$PROJECT_ROOT/.lbwc-planning/config.json"
  cp "$REPO_ROOT/scripts/ensure-plugin-root-link.sh" "$PLUGIN_SCRIPTS/ensure-plugin-root-link.sh"
  cp "$REPO_ROOT/scripts/resolve-plugin-root.sh" "$PLUGIN_SCRIPTS/resolve-plugin-root.sh"
  cp "$REPO_ROOT/scripts/tmux-preflight.sh" "$PLUGIN_SCRIPTS/tmux-preflight.sh"
  cp "$REPO_ROOT/scripts/tmux-session-name.sh" "$PLUGIN_SCRIPTS/tmux-session-name.sh"
  cp "$REPO_ROOT/scripts/lib/lbwc-control-root.sh" "$PLUGIN_SCRIPTS/lib/lbwc-control-root.sh"
  cp "$REPO_ROOT/scripts/lib/lbwc-target-root.sh" "$PLUGIN_SCRIPTS/lib/lbwc-target-root.sh"
  cp "$REPO_ROOT/scripts/lib/tmux-private-fs.py" "$PLUGIN_SCRIPTS/lib/tmux-private-fs.py"
  cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -V) printf '%s\n' 'tmux 3.4' ;;
  has-session) exit 1 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/tmux"
  rm -rf "$ROOT_LINK"
}

teardown() {
  rm -rf "$TEST_ROOT" "$ROOT_LINK"
}

resolve_doctor_context() {
  local directive
  directive="$(awk '/^!`/{sub(/^!`/,""); sub(/`$/,""); print; exit}' "$DOCTOR")"
  [ -n "$directive" ] || return 1

  run env -u LINK -u PROJECT_ROOT \
    CLAUDE_SESSION_ID="$COMMAND_SESSION_ID" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash -c "cd \"$PROJECT_ROOT\" && $directive"
  [ "$status" -eq 0 ] || return "$status"

  RESOLVED_LINK="$(printf '%s\n' "$output" | awk -F': ' '/^Plugin root: /{print $2; exit}')"
  RESOLVED_PROJECT_ROOT="$(printf '%s\n' "$output" | awk -F': ' '/^Project root: /{print $2; exit}')"
  [ "$RESOLVED_LINK" = "$PLUGIN_ROOT" ]
  [ "$RESOLVED_PROJECT_ROOT" = "$PROJECT_ROOT" ]
}

run_resolved_preflight() {
  local preflight
  resolve_doctor_context || return $?
  preflight="$(sed -n 's/.*run `\(bash "{LINK}\/scripts\/tmux-preflight\.sh"[^`]*\)`.*/\1/p' "$DOCTOR")"
  [ -n "$preflight" ] || return 1
  preflight="${preflight//\{LINK\}/$RESOLVED_LINK}"
  preflight="${preflight//\{PROJECT_ROOT\}/$RESOLVED_PROJECT_ROOT}"
  [[ "$preflight" != *'{LINK}'* ]] || return 1
  [[ "$preflight" != *'{PROJECT_ROOT}'* ]] || return 1
  [[ "$preflight" != *'{project-root}'* ]] || return 1

  run env \
    PATH="$FAKE_BIN:$PATH" \
    CLAUDE_SESSION_ID="$COMMAND_SESSION_ID" \
    bash -c "cd \"$PROJECT_ROOT\" && $preflight"
}

run_tmux_doctor() {
  run env PATH="$FAKE_BIN:$PATH" bash "$DOCTOR_HELPER" \
    --project-root "$PROJECT_ROOT" \
    --control-root "$CONTROL_ROOT"
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

plant_healthy_runtime() {
  local hash registry
  source_runtime
  ensure_bus_layout
  jq -n '{agent_execution_mode:"tmux",tmux_execution:{enabled:true,heartbeat_stale_seconds:120}}' > "$CONTROL_ROOT/config.json"
  hash=$(tmux_runtime_capability_hash "$(tmux_runtime_capability)")
  registry=$(jq -n --arg hash "$hash" '{
    schema_version: 2,
    main: {agent_id:"main-session",session_id:"main-session",role:"orchestrator",capability_hash:$hash},
    tmux: {session:"lbwc-main",orchestrator_target:"lbwc-main:0.0",orchestrator_pane:"0",topology:"detached-new-session",managed_session:true,ownership_token:"owned"},
    agents: [{
      agent_id:"agent-a",
      parent_id:"main-session",
      contract_id:"contract-a",
      generated_name:"agent-a",
      tmux_target:"lbwc-main:0.1",
      tmux_pane_id:"%1",
      claude_session_id:"session-a",
      capability_hash:("1" * 64),
      state:"running",
      heartbeat_at_ms:2000000000000
    }],
    routes: {
      "main-session": {inbox:"main-session",tmux_target:"lbwc-main:0.0"},
      "agent-a": {inbox:"agent-a",tmux_target:"lbwc-main:0.1"}
    }
  }')
  tmux_runtime_write_registry_route_bundle "$registry"
  cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) [ "$3" = lbwc-main ] && exit 0; exit 1 ;;
  display-message) exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$FAKE_BIN/tmux"
}

@test "doctor: preserves the fixed twenty-check output contract and adds runtime diagnostics" {
  run grep -F 'Result: {N}/20 passed, {W} warnings, {F} failures' "$DOCTOR"
  [ "$status" -eq 0 ]
  grep -F '  20. Temporary runs       {PASS|WARN|FAIL} {detail}' "$DOCTOR" >/dev/null
  grep -F 'Runtime diagnostics' "$DOCTOR" >/dev/null
  grep -F 'tmux-doctor.sh' "$DOCTOR" >/dev/null
  grep -F 'execution backend' "$DOCTOR" >/dev/null
  grep -F 'tmux session and pane health' "$DOCTOR" >/dev/null
  grep -F 'agent lifecycle counts' "$DOCTOR" >/dev/null
}

@test "doctor: diagnoses runtime integrity without mutating state by default" {
  grep -F 'tmux-doctor.sh' "$DOCTOR" >/dev/null
  grep -F 'malformed registry' "$DOCTOR" >/dev/null
  grep -F 'malformed route' "$DOCTOR" >/dev/null
  grep -F 'missing tmux' "$DOCTOR" >/dev/null
  grep -F 'stale heartbeat' "$DOCTOR" >/dev/null
  grep -F 'read-only' "$DOCTOR" >/dev/null
  grep -F 'Run `/lbwc:doctor --cleanup`' "$DOCTOR" >/dev/null
}

@test "doctor: provides actionable repair diagnostics and cleanup boundaries" {
  grep -F 'tmux-preflight.sh' "$DOCTOR" >/dev/null
  grep -F 'tmux-bus.sh' "$DOCTOR" >/dev/null
  grep -F 'does not authorize cleanup' "$DOCTOR" >/dev/null
  grep -F 'Never remove registry, route, lock, claim, pane, or session state' "$DOCTOR" >/dev/null
}

@test "tmux doctor: missing runtime is PASS and creates no bus state" {
  run_tmux_doctor

  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = PASS ]
  [ "$(jq -r '.detail' <<<"$output")" = 'no tmux runtime' ]
  [ ! -e "$CONTROL_ROOT/.runtime" ]
}

@test "tmux doctor: malformed registry is FAIL and does not rewrite the bus" {
  local before
  source_runtime
  ensure_bus_layout
  python3 "$REPO_ROOT/scripts/lib/tmux-private-fs.py" write-json \
    --root "$TMUX_RUNTIME_BUS_ROOT" \
    --relative registry.json \
    --document '{"nope":true}'
  before=$(cksum "$TMUX_RUNTIME_BUS_ROOT/registry.json")

  run_tmux_doctor

  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = FAIL ]
  [ "$(jq -r '.detail' <<<"$output")" = 'malformed registry' ]
  [ "$(cksum "$TMUX_RUNTIME_BUS_ROOT/registry.json")" = "$before" ]
}

@test "tmux doctor: healthy registry routes session panes and heartbeats are PASS" {
  local before
  plant_healthy_runtime
  before=$(find "$CONTROL_ROOT/.runtime" -type f -exec cksum {} \; | sort)

  run_tmux_doctor

  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = PASS ]
  [ "$(jq -r '.detail' <<<"$output")" = 'backend=tmux session=lbwc-main panes=2/2 agents=1 running:1 idle:0 failed:0 heartbeats=fresh' ]
  [ "$(find "$CONTROL_ROOT/.runtime" -type f -exec cksum {} \; | sort)" = "$before" ]
}

@test "tmux doctor: shutdown agents without routes are PASS" {
  plant_healthy_runtime
  registry=$(jq '
    .agents |= map(if .agent_id == "agent-a" then .state = "shutdown" else . end)
    | .routes |= del(.["agent-a"])
  ' "$CONTROL_ROOT/.runtime/tmux-bus/registry.json")
  tmux_runtime_write_registry_route_bundle "$registry"

  run_tmux_doctor

  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = PASS ]
  [ "$(jq -r '.detail' <<<"$output")" = 'backend=tmux session=lbwc-main panes=1/1 agents=1 running:0 idle:0 failed:0 heartbeats=fresh' ]
}

@test "tmux doctor: workflow backend reports as itself, not coerced to in_process" {
  plant_healthy_runtime
  jq '.agent_execution_mode = "workflow"' "$CONTROL_ROOT/config.json" > "$CONTROL_ROOT/config.json.tmp"
  mv "$CONTROL_ROOT/config.json.tmp" "$CONTROL_ROOT/config.json"

  run_tmux_doctor

  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' <<<"$output")" = PASS ]
  [[ "$(jq -r '.detail' <<<"$output")" == 'backend=workflow '* ]]
}

@test "doctor resolves the unavailable-runtime preflight helper before invoking it" {
  run grep -c '^!`' "$DOCTOR"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run_resolved_preflight

  [ "$status" -eq 0 ]
  [ "$RESOLVED_LINK" = "$PLUGIN_ROOT" ]
  [ "$RESOLVED_PROJECT_ROOT" = "$PROJECT_ROOT" ]
  [[ "$output" == *'"preflight": "passed"'* ]]
}
