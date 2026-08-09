#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/verify-state-consistency.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_verify() {
  (cd "$REPO_ROOT" && LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT")
}

make_minimal_project() {
  mkdir -p "$PLANNING_DIR/phases/01-test"
  printf 'Phase: 1 of 1 (test)\nPlans: 0/0\n' > "$PLANNING_DIR/STATE.md"
  printf '# Roadmap\n\n### Phase 1: Test\n' > "$PLANNING_DIR/ROADMAP.md"
}

@test "verify-state-consistency: no planning dir is clean" {
  run run_verify
  [ "$status" -eq 0 ]
  [ "$output" = "state_consistency=no_planning_dir" ]
}

@test "verify-state-consistency: minimal project is clean" {
  make_minimal_project
  run run_verify
  [ "$status" -eq 0 ]
  [ "$output" = "state_consistency=ok" ]
}

@test "verify-state-consistency: STATE Plans count drift is reported" {
  make_minimal_project
  : > "$PLANNING_DIR/phases/01-test/PLAN.md"
  run run_verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT STATE:"* ]]
}

@test "verify-state-consistency: missing remediation round is reported" {
  make_minimal_project
  mkdir -p "$PLANNING_DIR/phases/01-test/remediation/qa"
  printf 'stage=plan\nround=02\n' > "$PLANNING_DIR/phases/01-test/remediation/qa/.qa-remediation-stage"
  run run_verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT remediation:"* ]]
}

@test "verify-state-consistency: corrupted DevIQ chain is reported" {
  make_minimal_project
  mkdir -p "$PLANNING_DIR/deviq"
  printf '{"sha256":"bogus","prev_sha256":null}\n' > "$PLANNING_DIR/deviq/blocks.jsonl"
  run run_verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT deviq:"* ]]
}