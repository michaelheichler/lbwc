#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  PROTOCOL="$REPO_ROOT/references/workflow-spawn-protocol.md"
}

@test "workflow spawn protocol scopes the frozen-snapshot clause to every current frozen-snapshot caller" {
  grep -F 'either through a frozen runtime snapshot (`team`, `build`, and Execute mode in `vibe`)' "$PROTOCOL"
}

@test "workflow spawn protocol documents the shared solo backend resolution step" {
  grep -F '0. **Resolving the backend for a solo, non-team-snapshot command.**' "$PROTOCOL"
  grep -F '.agent_execution_mode' "$PROTOCOL"
  grep -F '.workflow.available' "$PROTOCOL"
  grep -F '.workflow.unavailable_reasons' "$PROTOCOL"
  grep -F 'There is no automatic fallback from a requested `workflow`.' "$PROTOCOL"
  grep -F 'workflow backend is disabled in configuration' "$PROTOCOL"
  grep -F 'Workflow run' "$PROTOCOL"
  grep -F 'Native spawn' "$PROTOCOL"
}

@test "workflow spawn protocol only offers the ask-mode question when the backend can actually run" {
  grep -F 'WORKFLOW_ENABLED=$(jq -r' "$PROTOCOL"
  grep -F 'When `EXEC_MODE` is `ask` and both `WORKFLOW_AVAILABLE` and `WORKFLOW_ENABLED` are `true`, ask one bounded question' "$PROTOCOL"
  grep -F 'or `EXEC_MODE=ask` when `WORKFLOW_AVAILABLE` or `WORKFLOW_ENABLED` is not `true`, keeps `RESOLVED_BACKEND=in_process` without asking' "$PROTOCOL"
}

@test "workflow spawn protocol documents that workflow-generator.sh re-validates the gate at generation time" {
  grep -F 'scripts/workflow-generator.sh` enforces it again immediately before every generation' "$PROTOCOL"
  grep -F 'CLAUDE_CODE_DISABLE_WORKFLOWS' "$PROTOCOL"
  grep -F 'CLAUDE_CODE_SUBAGENT_MODEL' "$PROTOCOL"
  grep -F 'applies to every caller including a solo command that never builds a frozen snapshot' "$PROTOCOL"
}

@test "workflow spawn protocol step 3 names WORKFLOW_READY by task id, not contract id" {
  grep -F 'followed by a `WORKFLOW_READY <task-id>` line' "$PROTOCOL"
  grep -F '`contract_id` and `task_identity` are distinct fields: the file name uses the contract id, the printed line names the task id.' "$PROTOCOL"
  grep -F 'into `<control-root>/workflows/<contract-id>.js`' "$PROTOCOL"
  ! grep -F 'WORKFLOW_READY <contract-id>' "$PROTOCOL"
}

@test "workflow spawn protocol step 7 names the entry asymmetry against native admission" {
  grep -F 'Entry is not simultaneous the way native admission is.' "$PROTOCOL"
  grep -F 'requires every admitted member spawned in one message, so a native or tmux pair or trio reaches `running` together' "$PROTOCOL"
  grep -F 'awaits the engineer'"'"'s `agent()` call before starting the critic'"'"'s' "$PROTOCOL"
  grep -F 'has at most one member `running` at any moment, entering `running` one member at a time in template order' "$PROTOCOL"
  grep -F 'is driven by the first admitted member reaching `running`, never by waiting for every admitted member to reach it' "$PROTOCOL"
}
