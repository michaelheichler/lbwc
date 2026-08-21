#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/map.md"
}

generate_map_scout_workflow() {
  local domain="$1" project control_root contract task_id agen_out name wgen_out
  project="$TEST_TEMP_DIR/project-$domain"
  mkdir -p "$project/.lbwc-planning"
  control_root="$project/.temporary-agent-runfiles/runs/map-$domain"
  mkdir -p "$control_root"
  jq -n '{workflow_execution:{enabled:true}}' > "$control_root/config.json"
  jq -n '{workflow:{available:true, unavailable_reasons:[]}}' > "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$project" "map-$domain" \
    --command map --role scout --team solo --job "map $domain for the fixture project" \
    --group fixed \
    --control-root "$control_root" --requested-backend workflow --resolved-backend workflow \
    --read-only-role scout) || return 1
  task_id=$(basename "$contract" .json)
  agen_out=$(bash "$SCRIPTS_DIR/agent-generator.sh" scout \
    --job "map $domain for the fixture project" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --execution-backend workflow 2>&1) || { printf '%s\n' "$agen_out" >&2; return 1; }
  name=$(grep '^SPAWN_READY' <<< "$agen_out" | awk '{print $2}')
  [ -n "$name" ] || return 1
  wgen_out=$(bash "$SCRIPTS_DIR/workflow-generator.sh" solo scout \
    --job "map $domain for the fixture project" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --name "$name" 2>&1) || { printf '%s\n' "$wgen_out" >&2; return 1; }
  printf '%s\n' "$wgen_out"
}

@test "map command's read-only workflow Scout contract issues, generates, and registers end to end" {
  setup_temp_dir
  run generate_map_scout_workflow "tech-and-architecture"
  teardown_temp_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *'WORKFLOW_READY'* ]]
  [[ "$output" == *'scriptPath'* ]] || [[ "$output" == *'path:'* ]]
}

@test "map command documents the workflow execution option and its per-Scout spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Choose the execution backend (duo and quad only)' "$COMMAND"
  grep -F 'Map execution' "$COMMAND"
  grep -F 'Where should Scout evidence gathering run? Workflow run orchestrates each Scout through a committed background script. Native spawn keeps the current multi-agent Scout spawn.' "$COMMAND"
  grep -F '`Workflow run`: Gather evidence through committed workflow scripts in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native Scout spawn.' "$COMMAND"
  grep -F '`Cancel mapping`: Do not map this codebase now.' "$COMMAND"
  grep -F 'workflow-generator.sh" solo scout' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
}

@test "map command scopes the execution-backend choice away from the solo tier" {
  grep -F 'Solo-tier mapping analyzes inline and spawns no Scout, so this choice never applies to it.' "$COMMAND"
}

@test "map command declares every workflow Scout contract read-only instead of a fabricated write capability" {
  grep -F -- '--read-only-role scout' "$COMMAND"
  grep -F -- '--control-root "$CONTROL_ROOT"' "$COMMAND"
  ! grep -F -- '--write-capability' "$COMMAND"
  ! grep -F 'carries no write capability' "$COMMAND"
  ! grep -F 'carries a write capability' "$COMMAND"
}

@test "map command launches every duo or quad Scout before waiting on any of them" {
  grep -F 'Launch both Scout runs before waiting on either.' "$COMMAND"
  grep -F 'Launch all four Scout runs before waiting on any of them.' "$COMMAND"
}

@test "map command's workflow capability gate skips on an uninitialized project" {
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.' "$COMMAND"
}

@test "map command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}
