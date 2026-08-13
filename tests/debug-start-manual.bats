#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  SCRIPT="$SCRIPTS_DIR/debug-start-manual.sh"
  PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning"
  mkdir -p "$PLANNING_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "manual start strips routing metadata and creates source todo" {
  run bash -c 'printf %s "$1" | REF_HASH=abcd1234 bash "$2" "$3"' _ \
    '  Parser crash (ref:abcd1234) --parallel  ' "$SCRIPT" "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  eval "$output"
  [ "$BUG_DESC" = "Parser crash" ]
  [ "$SLUG" = "parser-crash" ]
  [ "$MANUAL_REF" = "abcd1234" ]
  [ -f "$session_file" ]
  grep -Fq '**Text:** Parser crash' "$session_file"
  grep -Fq '**Ref:** abcd1234' "$session_file"
}

@test "manual start validates and persists detail fields" {
  detail='{"status":"ok","detail":{"context":"Parser boundary","files":["src/parser.sh","tests/parser.bats"]}}'

  run env DETAIL_STATUS=ok DETAIL_RESULT_JSON="$detail" bash -c \
    'printf %s "$1" | bash "$2" "$3"' _ 'Parser crash' "$SCRIPT" "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  eval "$output"
  [ "$MANUAL_DETAIL_CONTEXT" = "Parser boundary" ]
  [ "$MANUAL_DETAIL_FILES" = '["src/parser.sh","tests/parser.bats"]' ]
  grep -Fq 'Parser boundary' "$session_file"
  grep -Fq 'src/parser.sh' "$session_file"
}

@test "manual start rejects malformed successful detail" {
  run env DETAIL_STATUS=ok DETAIL_RESULT_JSON='{"status":"ok","detail":{"files":"src/parser.sh"}}' \
    bash -c 'printf %s "$1" | bash "$2" "$3"' _ 'Parser crash' "$SCRIPT" "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"DETAIL_RESULT_JSON is invalid"* ]]
  [ ! -e "$PLANNING_DIR/debugging/.active-session" ]
}

@test "manual start rejects an empty description without detail" {
  run bash -c 'printf %s "$1" | bash "$2" "$3"' _ \
    ' --competing (ref:abcd1234) ' "$SCRIPT" "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"bug description is empty"* ]]
  [ ! -e "$PLANNING_DIR/debugging/.active-session" ]
}

@test "manual start uses debug slug when valid detail supplies all context" {
  detail='{"status":"ok","detail":{"context":"Parser boundary","files":[]}}'

  run env DETAIL_STATUS=ok DETAIL_RESULT_JSON="$detail" bash -c \
    'printf %s "$1" | bash "$2" "$3"' _ '--serial' "$SCRIPT" "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  eval "$output"
  [ "$BUG_DESC" = "" ]
  [ "$SLUG" = "debug" ]
  [ -f "$session_file" ]
}

@test "debug command delegates complete inline verification protocol" {
  command_file="$PROJECT_ROOT/commands/debug.md"
  reference_file="$PROJECT_ROOT/references/debug-inline-verification.md"

  grep -Fq '@${CLAUDE_PLUGIN_ROOT}/references/debug-inline-verification.md' "$command_file"
  [ "$(wc -l < "$command_file" | tr -d ' ')" -lt 500 ]
  grep -Fq 'Debug QA: Round {qa_round}' "$reference_file"
  grep -Fq 'Debug UAT: Round {uat_round}' "$reference_file"
  grep -Fq 'set status to `uat_pending`' "$reference_file"
  grep -Fq 'set status to `uat_failed`' "$reference_file"
  grep -Fq 'invoke AskUserQuestion as a tool call and wait' "$reference_file"
  grep -Fq 're-enter investigation Step 3' "$reference_file"
}
