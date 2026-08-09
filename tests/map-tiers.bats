#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO_ROOT/scripts/lib/map-tiers.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  mkdir -p "$PLANNING_DIR/codebase"
  CURRENT_HASH="$(git -C "$REPO_ROOT" rev-parse HEAD)"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_tier() {
  bash -c ". '$LIB'; resolve_map_tier $*"
}

run_mode() {
  (
    cd "$REPO_ROOT"
    bash -c ". '$LIB'; resolve_map_mode '$PLANNING_DIR' $*"
  )
}

@test "map-tiers: under 200 files is solo" {
  run run_tier 50 auto
  [ "$status" -eq 0 ]
  [ "$output" = "tier=solo" ]
}

@test "map-tiers: 200 to 1000 files is duo" {
  run run_tier 500 auto
  [ "$status" -eq 0 ]
  [ "$output" = "tier=duo" ]
}

@test "map-tiers: over 1000 files is quad" {
  run run_tier 5000 auto
  [ "$status" -eq 0 ]
  [ "$output" = "tier=quad" ]
}

@test "map-tiers: prefer_teams=never forces solo at any size" {
  run run_tier 5000 never
  [ "$status" -eq 0 ]
  [ "$output" = "tier=solo" ]
}

@test "map-tiers: prefer_teams=never overrides forced tier" {
  run run_tier 5000 never quad
  [ "$status" -eq 0 ]
  [ "$output" = "tier=solo" ]
}

@test "map-tiers: prefer_teams=never rejects unknown forced tier" {
  run run_tier 5000 never octet
  [ "$status" -eq 1 ]
}

@test "map-tiers: forced tier wins over count" {
  run run_tier 50 auto quad
  [ "$status" -eq 0 ]
  [ "$output" = "tier=quad" ]
}

@test "map-tiers: unknown forced tier fails" {
  run run_tier 50 auto octet
  [ "$status" -eq 1 ]
}

@test "map-tiers: missing META means full mode" {
  run run_mode
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "mode=full" ]
}

@test "map-tiers: META at HEAD with few changes is incremental" {
  printf 'mapped_at: 2026-08-01T00:00:00Z\ngit_hash: %s\nfile_count: 1000000\n' \
    "$CURRENT_HASH" \
    > "$PLANNING_DIR/codebase/META.md"

  run run_mode
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "mode=incremental" ]
}

@test "map-tiers: unknown git hash means full mode" {
  printf 'mapped_at: 2026-08-01T00:00:00Z\ngit_hash: %s\nfile_count: 10\n' \
    '0000000000000000000000000000000000000000' \
    > "$PLANNING_DIR/codebase/META.md"

  run run_mode
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "mode=full" ]
}

@test "map-tiers: forced incremental wins without META" {
  run run_mode incremental
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "mode=incremental" ]
}
