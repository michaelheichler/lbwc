#!/usr/bin/env bats

load test_helper

@test "an omitted hook target exits 2 with an explicit resolution error" {
  run bash "$SCRIPTS_DIR/hook-wrapper.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"hook target resolution failed"* ]]
}

@test "a missing hook target exits 2 with an explicit resolution error" {
  run env -u CLAUDE_PLUGIN_ROOT bash "$SCRIPTS_DIR/hook-wrapper.sh" no-such-hook.sh
  [ "$status" -eq 2 ]
  [[ "$output" == *"hook target resolution failed"* ]]
  [[ "$output" == *"no-such-hook.sh"* ]]
}

@test "a resolved hook target receives its input and succeeds" {
  local input='{"tool_input":{"command":"git status"}}'
  run bash -c "printf '%s' '$input' | env CLAUDE_PLUGIN_ROOT='$PROJECT_ROOT' bash '$SCRIPTS_DIR/hook-wrapper.sh' validate-commit.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
