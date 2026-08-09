#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  mkdir -p "$PROJECT_DIR/.lbwc-planning"
  cd "$PROJECT_DIR"
  HOOK="$PROJECT_ROOT/hooks/context_usage.py"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

write_usage() {
  printf '%s\n' "$1" > "$PROJECT_DIR/.lbwc-planning/.context-usage"
}

resolve_level() {
  bash -c ". '$PROJECT_ROOT/scripts/lib/resolve-caveman-level.sh' && resolve_caveman_level auto '$PROJECT_DIR/.lbwc-planning' && printf '%s' \"\$RESOLVED_CAVEMAN_LEVEL\""
}

run_hook() {
  local transcript="$PROJECT_DIR/transcript.jsonl"
  python3 -c "open('$transcript','w').write('x' * $1)"
  run python3 "$HOOK" <<EOF
{"session_id": "s1", "cwd": "$PROJECT_DIR", "transcript_path": "$transcript", "tool_name": "Write", "tool_input": {}}
EOF
}

@test "context-usage hook writes parseable record" {
  run_hook 400000

  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.lbwc-planning/.context-usage" ]
  [ "$(cat "$PROJECT_DIR/.lbwc-planning/.context-usage")" = "s1|50|200000" ]
}

@test "context-usage hook respects configured window" {
  printf '{"context_window_tokens": 100000}\n' > "$PROJECT_DIR/.lbwc-planning/config.json"

  run_hook 200000

  [ "$status" -eq 0 ]
  [ "$(cat "$PROJECT_DIR/.lbwc-planning/.context-usage")" = "s1|50|100000" ]
}

@test "context-usage hook caps at 100 percent" {
  run_hook 2000000

  [ "$status" -eq 0 ]
  [[ "$(cat "$PROJECT_DIR/.lbwc-planning/.context-usage")" == "s1|100|"* ]]
}

@test "context-usage hook fails open without transcript" {
  run python3 "$HOOK" <<'EOF'
{"session_id": "s1", "cwd": "/nonexistent", "tool_name": "Write"}
EOF

  [ "$status" -eq 0 ]
}

@test "context-usage hook fails open on garbage stdin" {
  run python3 "$HOOK" <<'EOF'
not json at all
EOF

  [ "$status" -eq 0 ]
}

@test "caveman level: under 50 percent is none" {
  write_usage "s1|30|200000"
  [ "$(resolve_level)" = "none" ]
}

@test "caveman level: 50 to 69 is lite" {
  write_usage "s1|55|200000"
  [ "$(resolve_level)" = "lite" ]
}

@test "caveman level: 70 to 84 is full" {
  write_usage "s1|72|200000"
  [ "$(resolve_level)" = "full" ]
}

@test "caveman level: 85 and up is ultra" {
  write_usage "s1|90|200000"
  [ "$(resolve_level)" = "ultra" ]
}

@test "caveman level: two-field format still parses" {
  write_usage "60|200000"
  [ "$(resolve_level)" = "lite" ]
}

@test "caveman level: missing file is none" {
  [ "$(resolve_level)" = "none" ]
}

@test "caveman level: non-auto style passes through" {
  write_usage "s1|90|200000"
  result=$(bash -c ". '$PROJECT_ROOT/scripts/lib/resolve-caveman-level.sh' && resolve_caveman_level full '$PROJECT_DIR/.lbwc-planning' && printf '%s' \"\$RESOLVED_CAVEMAN_LEVEL\"")
  [ "$result" = "full" ]
}
