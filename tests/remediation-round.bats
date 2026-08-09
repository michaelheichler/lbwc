#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/remediation-round.sh"
  STATE_API="$REPO_ROOT/scripts/qa-remediation-state.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  PHASE_DIR="$PLANNING_DIR/phases/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  if command -v git-ai >/dev/null; then
    git-ai await --timeout 5 >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}

finish_qa_round() {
  bash "$SCRIPT" stage "$PHASE_DIR" qa execute >/dev/null
  bash "$SCRIPT" stage "$PHASE_DIR" qa verify >/dev/null
  bash "$SCRIPT" stage "$PHASE_DIR" qa done >/dev/null
}

@test "remediation-round: open creates round-01 with stage=plan" {
  run bash "$SCRIPT" open "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=01"* ]]
  [[ "$output" == *"round_dir=$PHASE_DIR/remediation/qa/round-01"* ]]
  [[ "$output" == *"plan_path=$PHASE_DIR/remediation/qa/round-01/R01-PLAN.md"* ]]
  [ -d "$PHASE_DIR/remediation/qa/round-01" ]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  grep -q '^stage=plan$' "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q '^round=01$' "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
  grep -q '^round_started_at_commit=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "remediation-round: stage transitions keep the round" {
  bash "$SCRIPT" open "$PHASE_DIR" uat >/dev/null

  run bash "$SCRIPT" stage "$PHASE_DIR" uat execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=execute"* ]]
  grep -q '^stage=execute$' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  grep -q '^round=01$' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
}

@test "remediation-round: open after done advances to round-02" {
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null
  finish_qa_round

  run bash "$SCRIPT" open "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=02"* ]]
  [ -d "$PHASE_DIR/remediation/qa/round-02" ]
}

@test "remediation-round: re-opening a round stuck at plan reuses it" {
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null

  run bash "$SCRIPT" open "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=01"* ]]
  [ ! -d "$PHASE_DIR/remediation/qa/round-02" ]
}

@test "remediation-round: cap reached exits 3" {
  printf '{"max_uat_remediation_rounds": 1}\n' > "$PLANNING_DIR/config.json"
  bash "$SCRIPT" open "$PHASE_DIR" uat >/dev/null
  bash "$SCRIPT" stage "$PHASE_DIR" uat done >/dev/null

  run bash "$SCRIPT" open "$PHASE_DIR" uat

  [ "$status" -eq 3 ]
  [[ "$output" == *"cap_reached=true"* ]]
}

@test "remediation-round: UAT cap does not reject reopening a plan round" {
  printf '{"max_uat_remediation_rounds": 1}\n' > "$PLANNING_DIR/config.json"
  bash "$SCRIPT" open "$PHASE_DIR" uat >/dev/null

  run bash "$SCRIPT" open "$PHASE_DIR" uat

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=01"* ]]
  [ ! -d "$PHASE_DIR/remediation/uat/round-02" ]
}

@test "remediation-round: current reports without mutating" {
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null
  bash "$SCRIPT" stage "$PHASE_DIR" qa execute >/dev/null
  bash "$SCRIPT" stage "$PHASE_DIR" qa verify >/dev/null

  run bash "$SCRIPT" current "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=verify"* ]]
  [[ "$output" == *"round=01"* ]]
  grep -q '^stage=verify$' "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "remediation-round: QA driver and state API expose the same stage lifecycle" {
  run bash "$STATE_API" open "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=plan"* ]]
  [[ "$output" == *"round=01"* ]]

  run bash "$SCRIPT" stage "$PHASE_DIR" qa execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=execute"* ]]

  run bash "$STATE_API" stage "$PHASE_DIR" verify

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=verify"* ]]

  run bash "$SCRIPT" current "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=verify"* ]]
  [[ "$output" == *"round=01"* ]]
}

@test "remediation-round: QA driver rejects a skipped stage transition" {
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null

  run bash "$SCRIPT" stage "$PHASE_DIR" qa verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"illegal QA stage transition: plan -> verify"* ]]
  grep -q '^stage=plan$' "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "qa-remediation-state: cap does not reject reopening a plan round" {
  printf '{"max_uat_remediation_rounds": 1}\n' > "$PLANNING_DIR/config.json"
  bash "$STATE_API" open "$PHASE_DIR" >/dev/null

  run bash "$STATE_API" open "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=01"* ]]
  [ ! -d "$PHASE_DIR/remediation/qa/round-02" ]
}

@test "qa-remediation-state: reclaims a stale lock from a dead writer" {
  local lock_dir="$PHASE_DIR/remediation/qa/.qa-remediation.lock"
  mkdir -p "$lock_dir"
  printf '%s\n' '999999' > "$lock_dir/pid"
  touch -t 200001010000 "$lock_dir"

  run env QA_REMEDIATION_LOCK_STALE_SECONDS=0 bash "$STATE_API" open "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"stage=plan"* ]]
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
  [ ! -d "$lock_dir" ]
}

@test "qa-remediation-state: keeps a live writer lock serialized" {
  local lock_dir="$PHASE_DIR/remediation/qa/.qa-remediation.lock"
  sleep 30 &
  local writer_pid=$!
  mkdir -p "$lock_dir"
  printf '%s\n' "$writer_pid" > "$lock_dir/pid"
  touch -t 200001010000 "$lock_dir"

  run env QA_REMEDIATION_LOCK_STALE_SECONDS=0 bash "$STATE_API" open "$PHASE_DIR"
  kill "$writer_pid" 2>/dev/null || true
  wait "$writer_pid" 2>/dev/null || true

  [ "$status" -eq 1 ]
  [[ "$output" == *"timed out acquiring QA remediation lock"* ]]
  [ -d "$lock_dir" ]
  [ ! -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]
}

@test "remediation-round: current with no round fails" {
  run bash "$SCRIPT" current "$PHASE_DIR" qa

  [ "$status" -eq 1 ]
}

setup_git_repo() {
  ( cd "$TEST_ROOT" && git init --quiet && git config user.email t@t && git config user.name T \
    && echo x > f && git add f && git commit -qm init )
  HEAD1=$(git -C "$TEST_ROOT" rev-parse HEAD)
}

@test "remediation-round: qa open anchors round_started_at_commit at HEAD" {
  setup_git_repo

  run bash "$SCRIPT" open "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  grep -q "^round_started_at_commit=$HEAD1$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "remediation-round: qa stage transition preserves the anchor" {
  setup_git_repo
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null

  run bash "$SCRIPT" stage "$PHASE_DIR" qa execute

  [ "$status" -eq 0 ]
  grep -q "^round_started_at_commit=$HEAD1$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "remediation-round: qa open of a new round re-anchors at the new HEAD" {
  setup_git_repo
  bash "$SCRIPT" open "$PHASE_DIR" qa >/dev/null
  finish_qa_round
  ( cd "$TEST_ROOT" && echo y >> f && git add f && git commit -qm second )
  HEAD2=$(git -C "$TEST_ROOT" rev-parse HEAD)

  run bash "$SCRIPT" open "$PHASE_DIR" qa

  [ "$status" -eq 0 ]
  [[ "$output" == *"round=02"* ]]
  grep -q "^round_started_at_commit=$HEAD2$" "$PHASE_DIR/remediation/qa/.qa-remediation-stage"
}

@test "remediation-round: uat stage file keeps layout=round-dir, no anchor" {
  setup_git_repo

  run bash "$SCRIPT" open "$PHASE_DIR" uat

  [ "$status" -eq 0 ]
  grep -q '^layout=round-dir$' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
  ! grep -q '^round_started_at_commit=' "$PHASE_DIR/remediation/uat/.uat-remediation-stage"
}
