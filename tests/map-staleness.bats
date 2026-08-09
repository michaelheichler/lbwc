#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/map-staleness.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  mkdir -p "$PLANNING_DIR/codebase"
  CURRENT_HASH="$(git -C "$REPO_ROOT" rev-parse HEAD)"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_map_staleness() {
  (
    cd "$REPO_ROOT"
    LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT"
  )
}

@test "map-staleness: missing META returns no_map" {
  run run_map_staleness

  [ "$status" -eq 0 ]
  [ "$output" = "status: no_map" ]
}

@test "map-staleness: list-item META returns no_map" {
  printf '%s\n' \
    '- mapped_at: 2026-08-01T00:00:00Z' \
    "- git_hash: $CURRENT_HASH" \
    '- file_count: 1' \
    > "$PLANNING_DIR/codebase/META.md"

  run run_map_staleness

  [ "$status" -eq 0 ]
  [ "$output" = "status: no_map" ]
}

@test "map-staleness: canonical META at HEAD returns fresh" {
  printf 'mapped_at: 2026-08-01T00:00:00Z\ngit_hash: %s\nfile_count: 1\n' \
    "$CURRENT_HASH" \
    > "$PLANNING_DIR/codebase/META.md"

  run run_map_staleness

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "status: fresh" ]
}

@test "map-staleness: unknown git hash returns stale" {
  printf 'mapped_at: 2026-08-01T00:00:00Z\ngit_hash: %s\nfile_count: 1\n' \
    '0000000000000000000000000000000000000000' \
    > "$PLANNING_DIR/codebase/META.md"

  run run_map_staleness

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "status: stale" ]
}
