#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/qa.md"
}

@test "qa command documents the workflow execution option and its spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Choose the execution backend' "$COMMAND"
  grep -F 'QA execution' "$COMMAND"
  grep -F 'Where should this QA verification run? Workflow run orchestrates it through a committed background script. Native spawn keeps the current single-agent QA run.' "$COMMAND"
  grep -F '`Workflow run`: Verify through a committed workflow script in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native QA spawn.' "$COMMAND"
  grep -F '`Cancel QA`: Do not verify this phase now.' "$COMMAND"
  grep -F 'workflow-generator.sh' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
  grep -F 'Debug-session QA in `<debug_session_qa>` always spawns `in_process`.' "$COMMAND"
}

@test "qa command binds NAME from the generator's own SPAWN_READY output before using it" {
  grep -F 'GENERATOR_OUTPUT=$(bash "{plugin-root}/scripts/agent-generator.sh" qa' "$COMMAND"
  grep -F "NAME=\$(printf '%s\\n' \"\$GENERATOR_OUTPUT\" | awk '/^SPAWN_READY/{print \$2}')" "$COMMAND"
}

@test "qa command grants no write capability to the read-only workflow QA contract" {
  ! grep -F -- '--write-capability' "$COMMAND"
  grep -F 'this contract carries no write capability' "$COMMAND"
}

@test "qa command's workflow capability gate skips on an uninitialized project" {
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.' "$COMMAND"
}

@test "qa command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}
