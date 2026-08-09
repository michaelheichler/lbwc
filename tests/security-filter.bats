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

run_filter() {
  local file_path="$1"
  payload "tool_input.file_path=$file_path" | bash "$SCRIPTS_DIR/security-filter.sh"
}

@test "allows a normal source file" {
  run run_filter "src/main.py"
  [ "$status" -eq 0 ]
}

@test "blocks .env files" {
  run run_filter ".env"
  [ "$status" -eq 2 ]
}

@test "blocks a bare .pem file" {
  run run_filter "id_rsa.pem"
  [ "$status" -eq 2 ]
}

@test "blocks a .pem file with a trailing extra extension" {
  run run_filter "id_rsa.pem.orig"
  [ "$status" -eq 2 ]
}

@test "blocks a .pem-named directory even when the leaf file is harmless" {
  run run_filter "vendor.pem/notes.txt"
  [ "$status" -eq 2 ]
}

@test "does not block a filename that merely contains pem without a dot" {
  run run_filter "openpem/notes.txt"
  [ "$status" -eq 0 ]
}

@test "blocks node_modules paths" {
  run run_filter "node_modules/leftpad/index.js"
  [ "$status" -eq 2 ]
}

@test "blocks empty file path" {
  run run_filter ""
  [ "$status" -eq 2 ]
}

@test "allows a Grep call with no path field, regex is not a path" {
  local json
  json=$(payload "tool_input.pattern=dist/|build/")
  run bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "does not block a search whose pattern contains dist/ or build/ when a real path is also present" {
  local json
  json=$(payload "tool_input.pattern=dist/|build/" "tool_input.path=src")
  run bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}
