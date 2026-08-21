#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/lbwc-config.sh"
  test_root=$(mktemp -d)
  TEST_ROOT="$(cd "$test_root" && pwd -P)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_config() {
  run bash "$SCRIPT" "$@"
}

@test "execution mode defaults to ask and persists tmux settings" {
  run_config init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .agent_execution_mode == "ask"
    and .tmux_execution.enabled == false
    and .tmux_execution.session_name_prefix == "lbwc"
    and .tmux_execution.max_agents == 3
    and .tmux_execution.attach_policy == "orchestrator_only"
    and (.tmux_execution | has("session_timeout_seconds") | not)
    and (.tmux_execution | has("pane_base_index") | not)
    and .tmux_execution.heartbeat_interval_seconds == 30
    and .tmux_execution.heartbeat_stale_seconds == 120
    and .tmux_execution.comms_latency_tolerance_ms == 5000
    and .tmux_execution.comms_fallback == "bus_only"
    and .tmux_execution.cleanup_policy == "kill_on_complete"
    and .tmux_execution.layout == "main-vertical"
    and .tmux_execution.restrictions.allow_nested_spawn == false
    and .tmux_execution.restrictions.allow_agent_git == false
    and .tmux_execution.restrictions.allow_agent_ask_user == false
    and .tmux_execution.restrictions.require_orchestrator_attach == true
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]

  tmux_settings=$(jq -c '.tmux_execution | .enabled = true | .max_agents = 4' "$PLANNING_DIR/config.json")
  run_config set-json "$PLANNING_DIR" tmux_execution "$tmux_settings"
  [ "$status" -eq 0 ]
  run_config set "$PLANNING_DIR" agent_execution_mode '"tmux"'
  [ "$status" -eq 0 ]

  run_config get "$PLANNING_DIR" agent_execution_mode
  [ "$status" -eq 0 ]
  [ "$output" = '"tmux"' ]
  run jq -e '.tmux_execution.enabled == true and .tmux_execution.max_agents == 4' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "execution mode accepts workflow and persists workflow settings" {
  run_config init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '.workflow_execution.enabled == false' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]

  workflow_settings=$(jq -c '.workflow_execution | .enabled = true' "$PLANNING_DIR/config.json")
  run_config set-json "$PLANNING_DIR" workflow_execution "$workflow_settings"
  [ "$status" -eq 0 ]
  run_config set "$PLANNING_DIR" agent_execution_mode '"workflow"'
  [ "$status" -eq 0 ]

  run_config get "$PLANNING_DIR" agent_execution_mode
  [ "$status" -eq 0 ]
  [ "$output" = '"workflow"' ]
  run jq -e '.workflow_execution.enabled == true' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "execution mode rejects invalid values without changing configuration" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config set "$PLANNING_DIR" agent_execution_mode '"invalid"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid configuration"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "tmux settings reject invalid values without changing configuration" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  while IFS=$'\t' read -r setting literal; do
    before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    run_config set "$PLANNING_DIR" "$setting" "$literal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid configuration"* ]]
    after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
  done <<'VALUES'
tmux_execution.max_agents	5
tmux_execution.session_name_prefix	"bad/name"
tmux_execution.comms_fallback	"native"
VALUES
}

@test "migration fills missing execution settings and nested restrictions" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"schema_version":1,"agent_execution_mode":"tmux","tmux_execution":{"max_agents":4,"restrictions":{"allow_agent_git":true}}}' > "$PLANNING_DIR/config.json"

  run bash "$REPO_ROOT/scripts/migrate-config.sh" "$PLANNING_DIR/config.json"

  [ "$status" -eq 0 ]
  run jq -e '
    .agent_execution_mode == "tmux"
    and .tmux_execution.enabled == false
    and .tmux_execution.max_agents == 4
    and (.tmux_execution | has("session_timeout_seconds") | not)
    and (.tmux_execution | has("pane_base_index") | not)
    and .tmux_execution.restrictions.allow_agent_git == true
    and .tmux_execution.restrictions.allow_nested_spawn == false
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "migration strips unused tmux session_timeout_seconds and pane_base_index" {
  mkdir -p "$PLANNING_DIR"
  run bash "$SCRIPT" default-config
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$PLANNING_DIR/config.json"
  jq '.tmux_execution.session_timeout_seconds = 14400 | .tmux_execution.pane_base_index = 1' \
    "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"

  run bash "$REPO_ROOT/scripts/migrate-config.sh" "$PLANNING_DIR/config.json"

  [ "$status" -eq 0 ]
  run jq -e '
    (.tmux_execution | has("session_timeout_seconds") | not)
    and (.tmux_execution | has("pane_base_index") | not)
    and .tmux_execution.layout == "main-vertical"
    and .tmux_execution.max_agents == 3
    and .tmux_execution.heartbeat_interval_seconds == 30
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "unused tmux keys are not writable and extra keys fail validation" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config set "$PLANNING_DIR" tmux_execution.session_timeout_seconds '14400'
  [ "$status" -ne 0 ]
  [[ "$output" == *"setting is not writable"* ]]
  run_config set "$PLANNING_DIR" tmux_execution.pane_base_index '1'
  [ "$status" -ne 0 ]
  [[ "$output" == *"setting is not writable"* ]]

  tmux_settings=$(jq -c '.tmux_execution | .session_timeout_seconds = 14400' "$PLANNING_DIR/config.json")
  run_config set-json "$PLANNING_DIR" tmux_execution "$tmux_settings"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "unused workflow keys are not writable and extra keys fail validation" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config set "$PLANNING_DIR" workflow_execution.size_guideline '"medium"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"setting is not writable"* ]]

  workflow_settings=$(jq -c '.workflow_execution | .size_guideline = "medium"' "$PLANNING_DIR/config.json")
  run_config set-json "$PLANNING_DIR" workflow_execution "$workflow_settings"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "migration fills a missing workflow_execution block with defaults" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"schema_version":1,"agent_execution_mode":"workflow"}' > "$PLANNING_DIR/config.json"

  run bash "$REPO_ROOT/scripts/migrate-config.sh" "$PLANNING_DIR/config.json"

  [ "$status" -eq 0 ]
  run jq -e '
    .agent_execution_mode == "workflow"
    and .workflow_execution.enabled == false
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "migration rejects invalid existing tmux execution settings without changing the configuration" {
  mkdir -p "$PLANNING_DIR"
  run bash "$SCRIPT" default-config
  [ "$status" -eq 0 ]
  default_config="$output"

  while IFS=$'\t' read -r setting literal; do
    printf '%s\n' "$default_config" > "$PLANNING_DIR/config.json"
    jq --arg setting "$setting" --argjson value "$literal" 'setpath($setting | split("."); $value)' \
      "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
    mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
    before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

    run bash "$REPO_ROOT/scripts/migrate-config.sh" "$PLANNING_DIR/config.json"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Config migration failed"* ]]
    after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
  done <<'VALUES'
tmux_execution.enabled	"true"
tmux_execution.session_name_prefix	"bad/name"
tmux_execution.max_agents	0
tmux_execution.max_agents	5
tmux_execution.attach_policy	"all"
tmux_execution.heartbeat_interval_seconds	0
tmux_execution.heartbeat_stale_seconds	0
tmux_execution.comms_latency_tolerance_ms	0
tmux_execution.comms_fallback	"native"
tmux_execution.cleanup_policy	"retain"
tmux_execution.layout	"stacked"
tmux_execution.restrictions	false
tmux_execution.restrictions.unexpected	true
tmux_execution.restrictions.allow_nested_spawn	"false"
tmux_execution.restrictions.allow_agent_git	"false"
tmux_execution.restrictions.allow_agent_ask_user	"false"
tmux_execution.restrictions.require_orchestrator_attach	"true"
tmux_execution.unexpected	true
VALUES
}

@test "execution mode changes are frozen while a plan is active" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"

  run_config set "$PLANNING_DIR" agent_execution_mode '"tmux"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
}

@test "active execution permits cleanup policy but freezes other tmux settings" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"

  run_config set "$PLANNING_DIR" tmux_execution.cleanup_policy '"keep_panes"'
  [ "$status" -eq 0 ]
  run jq -e '.tmux_execution.cleanup_policy == "keep_panes"' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]

  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  run_config set "$PLANNING_DIR" tmux_execution.layout '"tiled"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "workflow_execution.enabled is writable then frozen while a plan is active" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  run_config set "$PLANNING_DIR" workflow_execution.enabled 'true'
  [ "$status" -eq 0 ]
  run jq -e '.workflow_execution.enabled == true' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]

  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config set "$PLANNING_DIR" workflow_execution.enabled 'false'

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "valid non-running tmux registry states permit an active in-process emergency switch" {
  local state state_planning_dir

  for state in registered idle failed shutdown; do
    state_planning_dir="$TEST_ROOT/$state/.lbwc-planning"
    run_config init "$state_planning_dir"
    [ "$status" -eq 0 ]
    run_config set "$state_planning_dir" agent_execution_mode '"tmux"'
    [ "$status" -eq 0 ]
    printf '%s\n' '{"status":"executing"}' > "$state_planning_dir/.execution-state.json"
    mkdir -p "$state_planning_dir/.runtime/tmux-bus"
    printf '{"agents":[{"state":"%s"}]}\n' "$state" > "$state_planning_dir/.runtime/tmux-bus/registry.json"

    run_config set "$state_planning_dir" agent_execution_mode '"in_process"'

    [ "$status" -eq 0 ]
    run jq -e '.agent_execution_mode == "in_process"' "$state_planning_dir/config.json"
    [ "$status" -eq 0 ]
  done
}

@test "running tmux registry agents block an active in-process emergency switch" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  run_config set "$PLANNING_DIR" agent_execution_mode '"tmux"'
  [ "$status" -eq 0 ]
  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"
  mkdir -p "$PLANNING_DIR/.runtime/tmux-bus"
  printf '%s\n' '{"agents":[{"state":"running"}]}' > "$PLANNING_DIR/.runtime/tmux-bus/registry.json"

  run_config set "$PLANNING_DIR" agent_execution_mode '"in_process"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  run jq -e '.agent_execution_mode == "tmux"' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "malformed tmux registry blocks an active in-process emergency switch" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  run_config set "$PLANNING_DIR" agent_execution_mode '"tmux"'
  [ "$status" -eq 0 ]
  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"
  mkdir -p "$PLANNING_DIR/.runtime/tmux-bus"
  printf '%s\n' '{not valid json' > "$PLANNING_DIR/.runtime/tmux-bus/registry.json"

  run_config set "$PLANNING_DIR" agent_execution_mode '"in_process"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  run jq -e '.agent_execution_mode == "tmux"' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "structurally invalid tmux registry entries block an active in-process emergency switch" {
  local registry

  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  run_config set "$PLANNING_DIR" agent_execution_mode '"tmux"'
  [ "$status" -eq 0 ]
  printf '%s\n' '{"status":"executing"}' > "$PLANNING_DIR/.execution-state.json"
  mkdir -p "$PLANNING_DIR/.runtime/tmux-bus"

  for registry in '{"agents":[null]}' '{"agents":[{}]}' '{"agents":[{"state":"unknown"}]}' '{"agents":[{"state":"used"}]}' '{"agents":[{"state":"expired"}]}'; do
    printf '%s\n' "$registry" > "$PLANNING_DIR/.runtime/tmux-bus/registry.json"

    run_config set "$PLANNING_DIR" agent_execution_mode '"in_process"'

    [ "$status" -ne 0 ]
    [[ "$output" == *"frozen"* ]]
    run jq -e '.agent_execution_mode == "tmux"' "$PLANNING_DIR/config.json"
    [ "$status" -eq 0 ]
  done
}
