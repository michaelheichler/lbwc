#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/init.md"
}

generate_init_architect_workflow() {
  local project control_root contract task_id agen_out name wgen_out
  project="$TEST_TEMP_DIR/project-init"
  mkdir -p "$project/.lbwc-planning"
  control_root="$project/.temporary-agent-runfiles/runs/init-architect"
  mkdir -p "$control_root"
  jq -n '{workflow_execution:{enabled:true}}' > "$control_root/config.json"
  jq -n '{workflow:{available:true, unavailable_reasons:[]}}' > "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$project" "init-architect" \
    --command init --role architect --team solo --job "draft initial requirements and roadmap" \
    --group fixed \
    --control-root "$control_root" --requested-backend workflow --resolved-backend workflow \
    --read-only-role architect) || return 1
  task_id=$(basename "$contract" .json)
  agen_out=$(bash "$SCRIPTS_DIR/agent-generator.sh" architect \
    --job "draft initial requirements and roadmap" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --execution-backend workflow 2>&1) || { printf '%s\n' "$agen_out" >&2; return 1; }
  name=$(grep '^SPAWN_READY' <<< "$agen_out" | awk '{print $2}')
  [ -n "$name" ] || return 1
  wgen_out=$(bash "$SCRIPTS_DIR/workflow-generator.sh" solo architect \
    --job "draft initial requirements and roadmap" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --name "$name" 2>&1) || { printf '%s\n' "$wgen_out" >&2; return 1; }
  printf '%s\n' "$wgen_out"
}

@test "init command's read-only workflow Architect contract issues, generates, and registers end to end" {
  setup_temp_dir
  run generate_init_architect_workflow
  teardown_temp_dir
  [ "$status" -eq 0 ]
  [[ "$output" == *'WORKFLOW_READY'* ]]
  [[ "$output" == *'path:'* ]]
}

@test "init command documents the workflow execution option and its Architect spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Choose the execution backend.' "$COMMAND"
  grep -F 'Bootstrap execution' "$COMMAND"
  grep -F 'Where should the initial requirements and roadmap draft run? Workflow run orchestrates it through a committed background script. Native spawn keeps the current single-agent Architect spawn.' "$COMMAND"
  grep -F '`Workflow run`: Draft requirements and roadmap through a committed workflow script in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native Architect spawn.' "$COMMAND"
  grep -F '`Cancel bootstrap`: Stop before generating project-defining files.' "$COMMAND"
  grep -F 'workflow-generator.sh" solo architect' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
}

@test "init command declares the workflow Architect contract read-only instead of a fabricated write capability" {
  grep -F -- '--read-only-role architect' "$COMMAND"
  grep -F -- '--control-root "$CONTROL_ROOT"' "$COMMAND"
  ! grep -F -- '--write-capability' "$COMMAND"
  ! grep -F 'carries no write capability' "$COMMAND"
}

@test "init command's cancel path preserves the Step 1 scaffold and points to /lbwc:vibe" {
  grep -F 'Leave the Step 1 scaffold, config, routing, and any completed codebase mapping in place' "$COMMAND"
  grep -F 'point to `/lbwc:vibe` to complete planning from those placeholders.' "$COMMAND"
}

@test "init command documents that its only spawn always runs after the planning scaffold exists" {
  grep -F '## Workflow capability gate' "$COMMAND"
  grep -F "This command's only agent spawn, the Architect in Step 7c, always runs after Step 1's fail-closed sequence" "$COMMAND"
  grep -F 'The Guard below stops only when `.lbwc-planning/config.json` already exists' "$COMMAND"
}

@test "init command discloses that the workflow ask branch is unreachable on shipped defaults" {
  grep -F "Step 7c's \`ask\` branch is unreachable on the shipped default configuration." "$COMMAND"
  grep -F 'agent_execution_mode: "ask"' "$COMMAND"
  grep -F 'workflow_execution.enabled: false' "$COMMAND"
}

@test "init command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}
