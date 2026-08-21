#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/research.md"
}

generate_research_scout_workflow() {
  local facet="$1" project control_root contract task_id agen_out name wgen_out
  project="$TEST_TEMP_DIR/project-$facet"
  mkdir -p "$project/.lbwc-planning"
  control_root="$project/.temporary-agent-runfiles/runs/research-$facet"
  mkdir -p "$control_root"
  jq -n '{workflow_execution:{enabled:true}}' > "$control_root/config.json"
  jq -n '{workflow:{available:true, unavailable_reasons:[]}}' > "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$project" "research-$facet" \
    --command research --role scout --team solo --job "research: $facet" \
    --group fixed \
    --control-root "$control_root" --requested-backend workflow --resolved-backend workflow \
    --read-only-role scout) || return 1
  task_id=$(basename "$contract" .json)
  agen_out=$(bash "$SCRIPTS_DIR/agent-generator.sh" scout \
    --job "research: $facet" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --execution-backend workflow 2>&1) || { printf '%s\n' "$agen_out" >&2; return 1; }
  name=$(grep '^SPAWN_READY' <<< "$agen_out" | awk '{print $2}')
  [ -n "$name" ] || return 1
  wgen_out=$(bash "$SCRIPTS_DIR/workflow-generator.sh" solo scout \
    --job "research: $facet" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --name "$name" 2>&1) || { printf '%s\n' "$wgen_out" >&2; return 1; }
  printf '%s\n' "$wgen_out"
}

@test "research command's read-only workflow Scout contract issues, generates, and registers end to end" {
  setup_temp_dir
  run generate_research_scout_workflow "narrow-question"
  teardown_temp_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *'WORKFLOW_READY'* ]]
  [[ "$output" == *'path:'* ]]
}

@test "research command documents the workflow execution option and its per-facet spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Choose the execution backend' "$COMMAND"
  grep -F 'Research execution' "$COMMAND"
  grep -F 'Where should this research run? Workflow run orchestrates each Scout through a committed background script. Native spawn keeps the current Scout spawn.' "$COMMAND"
  grep -F '`Workflow run`: Research through committed workflow scripts in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native Scout spawn.' "$COMMAND"
  grep -F '`Cancel research`: Do not research this topic now.' "$COMMAND"
  grep -F 'workflow-generator.sh" solo scout' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
}

@test "research command declares every workflow Scout contract read-only instead of a fabricated write capability" {
  grep -F -- '--read-only-role scout' "$COMMAND"
  grep -F -- '--control-root "$CONTROL_ROOT"' "$COMMAND"
  ! grep -F -- '--write-capability' "$COMMAND"
  ! grep -F "carries a write capability" "$COMMAND"
}

@test "research command launches every facet's workflow run before waiting on any of them" {
  grep -F 'Launch every facet' "$COMMAND"
}

@test "research command's workflow capability gate skips on an uninitialized project" {
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.' "$COMMAND"
}

@test "research command renumbers steps after inserting the execution-backend choice" {
  grep -F '3. **Choose the execution backend:**' "$COMMAND"
  grep -F '4. **Spawn Scout:**' "$COMMAND"
  grep -F '5. **Synthesize:**' "$COMMAND"
  grep -F '6. **Persist:**' "$COMMAND"
}

@test "research command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}
