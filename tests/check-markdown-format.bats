#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECKER="$REPO_ROOT/scripts/check-markdown-format.sh"
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "$TEST_ROOT/commands"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_fixture() {
  local filename="$1"
  shift
  printf '%s\n' "$@" > "$TEST_ROOT/commands/$filename"
}

run_checker() {
  run bash "$CHECKER" --root "$TEST_ROOT"
}

@test "check-markdown-format accepts a clean command file" {
  write_fixture clean.md '---' 'category: supporting' '---' '' '# Clean'

  run_checker

  [ "$status" -eq 0 ]
  [[ "$output" == *'Markdown format passed: 1 command files'* ]]
}

@test "check-markdown-format rejects literal tabs" {
  printf '# Bad\n\tindented\n' > "$TEST_ROOT/commands/tabs.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'commands/tabs.md:2: literal tab character'* ]]
}

@test "check-markdown-format rejects trailing whitespace" {
  printf '# Bad  \n' > "$TEST_ROOT/commands/trailing.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'commands/trailing.md:1: trailing whitespace'* ]]
}

@test "check-markdown-format rejects CRLF line endings" {
  printf '# Bad\r\n' > "$TEST_ROOT/commands/crlf.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'commands/crlf.md:1: CRLF line ending'* ]]
}

@test "check-markdown-format rejects a missing final newline" {
  printf '# Bad' > "$TEST_ROOT/commands/no-final-newline.md"

  run_checker

  [ "$status" -eq 1 ]
  [[ "$output" == *'commands/no-final-newline.md: missing final newline'* ]]
}

@test "check-markdown-format accepts the debug command" {
  run bash "$CHECKER" --root "$REPO_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Markdown format passed:'* ]]
}