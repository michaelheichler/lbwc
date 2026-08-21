#!/usr/bin/env bats

setup() {
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/.lbwc-planning"
  printf '%s\n' '{}' > "$ROOT/.lbwc-planning/config.json"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/lib/workflow-manifest.sh"
  PLANNING_DIR="$ROOT/.lbwc-planning"
  SCRIPT_DIGEST=$(printf 'a%.0s' $(seq 1 64))
  ARGS_DIGEST=$(printf 'b%.0s' $(seq 1 64))
}

teardown() {
  rm -rf "$ROOT"
}

manifest_call() {
  run bash -c '. "$1"; shift; "$@"' _ "$SCRIPT" "$@"
}

@test "register writes a registered entry keyed by contract id" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '["lbwc-engineer-a","lbwc-critic-b"]'
  [ "$status" -eq 0 ]

  run jq -c '.workflows["wf-1"]' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$status" -eq 0 ]
  entry="$output"
  [ "$(jq -r '.state' <<< "$entry")" = registered ]
  [ "$(jq -r '.script_path' <<< "$entry")" = "$ROOT/workflows/wf-1.js" ]
  [ "$(jq -r '.script_digest' <<< "$entry")" = "$SCRIPT_DIGEST" ]
  [ "$(jq -r '.args_digest' <<< "$entry")" = "$ARGS_DIGEST" ]
  [ "$(jq -c '.roster' <<< "$entry")" = '["lbwc-engineer-a","lbwc-critic-b"]' ]
  [ "$(jq -r '.created_at' <<< "$entry")" != null ]
}

@test "register rejects a contract id already present in the manifest" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]

  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/other.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 3 ]

  run jq -r '.workflows["wf-1"].script_path' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = "$ROOT/workflows/wf-1.js" ]
}

@test "register rejects a roster that is not a JSON array" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '"not-an-array"'
  [ "$status" -eq 1 ]
  [ ! -f "$PLANNING_DIR/.workflow-manifest.json" ]
}

@test "claim moves a registered contract to running on matching digests" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]

  manifest_call workflow_manifest_claim "$PLANNING_DIR" wf-1 "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  [ "$status" -eq 0 ]

  run jq -r '.workflows["wf-1"].state' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = running ]
  run jq -r '.workflows["wf-1"].started_at' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" != null ]
}

@test "claim rejects a script digest that does not match the registered digest" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]

  local tampered
  tampered=$(printf 'c%.0s' $(seq 1 64))
  manifest_call workflow_manifest_claim "$PLANNING_DIR" wf-1 "$tampered" "$ARGS_DIGEST"
  [ "$status" -eq 20 ]

  run jq -r '.workflows["wf-1"].state' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = registered ]
}

@test "claim rejects a contract id absent from the manifest" {
  manifest_call workflow_manifest_claim "$PLANNING_DIR" wf-missing "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  [ "$status" -eq 10 ]
}

@test "claim refuses to reclaim a contract already running" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]
  manifest_call workflow_manifest_claim "$PLANNING_DIR" wf-1 "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  [ "$status" -eq 0 ]

  run bash -c '. "$1"; workflow_manifest_claim "$2" wf-1 "$3" "$4"; ec=$?; printf "state=%s\n" "$WORKFLOW_MANIFEST_CLAIM_STATE"; exit "$ec"' \
    _ "$SCRIPT" "$PLANNING_DIR" "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  [ "$status" -eq 3 ]
  [[ "$output" == *"state=running"* ]]
}

@test "complete moves a running contract to used" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]
  manifest_call workflow_manifest_claim "$PLANNING_DIR" wf-1 "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  [ "$status" -eq 0 ]

  manifest_call workflow_manifest_complete "$PLANNING_DIR" wf-1
  [ "$status" -eq 0 ]

  run jq -r '.workflows["wf-1"].state' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = used ]
  run jq -r '.workflows["wf-1"].completed_at' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" != null ]
}

@test "expire moves a registered contract to expired" {
  manifest_call workflow_manifest_register "$PLANNING_DIR" wf-1 "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST" '[]'
  [ "$status" -eq 0 ]

  manifest_call workflow_manifest_expire "$PLANNING_DIR" wf-1
  [ "$status" -eq 0 ]

  run jq -r '.workflows["wf-1"].state' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = expired ]
}

@test "a live writer keeps the lock serialized until the caller times out" {
  local lock_dir="$PLANNING_DIR/.workflow-manifest.lock"
  sleep 30 &
  local writer_pid=$!
  mkdir -p "$lock_dir"
  printf '%s\n' "$writer_pid" > "$lock_dir/pid"
  touch -t 200001010000 "$lock_dir"

  run env LBWC_WORKFLOW_MANIFEST_LOCK_TIMEOUT=1 LBWC_WORKFLOW_MANIFEST_LOCK_STALE_SECONDS=0 \
    bash -c '. "$1"; workflow_manifest_register "$2" wf-1 "$3" "$4" "$5" "[]"' \
    _ "$SCRIPT" "$PLANNING_DIR" "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST"
  kill "$writer_pid" 2>/dev/null || true
  wait "$writer_pid" 2>/dev/null || true

  [ "$status" -eq 1 ]
  [ -d "$lock_dir" ]
  [ ! -f "$PLANNING_DIR/.workflow-manifest.json" ]
}

@test "a stale lock from a dead writer is reclaimed" {
  local lock_dir="$PLANNING_DIR/.workflow-manifest.lock"
  mkdir -p "$lock_dir"
  printf '%s\n' '999999' > "$lock_dir/pid"
  touch -t 200001010000 "$lock_dir"

  run env LBWC_WORKFLOW_MANIFEST_LOCK_STALE_SECONDS=0 \
    bash -c '. "$1"; workflow_manifest_register "$2" wf-1 "$3" "$4" "$5" "[]"' \
    _ "$SCRIPT" "$PLANNING_DIR" "$ROOT/workflows/wf-1.js" "$SCRIPT_DIGEST" "$ARGS_DIGEST"

  [ "$status" -eq 0 ]
  [ ! -d "$lock_dir" ]
  run jq -r '.workflows["wf-1"].state' "$PLANNING_DIR/.workflow-manifest.json"
  [ "$output" = registered ]
}
