#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

make_phase() {
  local phase_dir="$TEST_TEMP_DIR/.lbwc-planning/phases/$1"
  mkdir -p "$phase_dir"
  touch "$phase_dir/$2-PLAN.md"
  printf '%s\n' '---' "status: $3" '---' > "$phase_dir/$2-SUMMARY.md"
}

make_support_copy() {
  local source_dir="$PROJECT_ROOT/scripts"
  local target_dir="$TEST_TEMP_DIR/gate-scripts"
  mkdir -p "$target_dir/lib"
  cp "$source_dir/qa-gate.sh" "$target_dir/"
  cp "$source_dir/lib/qa-gate-decision.sh" "$target_dir/lib/"
  cp "$source_dir/qa-result-gate.sh" "$target_dir/"
  cp "$source_dir/lib/qa-result-gate-path-evidence.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-fail-classifications.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-known-issues.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-summary-deviations.sh" "$target_dir/lib/"
  cat > "$target_dir/summary-utils.sh" <<'EOF'
#!/usr/bin/env bash
extract_summary_status() {
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
  ' "$1" 2>/dev/null
}

is_summary_complete() {
  local status
  status=$(extract_summary_status "$1")
  case "$status" in complete|completed) return 0 ;; *) return 1 ;; esac
}
count_complete_summaries() {
  local dir="$1" count=0 f
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    is_summary_complete "$f" && count=$((count + 1))
  done
  echo "$count"
}
count_terminal_summaries() {
  local dir="$1" count=0 f status
  for f in "$dir"/*-SUMMARY.md "$dir"/SUMMARY.md; do
    [ -f "$f" ] || continue
    status=$(extract_summary_status "$f")
    case "$status" in complete|completed|partial|failed) count=$((count + 1)) ;; esac
  done
  echo "$count"
}
EOF
  cat > "$target_dir/verification-freshness.sh" <<'EOF'
#!/usr/bin/env bash
EOF
  cat > "$target_dir/lib/phase-detect-support.sh" <<'EOF'
#!/usr/bin/env bash
phase_has_passing_qa_remediation() { return 1; }
phase_execution_is_satisfied() {
  local phase_dir="$1" plan_count="$2" complete_count="$3"
  [ "$plan_count" -gt 0 ] || return 1
  [ "$complete_count" -ge "$plan_count" ] && return 0
  phase_has_passing_qa_remediation "$phase_dir"
}
EOF
  cat > "$target_dir/resolve-verification-path.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s/remediation/qa/round-01/R01-VERIFICATION.md\n' "$2"
EOF
  chmod +x "$target_dir"/*.sh "$target_dir"/lib/*.sh
}

run_summary_gap_decision() {
  run bash -c '
    . "$1"
    qa_gate_summary_gap_is_allowed "$2" "$3" "$4"
  ' _ "$PROJECT_ROOT/scripts/lib/qa-gate-decision.sh" "$1" "$2" "$3"
}

make_git_log_fixture() {
  local log_line="$1"
  local bin_dir="$TEST_TEMP_DIR/fake-bin"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/date" <<'EOF'
#!/bin/bash
printf '%s\n' 1700000000
EOF
  cat > "$bin_dir/git" <<EOF
#!/bin/bash
if [ "\$1" = log ]; then
  printf '%s\\n' '$log_line'
  exit 0
fi
exit 1
EOF
  chmod +x "$bin_dir/date" "$bin_dir/git"
}

@test "summary-gap decision allows no plans without Git evidence" {
  run_summary_gap_decision 0 0 unavailable

  [ "$status" -eq 0 ]
}

@test "summary-gap decision allows completed plans without Git evidence" {
  run_summary_gap_decision 2 2 unavailable

  [ "$status" -eq 0 ]
}

@test "summary-gap decision denies missing summaries when Git is unavailable" {
  run_summary_gap_decision 2 1 unavailable

  [ "$status" -ne 0 ]
}

@test "summary-gap decision permits one missing summary with fresh conforming evidence" {
  run_summary_gap_decision 2 1 fresh-conforming

  [ "$status" -eq 0 ]
}

@test "summary-gap decision denies a nonconforming Git observation" {
  run_summary_gap_decision 2 1 nonconforming

  [ "$status" -ne 0 ]
}

@test "summary-gap decision denies a stale Git observation" {
  run_summary_gap_decision 2 1 stale

  [ "$status" -ne 0 ]
}

@test "adapter permits one missing summary for a fresh conforming commit" {
  make_phase 01-partial 01-01 complete
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy
  make_git_log_fixture '1699999999 feat(01-01): active work'

  run env PATH="$TEST_TEMP_DIR/fake-bin:$PATH" LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "adapter denies one missing summary for a stale conforming commit" {
  make_phase 01-partial 01-01 complete
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy
  make_git_log_fixture '1699992799 feat(01-01): old work'

  run env PATH="$TEST_TEMP_DIR/fake-bin:$PATH" LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"1 summaries for 2 plans"* ]]
}

@test "adapter denies a summary gap when the current time cannot be read" {
  make_phase 01-partial 01-01 complete
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy
  make_git_log_fixture '1699999999 feat(01-01): active work'
  cat > "$TEST_TEMP_DIR/fake-bin/date" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TEST_TEMP_DIR/fake-bin/date"

  run env PATH="$TEST_TEMP_DIR/fake-bin:$PATH" LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
}

@test "adapter denies a summary gap when the conforming commit is future-dated" {
  make_phase 01-partial 01-01 complete
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy
  make_git_log_fixture '1700000001 feat(01-01): active work'

  run env PATH="$TEST_TEMP_DIR/fake-bin:$PATH" LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"1 summaries for 2 plans"* ]]
}

@test "no planning dir exits clean" {
  rm -rf "$TEST_TEMP_DIR/.lbwc-planning"

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$PROJECT_ROOT/scripts/qa-gate.sh"

  [ "$status" -eq 0 ]
}

@test "dependency load failure fails closed instead of silently passing" {
  make_phase 01-partial 01-01 partial
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy
  rm -f "$TEST_TEMP_DIR/gate-scripts/verification-freshness.sh"

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"dependency load failed"* ]]
}

@test "unavailable Git denies incomplete plan summaries" {
  make_phase 01-partial 01-01 partial
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$PROJECT_ROOT/scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *"dependency load failed"* ]]
  [[ "$output" == *"SUMMARY.md gap detected"* ]]
}

@test "fully complete phase counts as satisfied" {
  make_phase 01-complete 01-01 complete
  make_support_copy

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unresolved partial phase does not count" {
  make_phase 01-partial 01-01 partial
  touch "$TEST_TEMP_DIR/.lbwc-planning/phases/01-partial/01-02-PLAN.md"
  make_support_copy

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"0 summaries for 2 plans"* ]]
}
