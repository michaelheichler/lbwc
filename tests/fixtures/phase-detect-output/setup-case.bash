#!/bin/bash
set -u

phase_detect_fixture_write_project() {
  mkdir -p .lbwc-planning/phases
  printf '# Fixture Project\n' > .lbwc-planning/PROJECT.md
  printf '{}\n' > .lbwc-planning/config.json
}

phase_detect_fixture_write_plan() {
  local phase_dir="$1"
  local phase_num="$2"

  mkdir -p "$phase_dir"
  printf '# Plan\n' > "$phase_dir/${phase_num}-PLAN.md"
}

phase_detect_fixture_write_summary() {
  local phase_dir="$1"
  local phase_num="$2"
  local summary_status="$3"

  printf '%s\n' '---' "status: $summary_status" '---' '# Summary' 'Done.' > "$phase_dir/${phase_num}-SUMMARY.md"
}

phase_detect_fixture_write_uat_issues() {
  local phase_dir="$1"
  local phase_num="$2"

  cat > "$phase_dir/${phase_num}-UAT.md" <<EOF
---
phase: $phase_num
status: issues_found
issues: 1
---

## Tests

### P${phase_num}-T1: fixture check

- **Result:** issue
- **Issue:** fixture issue
  - Description: fixture behavior failed
  - Severity: major
EOF
}

phase_detect_fixture_setup_git() {
  if [ ! -d .git ]; then
    git init --quiet
    git config user.email "fixture@example.com"
    git config user.name "Fixture"
    printf 'fixture\n' > .fixture-root
    git add .fixture-root
    git commit -m "fixture root" --quiet
  fi
}

phase_detect_fixture_write_original_failure() {
  local phase_dir="$1"

  cat > "$phase_dir/05-VERIFICATION.md" <<'EOF'
---
result: FAIL
writer: write-verification.sh
---
## Must-Have Checks
| ID | Category | Description | Status | Evidence |
|----|----------|-------------|--------|----------|
| FAIL-01 | must_have | Original failure | FAIL | Missing |
EOF
}

phase_detect_fixture_write_round_plan() {
  local round_dir="$1"

  cat > "$round_dir/R01-PLAN.md" <<'EOF'
---
round: 01
fail_classifications:
  - {id: "FAIL-01", type: "process-exception", rationale: "Fixture documents a valid remediated round"}
---
EOF
}

phase_detect_fixture_write_round_summary() {
  local round_dir="$1"

  cat > "$round_dir/R01-SUMMARY.md" <<'EOF'
---
plan: R01
status: complete
files_modified:
  - README.md
  - .lbwc-planning/phases/05-remediated/remediation/qa/round-01/R01-SUMMARY.md
deviations: []
---
EOF
}

phase_detect_fixture_write_remediation_round() {
  local phase_dir="$1"
  local round_dir="$phase_dir/remediation/qa/round-01"

  mkdir -p "$round_dir"
  phase_detect_fixture_write_original_failure "$phase_dir"
  phase_detect_fixture_write_round_plan "$round_dir"
  phase_detect_fixture_write_round_summary "$round_dir"
}

phase_detect_fixture_setup_remediated() {
  local phase_dir=".lbwc-planning/phases/05-remediated"
  local round_dir="$phase_dir/remediation/qa/round-01"
  local round_anchor current_commit

  phase_detect_fixture_write_plan "$phase_dir" "05-01"
  phase_detect_fixture_write_summary "$phase_dir" "05-01" "partial"
  phase_detect_fixture_write_remediation_round "$phase_dir"
  round_anchor=$(git rev-parse HEAD)
  printf 'remediation evidence\n' > README.md
  git add README.md "$phase_dir/05-01-SUMMARY.md"
  git commit -m "fixture remediation evidence" --quiet
  current_commit=$(git rev-parse HEAD)
  printf 'stage=done\nround=01\nround_started_at_commit=%s\n' "$round_anchor" > "$phase_dir/remediation/qa/.qa-remediation-stage"
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: $current_commit" '---' '# Verification' 'Passed after remediation.' > "$round_dir/R01-VERIFICATION.md"
}

phase_detect_fixture_setup_stale_pass() {
  local phase_dir=".lbwc-planning/phases/05-remediated"
  local round_one="$phase_dir/remediation/qa/round-01"
  local round_two="$phase_dir/remediation/qa/round-02"
  local current_commit

  phase_detect_fixture_write_plan "$phase_dir" "05-01"
  phase_detect_fixture_write_summary "$phase_dir" "05-01" "partial"
  mkdir -p "$round_one" "$round_two"
  current_commit=$(git rev-parse HEAD)
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: $current_commit" '---' > "$round_one/R01-VERIFICATION.md"
  printf '%s\n' '---' 'result: FAIL' 'writer: write-verification.sh' '---' > "$round_two/R02-VERIFICATION.md"
  printf 'stage=done\nround=02\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"
}

phase_detect_fixture_setup_failed_remediation() {
  local phase_dir=".lbwc-planning/phases/05-remediated"
  local round_dir="$phase_dir/remediation/qa/round-01"
  local current_commit

  phase_detect_fixture_write_plan "$phase_dir" "05-01"
  phase_detect_fixture_write_summary "$phase_dir" "05-01" "failed"
  mkdir -p "$round_dir"
  current_commit=$(git rev-parse HEAD)
  printf '%s\n' '---' 'result: PASS' 'writer: write-verification.sh' 'plans_verified:' '  - R01' "verified_at_commit: $current_commit" '---' > "$round_dir/R01-VERIFICATION.md"
  printf 'stage=done\nround=01\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"
}

phase_detect_fixture_setup_unplanned() {
  phase_detect_fixture_write_project
  mkdir -p .lbwc-planning/phases/01-unplanned
}

phase_detect_fixture_setup_incomplete() {
  phase_detect_fixture_write_project
  phase_detect_fixture_write_plan ".lbwc-planning/phases/01-incomplete" "01-01"
}

phase_detect_fixture_setup_all_done() {
  local phase_dir=".lbwc-planning/phases/01-complete"

  phase_detect_fixture_write_project
  phase_detect_fixture_write_plan "$phase_dir" "01-01"
  phase_detect_fixture_write_summary "$phase_dir" "01-01" "complete"
}

phase_detect_fixture_setup_uat_issues() {
  local phase_dir=".lbwc-planning/phases/01-uat-issues"

  phase_detect_fixture_write_project
  phase_detect_fixture_write_plan "$phase_dir" "01-01"
  phase_detect_fixture_write_summary "$phase_dir" "01-01" "complete"
  phase_detect_fixture_write_uat_issues "$phase_dir" "01"
}

phase_detect_fixture_setup_qa_remediation() {
  local phase_dir=".lbwc-planning/phases/01-qa-remediation"

  phase_detect_fixture_write_project
  phase_detect_fixture_write_plan "$phase_dir" "01-01"
  phase_detect_fixture_write_summary "$phase_dir" "01-01" "complete"
  mkdir -p "$phase_dir/remediation/qa"
  printf '%s\n' '---' 'result: FAIL' '---' > "$phase_dir/01-VERIFICATION.md"
  printf 'stage=execute\nround=01\n' > "$phase_dir/remediation/qa/.qa-remediation-stage"
}

phase_detect_fixture_setup_milestone_recovery() {
  local phase_dir=".lbwc-planning/milestones/m01-shipped/phases/01-archived"

  phase_detect_fixture_write_project
  mkdir -p "$phase_dir"
  printf '# Shipped\n' > .lbwc-planning/milestones/m01-shipped/SHIPPED.md
  phase_detect_fixture_write_plan "$phase_dir" "01-01"
  phase_detect_fixture_write_summary "$phase_dir" "01-01" "complete"
  phase_detect_fixture_write_uat_issues "$phase_dir" "01"
}

setup_phase_detect_output_case() {
  local case_name="$1"

  rm -rf .lbwc-planning README.md
  phase_detect_fixture_setup_git
  case "$case_name" in
    no-planning) : ;;
    unplanned) phase_detect_fixture_setup_unplanned ;;
    incomplete) phase_detect_fixture_setup_incomplete ;;
    all-done) phase_detect_fixture_setup_all_done ;;
    uat-issues) phase_detect_fixture_setup_uat_issues ;;
    qa-remediation) phase_detect_fixture_setup_qa_remediation ;;
    milestone-recovery) phase_detect_fixture_setup_milestone_recovery ;;
    phase-05-remediated) phase_detect_fixture_write_project; phase_detect_fixture_setup_remediated ;;
    failed-summary-passing-remediation) phase_detect_fixture_write_project; phase_detect_fixture_setup_failed_remediation ;;
    stale-pass-later-fail) phase_detect_fixture_write_project; phase_detect_fixture_setup_stale_pass ;;
    *) printf 'unknown fixture case: %s\n' "$case_name" >&2; return 1 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  setup_phase_detect_output_case "${1:-}"
fi
