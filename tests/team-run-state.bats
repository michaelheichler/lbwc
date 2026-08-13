#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  ROOT="$TEST_TEMP_DIR/project"
  mkdir -p "$ROOT"
  SCRIPT="$SCRIPTS_DIR/team-run-state.sh"
  CLEANUP="$SCRIPTS_DIR/cleanup-temporary-agent-runfiles.sh"
}

teardown() {
  teardown_temp_dir
}

@test "team run state defaults scope to the repository root" {
  run bash "$SCRIPT" resolve-scopes --project-root "$ROOT"

  [ "$status" -eq 0 ]
  jq -e '.scopes == ["."]' <<< "$output" >/dev/null
}

@test "team run state preserves repeatable canonical scopes" {
  mkdir -p "$ROOT/src/web" "$ROOT/tests/web"

  run bash "$SCRIPT" resolve-scopes --project-root "$ROOT" \
    --scope src/web --scope "$ROOT/tests/web"

  [ "$status" -eq 0 ]
  jq -e '.scopes == ["src/web", "tests/web"]' <<< "$output" >/dev/null
}

@test "team run state creates diagnosis files without active planning state" {
  run bash "$SCRIPT" create --project-root "$ROOT" --run-id run-one

  [ "$status" -eq 0 ]
  [ -f "$ROOT/.temporary-agent-runfiles/runs/run-one/run.json" ]
  [ -d "$ROOT/.temporary-agent-runfiles/runs/run-one/contracts" ]
  [ -d "$ROOT/.temporary-agent-runfiles/runs/run-one/generated-agents" ]
  jq -e '.status == "planned" and .scopes == ["."]' \
    "$ROOT/.temporary-agent-runfiles/runs/run-one/run.json" >/dev/null
  [ ! -e "$ROOT/.lbwc-planning/config.json" ]
}

@test "team run state rejects a scope that leaves the repository" {
  outside="$TEST_TEMP_DIR/outside"
  mkdir -p "$outside"

  run bash "$SCRIPT" resolve-scopes --project-root "$ROOT" --scope "$outside"

  [ "$status" -ne 0 ]
  [[ "$output" == *"scope must remain inside the project root"* ]]
}

@test "team run state records terminal status and prints a summary" {
  run_root="$ROOT/.temporary-agent-runfiles/runs/run-summary"
  run bash "$SCRIPT" create --project-root "$ROOT" --run-id run-summary
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" record --run-root "$run_root" --kind task \
    --id task-1 --status running
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" update --run-root "$run_root" --status completed \
    --event "native team completed"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" summary --run-root "$run_root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"status: completed"* ]]
  [[ "$output" == *"task-1"* ]]
}

@test "temporary cleanup removes only readable old terminal runs" {
  runs="$ROOT/.temporary-agent-runfiles/runs"
  mkdir -p "$runs/old-completed" "$runs/old-running" "$runs/old-unreadable"
  printf '%s\n' '{"status":"completed","updated_at":"2000-01-01T00:00:00Z"}' \
    > "$runs/old-completed/run.json"
  printf '%s\n' '{"status":"running","updated_at":"2000-01-01T00:00:00Z"}' \
    > "$runs/old-running/run.json"
  printf '%s\n' '{not-json' > "$runs/old-unreadable/run.json"

  run bash "$CLEANUP" cleanup --project-root "$ROOT"

  [ "$status" -eq 0 ]
  [ ! -e "$runs/old-completed" ]
  [ -d "$runs/old-running" ]
  [ -d "$runs/old-unreadable" ]
  [[ "$output" == *"old-completed"* ]]
}

@test "temporary cleanup scan exposes preserved active and unreadable runs" {
  runs="$ROOT/.temporary-agent-runfiles/runs"
  mkdir -p "$runs/active" "$runs/unreadable"
  printf '%s\n' '{"status":"awaiting-review"}' > "$runs/active/run.json"
  printf '%s\n' '{not-json' > "$runs/unreadable/run.json"

  run bash "$CLEANUP" scan --project-root "$ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"temporary_run_active|active"* ]]
  [[ "$output" == *"temporary_run_unreadable|unreadable"* ]]
}

@test "session start and doctor integrate temporary run cleanup" {
  grep -F 'cleanup-temporary-agent-runfiles.sh' "$SCRIPTS_DIR/session-start.sh" >/dev/null
  grep -F 'scan_temporary_runs' "$SCRIPTS_DIR/doctor-cleanup.sh" >/dev/null
  grep -F 'Temporary agent runs' "$PROJECT_ROOT/commands/doctor.md" >/dev/null
}
