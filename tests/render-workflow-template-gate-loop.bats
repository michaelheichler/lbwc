#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/render-workflow-template.sh"
  OUT_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$OUT_DIR"
}

HARNESS="$BATS_TEST_DIRNAME/fixtures/workflow-harness.cjs"

render_pair() {
  local autonomy="$1" job="${2:-job}"
  run bash "$SCRIPT" pair NAME=probe-pair DESCRIPTION=desc \
    "JOB=$job" TASK_ID=task-2 "AUTONOMY=$autonomy" \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast
}

render_trio() {
  local autonomy="$1" job="${2:-job}"
  run bash "$SCRIPT" trio NAME=probe-trio DESCRIPTION=desc \
    "JOB=$job" TASK_ID=task-3 "AUTONOMY=$autonomy" \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast \
    TESTDEV_AGENT_TYPE=lbwc-td-a TESTDEV_MODEL=sonnet TESTDEV_EFFORT=fast
}

run_workflow() {
  local rendered_file="$1" responses_json="$2"
  run node "$HARNESS" "$rendered_file" "$responses_json"
}

agent_labels() {
  jq -r '.agentCalls | map(.label) | join(",")' <<< "$output"
}

@test "pair template: PASS on round 1 exits after one engineer and one critic call" {
  render_pair standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-exec.mjs"

  run_workflow "$OUT_DIR/pair-exec.mjs" '[{"n":1},{"verdict":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,critic" ]
  [ "$(jq -r '.agentCalls[1].hasSchema' <<< "$output")" = true ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
  [ "$(jq -r '.result.round' <<< "$output")" = 1 ]
}

@test "pair template: three BLOCK rounds under AUTONOMY=standard emit user_decision_required" {
  render_pair standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-exec.mjs"

  local responses='[{"n":1},{"verdict":"BLOCK"},{"n":2},{"verdict":"BLOCK"},{"n":3},{"verdict":"BLOCK","findings":"round 3 findings"}]'
  run_workflow "$OUT_DIR/pair-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,critic,engineer,critic,engineer,critic" ]
  [ "$(jq -r '.result | keys | sort | join(",")' <<< "$output")" = "choices,context,decision,question,status" ]
  [ "$(jq -r '.result.status' <<< "$output")" = user_decision_required ]
  [ "$(jq -r '.result.decision' <<< "$output")" = workflow_gate_unresolved ]
  [ "$(jq -r '.result.context | type' <<< "$output")" = string ]
  [ "$(jq -r '.result.context' <<< "$output")" = "round 3 findings" ]
  choice_count=$(jq -r '.result.choices | length' <<< "$output")
  [ "$choice_count" -ge 2 ]
  [ "$choice_count" -le 4 ]
  [[ "$(jq -r '.result.question' <<< "$output")" == *"Round 3"* ]]
}

@test "pair template: AUTONOMY=pure-vibe does not stop at round 3" {
  render_pair pure-vibe
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-exec.mjs"

  local responses='[{"n":1},{"verdict":"BLOCK"},{"n":2},{"verdict":"BLOCK"},{"n":3},{"verdict":"BLOCK"},{"n":4},{"verdict":"PASS"}]'
  run_workflow "$OUT_DIR/pair-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,critic,engineer,critic,engineer,critic,engineer,critic" ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
  [ "$(jq -r '.result.round' <<< "$output")" = 4 ]
}

@test "pair template: a BLOCK verdict whose findings text contains the word PASS is still scored BLOCK" {
  render_pair standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-exec.mjs"

  local findings='1. (blocking) The variant does not decrease. Fix: tighten the guard split.\nVERDICT: BLOCK. Flips on: fix 1 so tests/guard.bats can pass.\nGrounding: discipline-of-programming-dijkstra/SKILL.md.'
  local round1="{\"verdict\":\"BLOCK\",\"findings\":\"$findings\"}"
  local responses="[{\"n\":1},$round1,{\"n\":2},{\"verdict\":\"PASS\"}]"
  run_workflow "$OUT_DIR/pair-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,critic,engineer,critic" ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
  [ "$(jq -r '.result.round' <<< "$output")" = 2 ]
}

@test "trio template: PASS on round 1 exits after one engineer, one test-dev and one critic call" {
  render_trio standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-exec.mjs"

  run_workflow "$OUT_DIR/trio-exec.mjs" '[{"n":1},{"t":1},{"verdict":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,test-dev,critic" ]
  [ "$(jq -r '.agentCalls[2].hasSchema' <<< "$output")" = true ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
}

@test "trio template: an OWNER SOURCE verdict reruns only the engineer on round 2" {
  render_trio standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-exec.mjs"

  local responses='[{"n":1},{"t":1},{"verdict":"BLOCK","owner":"SOURCE"},{"n":2},{"verdict":"PASS"}]'
  run_workflow "$OUT_DIR/trio-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,test-dev,critic,engineer,critic" ]
}

@test "trio template: an OWNER TESTS verdict reruns only test-dev on round 2" {
  render_trio standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-exec.mjs"

  local responses='[{"n":1},{"t":1},{"verdict":"BLOCK","owner":"TESTS"},{"t":2},{"verdict":"PASS"}]'
  run_workflow "$OUT_DIR/trio-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,test-dev,critic,test-dev,critic" ]
}

@test "trio template: a BLOCK with no owner field reruns both engineer and test-dev on round 2" {
  render_trio standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-exec.mjs"

  local responses='[{"n":1},{"t":1},{"verdict":"BLOCK"},{"n":2},{"t":2},{"verdict":"PASS"}]'
  run_workflow "$OUT_DIR/trio-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,test-dev,critic,engineer,test-dev,critic" ]
}

@test "trio template: three BLOCK rounds under AUTONOMY=standard emit user_decision_required" {
  render_trio standard
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-exec.mjs"

  local responses='[{"n":1},{"t":1},{"verdict":"BLOCK"},{"n":2},{"t":2},{"verdict":"BLOCK"},{"n":3},{"t":3},{"verdict":"BLOCK","findings":"round 3 findings"}]'
  run_workflow "$OUT_DIR/trio-exec.mjs" "$responses"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.result.status' <<< "$output")" = user_decision_required ]
  [ "$(jq -r '.result.context | type' <<< "$output")" = string ]
  [ "$(jq -r '.result.context' <<< "$output")" = "round 3 findings" ]
  [[ "$(jq -r '.result.question' <<< "$output")" == *"Round 3"* ]]
}
