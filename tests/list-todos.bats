#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

create_state_with_todos() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'EOF'
# LBWC State

**Project:** Test
**Status:** Active

## Todos
- Fix bug in parser (added 2026-01-15)
- [HIGH] Refactor auth module (added 2026-02-01)
- [low] Update docs (added 2026-02-10)

## Recent Activity
- 2026-02-10: Updated docs
EOF
}

@test "reads todos from root STATE.md (no ACTIVE)" {
  cd "$TEST_TEMP_DIR"
  create_state_with_todos ".lbwc-planning/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  local count
  count=$(echo "$output" | jq -r '.count')
  [ "$count" -eq 3 ]
}

@test "rejects archived milestone state when root STATE.md is absent" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-planning/milestones/default
  create_state_with_todos ".lbwc-planning/milestones/default/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
  [[ "$(echo "$output" | jq -r '.message')" == *"Writable root STATE.md not found"* ]]
}

@test "errors when no STATE.md exists anywhere" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-planning/milestones

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  local status_val
  status_val=$(echo "$output" | jq -r '.status')
  [ "$status_val" = "error" ]
}

@test "rejects filtered requests without a writable root state" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-planning/milestones/default
  create_state_with_todos ".lbwc-planning/milestones/default/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh" high

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
}

@test "emits stable mutation metadata for each displayed todo" {
  cd "$TEST_TEMP_DIR"
  create_state_with_todos ".lbwc-planning/STATE.md"

  run bash "$SCRIPTS_DIR/list-todos.sh"
  [ "$status" -eq 0 ]

  [ "$(echo "$output" | jq -r '.items[0].section_index')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[1].section_index')" = "2" ]
  [ "$(echo "$output" | jq -r '.items[0].normalized_text')" = "Fix bug in parser" ]
  [ "$(echo "$output" | jq -r '.items[1].display_identity')" = "[HIGH] Refactor auth module" ]
  [ "$(echo "$output" | jq -r '.items[1].command_text')" = "Refactor auth module" ]
  [ "$(echo "$output" | jq -r '.items[1].section')" = "## Todos" ]
  [ "$(echo "$output" | jq -r '.items[0].identity_occurrence')" = "1" ]
  [ "$(echo "$output" | jq -r '.items[0].identity_total')" = "1" ]
}

@test "rejects a symlinked root state" {
  cd "$TEST_TEMP_DIR"
  mkdir -p state-source .lbwc-planning
  create_state_with_todos "state-source/STATE.md"
  ln -s "$TEST_TEMP_DIR/state-source/STATE.md" .lbwc-planning/STATE.md

  run bash "$SCRIPTS_DIR/list-todos.sh"

  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.status')" = "error" ]
}
