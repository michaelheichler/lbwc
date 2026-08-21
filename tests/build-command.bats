#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/build.md"
}

@test "build command documents the workflow execution option and its spawn branch" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Build execution' "$COMMAND"
  grep -F 'Where should this phase'"'"'s task groupings run? Workflow run orchestrates each grouping through a committed background script. Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.' "$COMMAND"
  grep -F '`Workflow run`: Run each grouping through a committed workflow script in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native Agent spawn.' "$COMMAND"
  grep -F '`Cancel spawn`: Do not spawn any grouping for this build.' "$COMMAND"
  grep -F 'workflow-generator.sh' "$COMMAND"
  grep -F 'WORKFLOW_READY' "$COMMAND"
  grep -F 'scriptPath' "$COMMAND"
  grep -F 'Never pass `script`' "$COMMAND"
  grep -F 'user_decision_required' "$COMMAND"
}

@test "build command keeps exclusive admission identical but flags the workflow closure signal as different" {
  grep -F 'This admission rule is identical under every resolved backend, including `workflow`, but a workflow grouping'"'"'s closure signal is not.' "$COMMAND"
  grep -F 'This is confirmed on the host, not assumed: see `references/workflow-probe-findings.md`, Unknown D.' "$COMMAND"
  grep -F 'so `used` is necessary but not sufficient for workflow closure' "$COMMAND"
  grep -F 'The manifest is not the sole admission authority for `workflow` the way it is for `in_process` and `tmux`.' "$COMMAND"
  grep -F 'No wave or cross-grouping ordering is ever delegated into a workflow script itself.' "$COMMAND"
}

@test "build command records the open item that --exclusive cannot detect an in-flight workflow grouping" {
  grep -F '**Open item.** `agent-generator.sh --exclusive` alone cannot detect an in-flight workflow grouping between remediation rounds.' "$COMMAND"
}

@test "build command's workflow branch reads the manifest for state running but requires the terminal result before closure" {
  grep -F 'The manifest is still what `state ... running` reads' "$COMMAND"
  grep -F 'Closure is not read from the manifest alone.' "$COMMAND"
  grep -F 'Observe the run'"'"'s own terminal `result` first' "$COMMAND"
  grep -F 'The terminal result is what actually marks the grouping done.' "$COMMAND"
}

@test "build command names the entry asymmetry as the mirror of the closure asymmetry" {
  grep -F 'Entry has the same asymmetry, mirrored.' "$COMMAND"
  grep -F 'A workflow pair or trio is therefore never more than one member `running` at once.' "$COMMAND"
  grep -F 'It enters `running` one member at a time, in template order.' "$COMMAND"
  grep -F 'After the manifest shows the first admitted member `running`, run `state ... running`.' "$COMMAND"
  grep -F 'For `workflow`, only the first admitted member has started (see the entry-asymmetry paragraph in Plan waves above).' "$COMMAND"
  grep -F 'Run `state ... running` from that first `SubagentStart`, not from waiting on every admitted member to reach it' "$COMMAND"
  ! grep -F 'the same `SubagentStart` hook that drives a native or TMUX member sets the admitted members to `running` here too' "$COMMAND"
  ! grep -F 'After the manifest shows the admitted members `running`, run `state ... running`.' "$COMMAND"
}

@test "build command reuses the same contract allowance args for every backend" {
  grep -F '`CONTRACT_ALLOWANCE_ARGS` is identical for every resolved backend, including `workflow`.' "$COMMAND"
}

@test "build command's TDD red stage supports the workflow backend" {
  grep -F 'On `workflow`, generate and dispatch the red stage exactly like any other grouping above' "$COMMAND"
}

@test "build command's workflow capability gate skips on an uninitialized project" {
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.' "$COMMAND"
}

@test "build command's workflow capability gate stops on a failed refresh rather than silently falling back" {
  grep -F 'bash "{LINK}/scripts/lbwc-model" refresh "{PROJECT_ROOT}/.lbwc-planning"' "$COMMAND"
  grep -F 'This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`' "$COMMAND"
  grep -F 'Stop before plan execution when the helper exits non-zero.' "$COMMAND"
  ! grep -F 'A non-zero exit here does not stop the build.' "$COMMAND"
  ! grep -F 'by step 0 of `workflow-spawn-protocol.md`' "$COMMAND"
}

@test "build command allows Workflow and AskUserQuestion in frontmatter" {
  grep -E '^allowed-tools:.*\bWorkflow\b' "$COMMAND"
  grep -E '^allowed-tools:.*\bAskUserQuestion\b' "$COMMAND"
}

@test "build command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}

@test "build command is registered in the command section contract" {
  jq -e '.commands["build.md"].required_headings == ["Context","Guard","Resolve the target phase","Plan waves","Select roles","Select the team shape","Main-session task contract and telemetry","Spawn and verify","Failure and recovery","Output Format","Next Up"]' \
    "$REPO_ROOT/config/command-sections.json" >/dev/null
}
