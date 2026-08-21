#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  COMMAND="$REPO_ROOT/commands/vibe.md"
  EXECUTE_REF="$REPO_ROOT/references/vibe-mode-execute.md"
}

@test "vibe command documents the workflow execution option for Execute mode" {
  grep -F 'references/workflow-spawn-protocol.md' "$COMMAND"
  grep -F 'Execute execution' "$COMMAND"
  grep -F 'Where should this phase'"'"'s task groupings run? Workflow run orchestrates each grouping through a committed background script. Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.' "$COMMAND"
  grep -F '`Workflow run`: Run each grouping through a committed workflow script in the background.' "$COMMAND"
  grep -F '`Native spawn`: Keep the current native Agent spawn.' "$COMMAND"
  grep -F '`Cancel spawn`: Do not spawn any grouping for this execution.' "$COMMAND"
  grep -F 'If `snapshot.resolved_backend` is `workflow`, `{LINK}/references/vibe-mode-execute.md` follows `{LINK}/references/workflow-spawn-protocol.md` on this branch only.' "$COMMAND"
}

@test "vibe command's workflow capability gate is scoped to Execute mode and skips on an uninitialized project" {
  grep -F 'Refresh the saved Claude capability catalog before any Execute-mode grouping contract or spawn' "$COMMAND"
  grep -F 'Skip this gate when `.lbwc-planning/` is missing. Every other mode ignores this gate. Do not create a planning directory here.' "$COMMAND"
}

@test "vibe command's workflow capability gate stops on a failed refresh rather than silently falling back" {
  grep -F 'Stop before Execute mode when the helper exits non-zero.' "$COMMAND"
  ! grep -F 'A non-zero exit here does not stop mode selection.' "$COMMAND"
  ! grep -F 'by step 0 of `workflow-spawn-protocol.md`' "$COMMAND"
}

@test "vibe command allows Workflow in frontmatter" {
  grep -E '^allowed-tools:.*\bWorkflow\b' "$COMMAND"
}

@test "vibe command does not instruct the model to author a workflow" {
  run bash "$REPO_ROOT/scripts/command-contract.sh"
  [ "$status" -eq 0 ]
}

@test "vibe-mode-execute reference documents the workflow spawn path" {
  grep -F 'If `snapshot.resolved_backend` is `workflow`' "$EXECUTE_REF"
  grep -F 'workflow-generator.sh' "$EXECUTE_REF"
  grep -F 'WORKFLOW_READY' "$EXECUTE_REF"
  grep -F 'Never pass `script`' "$EXECUTE_REF"
  grep -F 'user_decision_required' "$EXECUTE_REF"
  grep -F 'Do not run `tmux-spawn-group.sh`.' "$EXECUTE_REF"
}

@test "vibe-mode-execute reference reads the manifest for state running but requires the terminal result before closure" {
  grep -F 'The manifest is still what `execute-protocol.md` reads for `state ... running`' "$EXECUTE_REF"
  grep -F 'workflow-probe-findings.md`, Unknown D' "$EXECUTE_REF"
  grep -F 'Closure is not read from the manifest alone.' "$EXECUTE_REF"
  grep -F 'The terminal result is what actually marks the grouping done.' "$EXECUTE_REF"
}

@test "vibe-mode-execute reference names the entry asymmetry as the mirror of the closure asymmetry" {
  grep -F 'but entry is not the same shape here' "$EXECUTE_REF"
  grep -F 'It fires only for the one member the template has started so far.' "$EXECUTE_REF"
  grep -F 'A native pair or trio reaches `running` together because of that.' "$EXECUTE_REF"
  grep -F 'A workflow pair or trio is therefore never more than one member `running` at once.' "$EXECUTE_REF"
  grep -F 'Run `state ... running` from that first `SubagentStart`, not from waiting on every admitted member to reach it' "$EXECUTE_REF"
}

@test "vibe command is registered in the command section contract" {
  jq -e '.commands["vibe.md"].required_headings == ["Shared interaction contract","Context","Input Parsing","Modes","Output Format"]' \
    "$REPO_ROOT/config/command-sections.json" >/dev/null
}
