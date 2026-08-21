#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/debug.md"
}

@test "debug command documents the workflow execution option and its spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Choose the execution backend' "$COMMAND"
  grep -F 'Implementation execution' "$COMMAND"
  grep -F 'Where should this implementation run? Workflow run applies it through a committed background script. Native spawn keeps the current single-agent implementation.' "$COMMAND"
  grep -F '`Workflow run`: Apply the fix through a committed workflow script in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native implementation spawn.' "$COMMAND"
  grep -F '`Cancel implementation`: Investigate but do not apply this fix now.' "$COMMAND"
  grep -F 'workflow-generator.sh' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
}

@test "debug command binds NAME from the generator's own SPAWN_READY output before using it" {
  grep -F 'GENERATOR_OUTPUT=$(bash "{plugin-root}/scripts/agent-generator.sh" debugger' "$COMMAND"
  grep -F "NAME=\$(printf '%s\\n' \"\$GENERATOR_OUTPUT\" | awk '/^SPAWN_READY/{print \$2}')" "$COMMAND"
}

@test "debug command scopes the workflow gate to the implementation spawn only" {
  grep -F 'This gate applies only to this implementation spawn. The read-only investigation debuggers above always spawn `in_process`.' "$COMMAND"
}

@test "debug command's workflow capability gate skips on an uninitialized project" {
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.' "$COMMAND"
}

@test "debug command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}
