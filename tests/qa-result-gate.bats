#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/qa-result-gate.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_DIR="$(cd "$TEST_DIR" && pwd -P)"
  PHASE_DIR="$TEST_DIR/.lbwc-planning/phases/01-test-phase"
  mkdir -p "$PHASE_DIR" "$TEST_DIR/.lbwc-planning"
  printf '{}\n' > "$TEST_DIR/.lbwc-planning/config.json"
}

teardown() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

create_verif() {
  local writer="${1:-write-verification.sh}"
  local result="${2:-PASS}"
  local body="${3:-}"
  {
    echo "---"
    echo "phase: 01"
    echo "tier: full"
    echo "result: $result"
    echo "passed: 10"
    echo "failed: 0"
    echo "total: 10"
    echo "date: 2026-03-27"
    if [ "$writer" != "OMIT" ]; then
      echo "writer: $writer"
    fi
    echo "---"
    echo ""
    if [ -n "$body" ]; then
      printf '%s\n' "$body"
    fi
  } > "$PHASE_DIR/01-VERIFICATION.md"
}

@test "PASS with clean body -> PROCEED_TO_UAT" {
  create_verif "write-verification.sh" "PASS" "## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
  [[ "$output" == *"qa_gate_writer=write-verification.sh"* ]]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_fail_count=0"* ]]
}

@test "legacy status PASS without result -> PROCEED_TO_UAT" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'VERIF'
---
phase: 01
status: PASS
writer: write-verification.sh
---
## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "lowercase result pass is normalized before routing" {
  create_verif "write-verification.sh" "pass"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "mixed-case result partial is normalized before routing" {
  create_verif "write-verification.sh" "PaRtIaL"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=PARTIAL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "result field overrides conflicting legacy status" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'VERIF'
---
phase: 01
result: FAIL
status: PASS
writer: write-verification.sh
---
## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature failed | FAIL |
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
}

@test "blank result does not fall back to legacy status" {
  cat > "$PHASE_DIR/01-VERIFICATION.md" <<'VERIF'
---
phase: 01
result:
status: PASS
writer: write-verification.sh
---
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_result=missing"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PASS with FAIL rows in body -> REMEDIATION_REQUIRED (override)" {
  create_verif "write-verification.sh" "PASS" "## Must-Have Checks
| Check | Status |
|-------|--------|
| Feature works | PASS |
| Edge case | FAIL |"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_fail_count=1"* ]]
}

@test "PASS with flow-style YAML deviations -> QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  cat > "$PHASE_DIR/01-01-SUMMARY.md" <<'SUMMARY'
---
plan: 01-01
deviations: ["Changed API contract", 'Moved tests to existing file']
---

## Summary
Work completed.
SUMMARY

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_deviation_count=2"* ]]
  [[ "$output" == *"qa_gate_deviation_override=true"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "PARTIAL result -> REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "PARTIAL"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=PARTIAL"* ]]
}

@test "FAIL result -> REMEDIATION_REQUIRED" {
  create_verif "write-verification.sh" "FAIL"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=REMEDIATION_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=FAIL"* ]]
}

@test "wrong writer -> QA_RERUN_REQUIRED" {
  create_verif "manual-write" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=manual-write"* ]]
}

@test "missing writer field -> QA_RERUN_REQUIRED" {
  create_verif "OMIT" "PASS"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_writer=missing"* ]]
}

@test "missing VERIFICATION.md -> QA_RERUN_REQUIRED" {
  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
  [[ "$output" == *"qa_gate_result=missing"* ]]
}

@test "unknown result value -> QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "UNKNOWN_VALUE"

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "missing phase-dir argument -> QA_RERUN_REQUIRED" {
  run bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "custom verif-name argument" {
  create_verif "write-verification.sh" "PASS"
  mv "$PHASE_DIR/01-VERIFICATION.md" "$PHASE_DIR/CUSTOM-VERIF.md"

  run bash "$SCRIPT" "$PHASE_DIR" "CUSTOM-VERIF.md"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_routing=PROCEED_TO_UAT"* ]]
}

@test "PASS with unmet plan coverage -> QA_RERUN_REQUIRED" {
  create_verif "write-verification.sh" "PASS"
  cat > "$PHASE_DIR/01-01-PLAN.md" <<'PLAN'
Plan stub
PLAN
  cat > "$PHASE_DIR/01-02-PLAN.md" <<'PLAN'
Plan stub
PLAN

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_plan_count=2"* ]]
  [[ "$output" == *"qa_gate_plans_verified_count=0"* ]]
  [[ "$output" == *"qa_gate_routing=QA_RERUN_REQUIRED"* ]]
}

@test "UAT remediation scope selects its current round verification" {
  local round_dir="$PHASE_DIR/remediation/uat/round-01"
  mkdir -p "$round_dir"
  printf 'stage=verify\nround=01\nlayout=round-dir\n' > "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  cat > "$round_dir/R01-VERIFICATION.md" <<'VERIF'
---
phase: 01
result: PASS
writer: write-verification.sh
---
VERIF

  run bash "$SCRIPT" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"qa_gate_scope=uat round=01"* ]]
  [[ "$output" == *"qa_gate_result=PASS"* ]]
}
