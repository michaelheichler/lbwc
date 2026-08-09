#!/usr/bin/env bats

load test_helper

FIXTURE_DIR="$BATS_TEST_DIRNAME/fixtures/phase-detect-output"
FIXTURE_BUILDER="$FIXTURE_DIR/setup-case.bash"

setup() {
  setup_temp_dir
  export CLAUDE_SESSION_ID="phase-detect-output-${BATS_TEST_NUMBER:-0}-$$-$RANDOM"
  ACTUAL_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/lbwc-phase-detect-output.XXXXXX")
  export ACTUAL_OUTPUT
  cd "$TEST_TEMP_DIR"
}

teardown() {
  rm -f "$ACTUAL_OUTPUT"
  rm -f "/tmp/.lbwc-phase-detect-${CLAUDE_SESSION_ID:-default}.txt" 2>/dev/null || true
  rm -rf "/tmp/.lbwc-phase-detect-live-${CLAUDE_SESSION_ID:-default}.lock" 2>/dev/null || true
  rm -rf "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}" 2>/dev/null || true
  unset CLAUDE_SESSION_ID ACTUAL_OUTPUT
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

run_output_fixture() {
  local case_name="$1"

  bash "$FIXTURE_BUILDER" "$case_name"
  bash "$SCRIPTS_DIR/phase-detect.sh" > "$ACTUAL_OUTPUT"
  grep -q '^phase_detect_complete=true$' "$ACTUAL_OUTPUT"
}

assert_output_fixture() {
  local case_name="$1"
  local expected="$FIXTURE_DIR/$case_name.txt"

  run_output_fixture "$case_name"
  if ! cmp -s "$expected" "$ACTUAL_OUTPUT"; then
    diff -u "$expected" "$ACTUAL_OUTPUT"
    return 1
  fi
}

@test "output contract: no planning directory" {
  assert_output_fixture no-planning
}

@test "output contract: unplanned phase" {
  assert_output_fixture unplanned
}

@test "output contract: incomplete phase" {
  assert_output_fixture incomplete
}

@test "output contract: all phases done" {
  assert_output_fixture all-done
}

@test "output contract: UAT issue routing" {
  assert_output_fixture uat-issues
}

@test "output contract: active QA remediation" {
  assert_output_fixture qa-remediation
}

@test "output contract: milestone UAT recovery" {
  assert_output_fixture milestone-recovery
}

@test "output contract: legacy default milestone is query-only" {
  mkdir -p .lbwc-planning/milestones/default/phases/01-legacy-phase

  bash "$SCRIPTS_DIR/phase-detect.sh" > "$ACTUAL_OUTPUT"

  grep -q '^phase_detect_complete=true$' "$ACTUAL_OUTPUT"
  grep -q '^needs_milestone_rename=true$' "$ACTUAL_OUTPUT"
  [ -d .lbwc-planning/milestones/default ]
  [ -d .lbwc-planning/milestones/default/phases/01-legacy-phase ]
}

@test "output contract: current-round QA PASS satisfies a terminal partial phase" {

  assert_output_fixture phase-05-remediated
  grep -q '^next_phase_state=all_done$' "$ACTUAL_OUTPUT"
  grep -q '^next_phase_summaries=0$' "$ACTUAL_OUTPUT"
}

@test "output contract: current-round QA PASS cannot mask a terminal failed phase" {
  assert_output_fixture failed-summary-passing-remediation
  grep -q '^next_phase_state=needs_execute$' "$ACTUAL_OUTPUT"
  ! grep -q '^next_phase_state=all_done$' "$ACTUAL_OUTPUT"
}

@test "output contract: earlier-round PASS cannot mask current-round FAIL" {
  run_output_fixture stale-pass-later-fail
  grep -q '^next_phase_state=needs_execute$' "$ACTUAL_OUTPUT"
  ! grep -q '^next_phase_state=all_done$' "$ACTUAL_OUTPUT"
}
