#!/usr/bin/env bats

setup() {
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/.lbwc-planning" "$ROOT/.temporary-agent-runfiles/runs/team-one"
  printf '%s\n' '{}' > "$ROOT/.lbwc-planning/config.json"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/lib/lbwc-control-root.sh"
}

teardown() {
  rm -rf "$ROOT"
}

@test "resolver selects a valid active planning control root" {
  run bash -c '. "$1"; lbwc_resolve_control_root "" "" "$2"' _ "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
  expected_root=$(cd -P "$ROOT" && pwd -P)
  [ "$output" = "$expected_root/.lbwc-planning" ]
}

@test "resolver selects one explicit temporary run below the repository" {
  run bash -c '. "$1"; lbwc_resolve_control_root "$2" "" "$3"' _ "$SCRIPT" "$ROOT/.temporary-agent-runfiles/runs/team-one" "$ROOT"
  [ "$status" -eq 0 ]
  expected_root=$(cd -P "$ROOT" && pwd -P)
  [ "$output" = "$expected_root/.temporary-agent-runfiles/runs/team-one" ]
}

@test "resolver rejects an arbitrary control directory" {
  mkdir -p "$ROOT/not-control"
  run bash -c '. "$1"; lbwc_control_root_validate "$2"' _ "$SCRIPT" "$ROOT/not-control"
  [ "$status" -ne 0 ]
}

@test "resolver rejects a temporary run nested below a run" {
  mkdir -p "$ROOT/.temporary-agent-runfiles/runs/team-one/nested"
  run bash -c '. "$1"; lbwc_control_root_validate "$2"' _ "$SCRIPT" "$ROOT/.temporary-agent-runfiles/runs/team-one/nested"
  [ "$status" -ne 0 ]
}

@test "resolver rejects ambiguous temporary runs" {
  rm -rf "$ROOT/.lbwc-planning"
  mkdir -p "$ROOT/.temporary-agent-runfiles/runs/team-two"

  run bash -c '. "$1"; lbwc_resolve_control_root "" "" "$2"' _ "$SCRIPT" "$ROOT"

  [ "$status" -ne 0 ]
}
