#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS="$REPO_ROOT/scripts"
  TEST_ROOT="$(mktemp -d)"
  PHASE_DIR="$TEST_ROOT/.lbwc-planning/phases/01-checkout"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "uat-remediation-state initializes the authoritative round state" {
  run bash "$SCRIPTS/uat-remediation-state.sh" init "$PHASE_DIR" major

  [ "$status" -eq 0 ]
  [[ "$output" == *"research"* ]]
  [[ "$output" == *"round=01"* ]]
  [ -f "$PHASE_DIR/remediation/uat/.uat-remediation-stage" ]
  grep -q '^stage=research$' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  grep -q '^layout=round-dir$' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
}

@test "extract-uat-resume selects the current round UAT artifact" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=verify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  printf '%s\n' '---' 'status: in_progress' '---' '# UAT' > "$PHASE_DIR/remediation/uat/round-01/R01-UAT.md"

  run bash "$SCRIPTS/extract-uat-resume.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"uat_path=$PHASE_DIR/remediation/uat/round-01/R01-UAT.md"* ]]
}

@test "finalize-uat-status rejects unfinished checkpoints" {
  UAT="$PHASE_DIR/01-UAT.md"
  printf '%s\n' '---' 'status: in_progress' '---' '### P1: Checkout' '- **Result:** pass' '### P2: Receipt' > "$UAT"

  run bash "$SCRIPTS/finalize-uat-status.sh" "$UAT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing Result line"* ]]
}

@test "validate artifact rejects a plan outside the active round" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=plan\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  printf '%s\n' '---' 'phase: 01' '---' '# Plan' > "$PHASE_DIR/R01-PLAN.md"

  run bash "$SCRIPTS/validate-uat-remediation-artifact.sh" plan "$PHASE_DIR/R01-PLAN.md"

  [ "$status" -ne 0 ]
  [[ "$output" == *"artifact_valid=false"* ]]
}

@test "compile UAT verification context selects remediation-only while active" {
  mkdir -p "$PHASE_DIR/remediation/uat/round-01"
  printf 'stage=execute\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  printf '%s\n' '---' 'plan: 01-01' '---' '# Plan' > "$PHASE_DIR/remediation/uat/round-01/R01-PLAN.md"

  run bash "$SCRIPTS/compile-verify-context-for-uat.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_scope=remediation"* ]]
}

@test "create remediation phase seeds LBWC roadmap and is idempotent" {
  local planning_dir="$TEST_ROOT/.lbwc-planning"
  local archived_phase="$planning_dir/milestones/v1/phases/02-checkout"
  rm -rf "$PHASE_DIR"
  mkdir -p "$archived_phase"
  printf '%s\n' '# Test Project' > "$planning_dir/PROJECT.md"
  printf '%s\n' '---' 'status: issues_found' '---' '# UAT' > "$archived_phase/02-UAT.md"

  run bash "$SCRIPTS/create-remediation-phase.sh" "$planning_dir" "$archived_phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"phase=01"* ]]
  [ -f "$planning_dir/phases/01-remediate-v1-checkout/01-CONTEXT.md" ]
  [ -f "$planning_dir/phases/01-remediate-v1-checkout/01-SOURCE-UAT.md" ]
  grep -q '^# UAT Remediation Roadmap$' "$planning_dir/ROADMAP.md"
  grep -q '^\*\*Milestone:\*\* UAT Remediation$' "$planning_dir/STATE.md"

  run bash "$SCRIPTS/create-remediation-phase.sh" "$planning_dir" "$archived_phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"phase=01"* ]]
  [ "$(find "$planning_dir/phases" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -eq 1 ]
}
