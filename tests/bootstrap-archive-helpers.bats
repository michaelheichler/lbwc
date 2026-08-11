#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS_DIR="$REPO_ROOT/scripts"
  TEST_ROOT="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "bootstrap project writes the requested output path" {
  local project="$TEST_ROOT/.lbwc-planning/PROJECT.md"

  run bash "$SCRIPTS_DIR/bootstrap/bootstrap-project.sh" "$project" "Example Project" "Example description"

  [ "$status" -eq 0 ]
  [ -f "$project" ]
  grep -Fqx 'Example description' "$project"
}

@test "derive milestone slug uses roadmap phase names" {
  mkdir -p "$TEST_ROOT/.lbwc-planning"
  printf '%s\n' '## Phase 1: Safer archives' > "$TEST_ROOT/.lbwc-planning/ROADMAP.md"

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" "$TEST_ROOT/.lbwc-planning"

  [ "$status" -eq 0 ]
  [ "$output" = "01-safer-archives" ]
}

@test "archive guard blocks an unresolved UAT report" {
  cp "$SCRIPTS_DIR/archive-uat-guard.sh" "$TEST_ROOT/archive-uat-guard.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "phase_detect_complete=true" "planning_dir_exists=true" "project_exists=true" "uat_issues_phase=01" "uat_blocking_phase=none" "milestone_uat_issues=false"' > "$TEST_ROOT/phase-detect.sh"
  chmod +x "$TEST_ROOT/phase-detect.sh"

  run bash "$TEST_ROOT/archive-uat-guard.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"UAT"* ]]
}

@test "normalizing plans preserves an existing destination" {
  local phase="$TEST_ROOT/.lbwc-planning/phases/01-bootstrap"
  mkdir -p "$phase"
  printf '%s\n' '# Existing' > "$phase/01-PLAN.md"
  printf '%s\n' '# Source' > "$phase/PLAN-1.md"

  run bash "$SCRIPTS_DIR/normalize-plan-filenames.sh" "$phase"

  [ "$status" -eq 0 ]
  [ -f "$phase/01-PLAN.md" ]
  [ -f "$phase/PLAN-1.md" ]
  grep -Fqx '# Existing' "$phase/01-PLAN.md"
}

@test "migration writes an LBWC configuration version" {
  mkdir -p "$TEST_ROOT/.lbwc-planning"
  printf '%s\n' '{"config_version":1}' > "$TEST_ROOT/.lbwc-planning/config.json"

  run bash "$SCRIPTS_DIR/migrate-config.sh" "$TEST_ROOT/.lbwc-planning/config.json"

  [ "$status" -eq 0 ]
  run jq -e '.config_version >= 1' "$TEST_ROOT/.lbwc-planning/config.json"
  [ "$status" -eq 0 ]
}

@test "suggestions use LBWC command names" {
  mkdir -p "$TEST_ROOT/.lbwc-planning"

  run env LBWC_PLANNING_DIR="$TEST_ROOT/.lbwc-planning" bash "$SCRIPTS_DIR/suggest-next.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"/lbwc:"* ]]
}
