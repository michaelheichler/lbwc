#!/usr/bin/env bats

load test_helper

RECORDER="$SCRIPTS_DIR/lib/deviq-record.py"
GATE="$SCRIPTS_DIR/deviq-build-gate.sh"

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  DEVIQ="$TEST_TEMP_DIR/deviq"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

record_block() {
  local phase="$1" role="$2"
  shift 2
  python3 "$RECORDER" block --phase "$phase" --role "$role" --root "$DEVIQ" "$@"
}

@test "a malformed line in blocks.jsonl fails the gate and names the line number" {
  mkdir -p "$DEVIQ"
  printf 'not json\n' > "$DEVIQ/blocks.jsonl"

  run bash "$GATE" p1 --root "$DEVIQ"

  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed at line 1"* ]]
}

@test "a malformed second line names line 2, not line 1" {
  mkdir -p "$DEVIQ"
  record_block p1 roleA --field trigger=one --field consequence=c --field fix=f --field status=open >/dev/null
  printf 'not json\n' >> "$DEVIQ/blocks.jsonl"

  run bash "$GATE" p1 --root "$DEVIQ"

  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed at line 2"* ]]
}

@test "a resolved block passes the gate" {
  ID=$(record_block p1 roleA --field trigger="stale cache" --field consequence=c --field fix=f --field status=open)
  record_block p1 roleA --field id="$ID" --field trigger="stale cache" --field consequence=c --field fix=f --field status=resolved >/dev/null

  run bash "$GATE" p1 --root "$DEVIQ"

  [ "$status" -eq 0 ]
}

@test "dedupe collapses repeated open appends to a single blocking entry" {
  record_block p1 roleA --field trigger="flaky test" --field consequence=c --field fix=f --field status=open >/dev/null
  record_block p1 roleA --field trigger="flaky test" --field consequence=c --field fix=f --field status=open >/dev/null

  run bash "$GATE" p1 --root "$DEVIQ"

  [ "$status" -eq 2 ]
  local count
  count=$(grep -c 'flaky test' <<< "$output")
  [ "$count" -eq 1 ]
}

@test "a 9th distinct open block is refused by the recorder before it ever reaches the gate" {
  for i in 1 2 3 4 5 6 7 8; do
    record_block p1 roleA --field trigger="issue-$i" --field consequence=c --field fix=f --field status=open >/dev/null
  done

  run record_block p1 roleA --field trigger="issue-9" --field consequence=c --field fix=f --field status=open
  [ "$status" -eq 1 ]

  run bash "$GATE" p1 --root "$DEVIQ"
  [ "$status" -eq 2 ]
  [[ "$output" != *"issue-9"* ]]
  local count
  count=$(grep -oc 'issue-[0-9]' <<< "$output")
  [ "$count" -eq 8 ]
}
