#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/track-known-issues.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  PHASE_DIR="$PLANNING_DIR/phases/03-test-phase"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_summary() {
  cat > "$PHASE_DIR/03-01-SUMMARY.md" <<'SUMMARY'
---
phase: 03
pre_existing_issues:
  - '{"test":"TransferTests","file":"tests/transfer.sh","error":"timeout"}'
---
SUMMARY
}

@test "sync-summaries creates an idempotent root registry" {
  write_summary

  run bash "$SCRIPT" sync-summaries "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"known_issues_status=present"* ]]
  [[ "$output" == *"known_issues_count=1"* ]]
  [ "$(jq -r '.issues[0].test' "$PHASE_DIR/known-issues.json")" = "TransferTests" ]

  first="$(jq -cS '.issues[0]' "$PHASE_DIR/known-issues.json")"
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  [ "$first" = "$(jq -cS '.issues[0]' "$PHASE_DIR/known-issues.json")" ]
}

@test "promote-todos writes each root-canonical issue once" {
  write_summary
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null
  cat > "$PLANNING_DIR/STATE.md" <<'STATE'
## Todos
None.
STATE

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"promoted_count=1"* ]]
  grep -q '\[KNOWN-ISSUE\] TransferTests (tests/transfer.sh): timeout' "$PLANNING_DIR/STATE.md"

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"already_tracked_count=1"* ]]
}

@test "promote-todos fails closed without root STATE.md" {
  write_summary
  bash "$SCRIPT" sync-summaries "$PHASE_DIR" >/dev/null

  run bash "$SCRIPT" promote-todos "$PHASE_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"promote_status=no_state_file"* ]]
}
