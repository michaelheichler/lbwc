#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.lbwc-planning/phases/01-test-phase"
  cat > "$TEST_TEMP_DIR/.lbwc-planning/ROADMAP.md" <<'EOF'
## Phase 1: Test Phase
**Goal:** Test goal
**Success:** Tests pass
**Reqs:** REQ-01
EOF
  cat > "$TEST_TEMP_DIR/.lbwc-planning/REQUIREMENTS.md" <<'EOF'
- [ ] REQ-01: Test requirement
EOF
  cat > "$TEST_TEMP_DIR/.lbwc-planning/phases/01-test-phase/PLAN.md" <<'EOF'
## Tasks
- [ ] TASK-01: Do something
EOF
}

teardown() {
  teardown_temp_dir
}

@test "compile-context: default configuration skips the absent metrics collector" {
  cd "$TEST_TEMP_DIR"

  run bash -x "$SCRIPTS_DIR/compile-context.sh" 01 dev .lbwc-planning/phases

  [ "$status" -eq 0 ]
  [[ "$output" == *"V3_METRICS_ENABLED=false"* ]]
  [[ "$output" != *"collect-metrics.sh"* ]]
}

@test "compile-context: project metrics opt-in reaches the collector branch" {
  printf '%s\n' '{"metrics":true}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  cd "$TEST_TEMP_DIR"

  run bash -x "$SCRIPTS_DIR/compile-context.sh" 01 dev .lbwc-planning/phases

  [ "$status" -eq 0 ]
  [[ "$output" == *"V3_METRICS_ENABLED=true"* ]]
  [[ "$output" == *"collect-metrics.sh"* ]]
}
