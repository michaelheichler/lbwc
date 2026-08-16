#!/usr/bin/env bats

load test_helper

@test "execution commands keep backend selection stable and cancel without fallback" {
  for command in vibe build team; do
    file="$BATS_TEST_DIRNAME/../commands/$command.md"
    run grep -F 'frozen runtime snapshot' "$file"
    [ "$status" -eq 0 ]
    run grep -F 'backend drift' "$file"
    [ "$status" -eq 0 ]
  done

  run grep -F 'Cancel spawn' "$BATS_TEST_DIRNAME/../commands/team.md"
  [ "$status" -eq 0 ]
  run grep -F 'must cancel, never fall back' "$BATS_TEST_DIRNAME/../commands/team.md"
  [ "$status" -eq 0 ]
}
