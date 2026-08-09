#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="${PLAN_TASK_COUNT_SCRIPT:-$REPO_ROOT/scripts/plan-task-count.sh}"
  TEST_ROOT="$(mktemp -d)"
  PLAN="$TEST_ROOT/plan fixture.md"
  CONFIG="$TEST_ROOT/config.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_plan() {
  local records="$1"
  cat > "$PLAN" <<EOF
---
phase: 8
---
<objective>
Prose mentioning <task type="auto"> is not a task record.
</objective>
<tasks>
$records
</tasks>
<verification>
The text <task type="auto"> outside the task block is prose.
</verification>
EOF
}

@test "accepts task count at the merged project cap" {
  printf '{"max_tasks_per_plan": 2}\n' > "$CONFIG"
  write_plan '<task type="auto">
  <name>First</name>
</task>
<task type="auto">
  <name>Second</name>
</task>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -eq 0 ]
  [[ "$output" == *"plan_task_count=2"* ]]
  [[ "$output" == *"max_tasks_per_plan=2"* ]]
}

@test "rejects a task count above the merged project cap" {
  printf '{"max_tasks_per_plan": 1}\n' > "$CONFIG"
  write_plan '<task type="auto">
</task>
<task type="auto">
</task>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN has 2 tasks, exceeding max_tasks_per_plan=1"* ]]
}

@test "counts only balanced records inside the tasks block" {
  printf '{}\n' > "$CONFIG"
  write_plan '<task type="auto">
  <action>Prose mentioning &lt;task type="auto"&gt; stays inside this record.</action>
</task>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -eq 0 ]
  [[ "$output" == *"plan_task_count=1"* ]]
  [[ "$output" == *"max_tasks_per_plan=5"* ]]
}

@test "rejects malformed task structure" {
  printf '{}\n' > "$CONFIG"
  write_plan '<task type="auto">
  <name>Unclosed</name>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed PLAN task structure"* ]]
}

@test "rejects a completed plan with no task records" {
  printf '{}\n' > "$CONFIG"
  write_plan 'No task records.'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN has no task records"* ]]
}

@test "fails closed on malformed project config" {
  printf '{"max_tasks_per_plan":' > "$CONFIG"
  write_plan '<task type="auto">
</task>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -ne 0 ]
  [[ "$output" == *"project config is not valid JSON"* ]]
}

@test "fails closed when project config is unavailable" {
  write_plan '<task type="auto">
</task>'

  run bash "$SCRIPT" "$PLAN" "$CONFIG"

  [ "$status" -ne 0 ]
  [[ "$output" == *"project config is not readable"* ]]
}

@test "fails closed on an invalid merged cap" {
  write_plan '<task type="auto">
</task>'

  for invalid_cap in 0 1.5 '"2"' null; do
    printf '{"max_tasks_per_plan": %s}\n' "$invalid_cap" > "$CONFIG"
    run bash "$SCRIPT" "$PLAN" "$CONFIG"

    [ "$status" -ne 0 ]
    [[ "$output" == *"max_tasks_per_plan must be a positive integer"* ]]
  done
}
