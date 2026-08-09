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

run_nudge() {
  local content="$1"
  payload "tool_name=Write" "tool_input.content=$content" \
    | env CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" bash "$SCRIPTS_DIR/deviq-nudge.sh"
}

@test "content matching a nudge pattern emits a PostToolUse additionalContext" {
  run run_nudge "this class has become a real god object over time"

  [ "$status" -eq 0 ]
  [[ "$output" == *"additionalContext"* ]]
  [[ "$output" == *"antipatterns/blob"* ]]
  [[ "$output" == *"scripts/deviq-lookup.sh --show"* ]]
}

@test "garbage stdin exits 0 with no output" {
  run bash -c "printf 'not json{{{' | env CLAUDE_PLUGIN_ROOT='$PROJECT_ROOT' bash '$SCRIPTS_DIR/deviq-nudge.sh'"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a second matching write inside the cooldown window is silent" {
  run run_nudge "another god object showing up here"
  [ "$status" -eq 0 ]
  [[ "$output" == *"additionalContext"* ]]

  run run_nudge "yet another god object right here"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing nudge map exits 0 with no output" {
  run bash -c "printf '%s' '{\"tool_input\":{\"content\":\"god object\"}}' | env CLAUDE_PLUGIN_ROOT='$TEST_TEMP_DIR' bash '$SCRIPTS_DIR/deviq-nudge.sh'"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "content with no matching pattern is silent" {
  run run_nudge "adds a simple helper function to format dates"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
