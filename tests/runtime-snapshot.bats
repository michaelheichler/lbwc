#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SCRIPT="$REPO_ROOT/scripts/runtime-snapshot.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/project/.lbwc-planning"
  PHASE_DIR="$PLANNING_DIR/phases/01-runtime-freeze"
  SNAPSHOT_PATH="$PHASE_DIR/.runtime-snapshot.json"
  mkdir -p "$PHASE_DIR"
  write_config
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_config() {
  jq -n '
    {
      effort: "balanced",
      agent_execution_mode: "in_process",
      tmux_execution: {
        enabled: false,
        session_name_prefix: "lbwc",
        max_agents: 3,
        attach_policy: "orchestrator_only",
        heartbeat_interval_seconds: 30,
        heartbeat_stale_seconds: 120,
        comms_latency_tolerance_ms: 5000,
        comms_fallback: "bus_only",
        cleanup_policy: "kill_on_complete",
        layout: "main-vertical",
        restrictions: {
          allow_nested_spawn: false,
          allow_agent_git: false,
          allow_agent_ask_user: false,
          require_orchestrator_attach: true
        }
      },
      workflow_execution: {
        enabled: false
      },
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {
            roles: {
              "coding-dijkstra": {
                model: "openai/gpt-5.6-terra",
                reasoning: "high",
                status: "resolved"
              }
            }
          },
          turbo: {roles: {}}
        }
      }
    }
  ' > "$PLANNING_DIR/config.json"
}

run_snapshot() {
  run bash "$SCRIPT" "$@" --planning-dir "$PLANNING_DIR" --phase-dir "$PHASE_DIR"
}

freeze_in_process() {
  run_snapshot freeze --requested-backend in_process --resolved-backend in_process
  [ "$status" -eq 0 ]
}

@test "freeze creates the canonical schema atomically" {
  freeze_in_process

  [ -f "$SNAPSHOT_PATH" ]
  jq -e --arg phase "phases/01-runtime-freeze" '
    .schema_version == 1
    and .phase == $phase
    and .requested_backend == "in_process"
    and .resolved_backend == "in_process"
    and .effort == "balanced"
    and .routing_profile == "balanced"
    and .routing_roles["coding-dijkstra"].model == "openai/gpt-5.6-terra"
    and .tmux_execution.restrictions.require_orchestrator_attach == true
    and (.source_config_digest | test("^[0-9a-f]{64}$"))
  ' "$SNAPSHOT_PATH" >/dev/null
  [[ "$output" == *'"status":"created"'* ]]
  [ -z "$(compgen -G "$PHASE_DIR/.runtime-snapshot.tmp.*")" ]
}

@test "resume validation accepts an identical frozen configuration" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')

  run_snapshot validate

  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
  [[ "$output" == *'"status":"matched"'* ]]
}

@test "configuration drift fails before mutation" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')
  jq '.effort = "thorough"' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run_snapshot validate

  [ "$status" -ne 0 ]
  [[ "$output" == *'backend drift'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
}

@test "backend drift fails before mutation" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')
  jq '.agent_execution_mode = "tmux" | .tmux_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run_snapshot validate

  [ "$status" -ne 0 ]
  [[ "$output" == *'backend drift'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
}

write_capability_catalog() {
  local available="$1"
  if [ "$available" = true ]; then
    jq -n '{
      workflow: {
        min_version: "2.1.154",
        host_version: "2.1.200",
        meets_version_floor: true,
        disabled_by_settings: false,
        disabled_by_env: false,
        subagent_model_override_active: false,
        available: true,
        unavailable_reasons: []
      }
    }' > "$PLANNING_DIR/claude-capabilities.json"
  else
    jq -n '{
      workflow: {
        min_version: "2.1.154",
        host_version: "2.1.100",
        meets_version_floor: false,
        disabled_by_settings: false,
        disabled_by_env: false,
        subagent_model_override_active: false,
        available: false,
        unavailable_reasons: ["Claude Code 2.1.100 is older than the workflow version floor 2.1.154."]
      }
    }' > "$PLANNING_DIR/claude-capabilities.json"
  fi
}

freeze_workflow() {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  write_capability_catalog true
  run_snapshot freeze --requested-backend workflow --resolved-backend workflow
  [ "$status" -eq 0 ]
}

@test "freeze creates a workflow snapshot and validate round-trips it" {
  freeze_workflow

  [ -f "$SNAPSHOT_PATH" ]
  jq -e --arg phase "phases/01-runtime-freeze" '
    .schema_version == 1
    and .phase == $phase
    and .requested_backend == "workflow"
    and .resolved_backend == "workflow"
    and (.source_config_digest | test("^[0-9a-f]{64}$"))
  ' "$SNAPSHOT_PATH" >/dev/null
  [[ "$output" == *'"status":"created"'* ]]
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')

  run_snapshot validate

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"matched"'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
}

@test "a workflow request cannot resolve to another backend" {
  jq '.agent_execution_mode = "ask"' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run_snapshot freeze --requested-backend workflow --resolved-backend in_process

  [ "$status" -ne 0 ]
  [[ "$output" == *'workflow requested backend cannot resolve to another backend'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "workflow config mode rejects a frozen non-workflow backend" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')
  jq '.agent_execution_mode = "workflow"' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run_snapshot validate

  [ "$status" -ne 0 ]
  [[ "$output" == *'backend drift: configuration requires workflow'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
}

@test "a requested workflow backend fails closed on a disabled-host capability probe" {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  write_capability_catalog false

  run_snapshot freeze --requested-backend workflow --resolved-backend workflow

  [ "$status" -ne 0 ]
  [[ "$output" == *'workflow backend is unavailable'* ]]
  [[ "$output" == *'Claude Code 2.1.100 is older than the workflow version floor 2.1.154.'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "a requested workflow backend fails closed when disabled in configuration" {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = false' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  write_capability_catalog true

  run_snapshot freeze --requested-backend workflow --resolved-backend workflow

  [ "$status" -ne 0 ]
  [[ "$output" == *'workflow backend is disabled in configuration'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "a requested workflow backend fails closed when no capability catalog exists" {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  rm -f "$PLANNING_DIR/claude-capabilities.json"

  run_snapshot freeze --requested-backend workflow --resolved-backend workflow

  [ "$status" -ne 0 ]
  [[ "$output" == *'workflow backend is unavailable'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "a requested workflow backend fails closed when CLAUDE_CODE_SUBAGENT_MODEL is set live against a stale available catalog" {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  write_capability_catalog true

  CLAUDE_CODE_SUBAGENT_MODEL=claude-opus run_snapshot freeze --requested-backend workflow --resolved-backend workflow

  [ "$status" -ne 0 ]
  [[ "$output" == *'CLAUDE_CODE_SUBAGENT_MODEL is set in this session'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "a requested workflow backend fails closed when CLAUDE_CODE_DISABLE_WORKFLOWS is set live against a stale available catalog" {
  jq '.agent_execution_mode = "workflow" | .workflow_execution.enabled = true' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  write_capability_catalog true

  CLAUDE_CODE_DISABLE_WORKFLOWS=1 run_snapshot freeze --requested-backend workflow --resolved-backend workflow

  [ "$status" -ne 0 ]
  [[ "$output" == *'CLAUDE_CODE_DISABLE_WORKFLOWS is set in this session'* ]]
  [ ! -f "$SNAPSHOT_PATH" ]
}

@test "routing drift fails before mutation" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')
  jq '.routing.profiles.balanced.roles["coding-dijkstra"].model = "openai/gpt-5.6-luna"' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run_snapshot validate

  [ "$status" -ne 0 ]
  [[ "$output" == *'backend drift'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
}

@test "malformed snapshots fail closed" {
  printf '%s\n' '{"schema_version":1}' > "$SNAPSHOT_PATH"

  run_snapshot validate

  [ "$status" -ne 0 ]
  [[ "$output" == *'runtime snapshot is malformed'* ]]
}

@test "cancel writes a durable marker and does not freeze a backend" {
  run_snapshot cancel

  [ "$status" -eq 0 ]
  [ ! -e "$SNAPSHOT_PATH" ]
  [ -f "$PHASE_DIR/.runtime-cancelled.json" ]
  jq -e --arg phase "phases/01-runtime-freeze" '
    .schema_version == 1
    and .phase == $phase
    and .status == "cancelled"
  ' "$PHASE_DIR/.runtime-cancelled.json" >/dev/null
  [[ "$output" == *'"status":"cancelled"'* ]]
}

@test "cancel after freeze is an error" {
  freeze_in_process
  before=$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')

  run_snapshot cancel

  [ "$status" -ne 0 ]
  [[ "$output" == *'runtime snapshot already exists'* ]]
  [ "$(shasum -a 256 "$SNAPSHOT_PATH" | awk '{print $1}')" = "$before" ]
  [ ! -e "$PHASE_DIR/.runtime-cancelled.json" ]
}

@test "cleanup removes a valid terminal snapshot" {
  freeze_in_process

  run_snapshot cleanup

  [ "$status" -eq 0 ]
  [ ! -e "$SNAPSHOT_PATH" ]
  [[ "$output" == *'"status":"cleaned"'* ]]
}

@test "vibe and build execute the runtime snapshot helper" {
  for command in vibe build; do
    file="$REPO_ROOT/commands/$command.md"
    grep -F 'scripts/runtime-snapshot.sh" validate' "$file"
    grep -F 'scripts/runtime-snapshot.sh" freeze' "$file"
    grep -F 'scripts/runtime-snapshot.sh" cancel' "$file"
    grep -F '.runtime-cancelled.json' "$file"
  done

  grep -F 'scripts/runtime-snapshot.sh" cleanup' "$REPO_ROOT/commands/build.md"
  grep -F 'agent-generator.sh --execution-backend' "$REPO_ROOT/commands/build.md"
}

@test "build wires schema 3 open flags and an explicit tmux spawn branch" {
  local file="$REPO_ROOT/commands/build.md"
  grep -F -- '--requested-backend' "$file"
  grep -F -- '--resolved-backend' "$file"
  grep -F -- '--control-root' "$file"
  grep -F -- '--assert-snapshot' "$file"
  grep -F '[ -f "$SNAPSHOT_PATH" ]' "$file"
  grep -F 'references/tmux-spawn-protocol.md' "$file"
  grep -F 'tmux-spawn-group.sh" dispatch' "$file"
  grep -F 'CLAUDE_SESSION_ID' "$file"
  grep -F 'If `snapshot.resolved_backend` is `in_process`' "$file"
  grep -F 'If `snapshot.resolved_backend` is `tmux`' "$file"
  grep -F 'Do not call native Agent.' "$file"
  grep -F 'Schema 2 generation omits `--execution-backend`' "$file"
  ! grep -F 'MAIN_ID=main-session' "$file"
  ! grep -F '$AGENTS_JSON' "$file"
  ! grep -F 'Pane spawn is not wired' "$file"
}

@test "vibe execute wires schema 3 open flags and an explicit tmux spawn branch" {
  local vibe="$REPO_ROOT/commands/vibe.md"
  local proto="$REPO_ROOT/references/vibe-mode-execute.md"

  grep -F -- '--assert-snapshot' "$vibe"
  grep -F 'agent-generator.sh --execution-backend' "$vibe"
  grep -F 'Schema 2 generation omits `--execution-backend`' "$vibe"
  grep -F 'If `snapshot.resolved_backend` is `in_process`' "$vibe"
  grep -F 'If `snapshot.resolved_backend` is `tmux`' "$vibe"
  grep -F 'references/tmux-spawn-protocol.md' "$vibe"
  grep -F 'Do not call native Agent.' "$vibe"
  grep -F '.runtime-cancelled.json' "$vibe"
  ! grep -F 'Pane spawn is not wired' "$vibe"

  grep -F -- '--requested-backend' "$proto"
  grep -F -- '--resolved-backend' "$proto"
  grep -F -- '--control-root' "$proto"
  grep -F -- '--assert-snapshot' "$proto"
  grep -F '[ -f "$SNAPSHOT_PATH" ]' "$proto"
  grep -F 'agent-generator.sh --execution-backend' "$proto"
  grep -F 'Schema 2 generation omits `--execution-backend`' "$proto"
  grep -F 'references/tmux-spawn-protocol.md' "$proto"
  grep -F 'tmux-spawn-group.sh" dispatch' "$proto"
  grep -F 'CLAUDE_SESSION_ID' "$proto"
  grep -F 'Spawn path (hard branch)' "$proto"
  grep -F 'If `snapshot.resolved_backend` is `in_process`' "$proto"
  grep -F 'If `snapshot.resolved_backend` is `tmux`' "$proto"
  grep -F 'Do not call native Agent.' "$proto"
  grep -F '.runtime-cancelled.json' "$proto"
  ! grep -F 'MAIN_ID=main-session' "$proto"
  ! grep -F '$AGENTS_JSON' "$proto"
  ! grep -F 'Pane spawn is not wired' "$proto"
}
