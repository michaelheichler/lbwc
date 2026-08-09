#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  jq '.worktree_isolation = "on"' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.json.tmp" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  cd "$TEST_TEMP_DIR"

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: init"

  mkdir -p .lbwc-planning/phases/01-test
  cat > .lbwc-planning/phases/01-test/01-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
title: Test
wave: 1
depends_on: []
files_modified:
  - src/app.ts
  - src/widget.ts
---
PLAN
}

teardown() {
  teardown_temp_dir
}

run_file_guard() {
  local role="$1" agent_name="$2" file_path="$3"
  jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}' > "$TEST_TEMP_DIR/.test-input.json"
  run env LBWC_AGENT_ROLE="$role" LBWC_AGENT_NAME="$agent_name" bash -c "cat '$TEST_TEMP_DIR/.test-input.json' | bash '$SCRIPTS_DIR/file-guard.sh'"
}

set_stale_mtime_3h() {
  local target="$1"
  local stamp=""
  if [ "$(uname)" = "Darwin" ]; then
    stamp=$(date -v-3H '+%Y%m%d%H%M.%S' 2>/dev/null) || return 1
  else
    stamp=$(date -d '3 hours ago' '+%Y%m%d%H%M.%S' 2>/dev/null) || return 1
  fi
  touch -t "$stamp" "$target"
}

@test "file-guard worktree: write inside worktree allowed" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR\"}" > .lbwc-planning/.agent-worktrees/dev-01.json

  run_file_guard dev lbwc-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: LBWC has no per-agent worktree boundary check, write outside nominal worktree still allowed" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/dev-01.json

  run_file_guard dev lbwc-dev-01 /some/other/path/app.ts
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: LBWC has no per-agent worktree boundary check, relative path escaping nominal worktree still allowed" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR\"}" > .lbwc-planning/.agent-worktrees/dev-01.json

  run_file_guard dev lbwc-dev-01 outside.ts
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: non-dev role bypasses boundary check" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/qa-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/qa-01.json

  local input
  input=$(jq -n '{"tool_input":{"file_path":".lbwc-planning/test.md"}}')
  run bash -c "LBWC_AGENT_ROLE=qa LBWC_AGENT_NAME=lbwc-qa-01 echo '$input' | LBWC_AGENT_ROLE=qa LBWC_AGENT_NAME=lbwc-qa-01 bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: worktree_isolation=off bypasses boundary check" {
  jq '.worktree_isolation = "off"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-01"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/dev-01.json

  run_file_guard dev lbwc-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: missing agent mapping does not block (no worktree mapping is ever consulted)" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json

  run_file_guard dev lbwc-dev-01 "$TEST_TEMP_DIR/src/app.ts"
  [ "$status" -eq 0 ]
}

@test "file-guard worktree: debugger role also gets no boundary enforcement" {
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  mkdir -p .lbwc-planning/.agent-worktrees
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/debugger"
  mkdir -p "$wt_path"
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/debugger.json

  run_file_guard debugger lbwc-debugger /outside/path/file.ts
  [ "$status" -eq 0 ]
}

@test "compaction-instructions: engineer role with exact-match worktree mapping includes CRITICAL path" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-01"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run bash -c 'echo "{\"agent_name\":\"lbwc-python-engineer-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRITICAL"* ]]
  [[ "$output" == *"$wt_path"* ]]
}

@test "compaction-instructions: agent_type carrying the full generated name resolves the same mapping" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-02"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-02.json

  run bash -c 'echo "{\"agent_type\":\"lbwc-python-engineer-02\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
}

@test "compaction-instructions: bare non-LBWC agent_type ignores an LBWC worktree mapping" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/non-lbwc-engineer"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "session" > .lbwc-planning/.lbwc-session
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/engineer-01.json

  run bash -c 'echo "{\"agent_type\":\"engineer\",\"name\":\"engineer-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

@test "compaction-instructions: a foreign agent_type suppresses worktree lookup even with a valid LBWC agent_name" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/fallback-engineer"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run bash -c 'echo "{\"agent_type\":\"helper-agent\",\"agent_name\":\"lbwc-python-engineer-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"$wt_path"* ]]
}

@test "compaction-instructions: an unmatched mapping key omits worktree context, no cwd fallback exists" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/native-engineer"
  mkdir -p "$wt_path" "$TEST_TEMP_DIR/.lbwc-planning/.agent-worktrees"
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  echo '{"worktree_path":"/unused/engineer-01"}' > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash -c "cd '$wt_path' && echo '{\"agent_type\":\"python-engineer\",\"agent_id\":\"agent-abc123\",\"matcher\":\"auto\"}' | bash '$SCRIPTS_DIR/compaction-instructions.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

@test "compaction-instructions: engineer without a worktree mapping omits path" {
  jq '.worktree_isolation = "off"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  run bash -c 'echo "{\"agent_name\":\"lbwc-python-engineer-01\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

@test "compaction-instructions: qa role never gets worktree context" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/qa-01"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/qa.json

  run bash -c 'echo "{\"agent_name\":\"lbwc-qa\",\"matcher\":\"auto\"}" | bash "'"$SCRIPTS_DIR"'/compaction-instructions.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"CRITICAL: Your working directory"* ]]
}

@test "post-compact: engineer role with exact-match worktree mapping includes worktree path" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-01"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run bash -c 'echo "{\"agent_name\":\"lbwc-python-engineer-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
  [[ "$output" == *"Worktree working directory"* ]]
}

@test "post-compact: agent_type carrying the full generated name resolves the same mapping" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/01-02"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-02.json

  run bash -c 'echo "{\"agent_type\":\"lbwc-python-engineer-02\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$wt_path"* ]]
  [[ "$output" == *"Worktree working directory"* ]]
}

@test "post-compact: bare non-LBWC agent_type ignores an LBWC worktree mapping" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/non-lbwc-engineer"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "session" > .lbwc-planning/.lbwc-session
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/engineer-01.json

  run bash -c 'echo "{\"agent_type\":\"engineer\",\"name\":\"engineer-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

@test "post-compact: a foreign agent_type suppresses worktree lookup even with a valid LBWC agent_name" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/fallback-engineer"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run bash -c 'echo "{\"agent_type\":\"helper-agent\",\"agent_name\":\"lbwc-python-engineer-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"$wt_path"* ]]
}

@test "post-compact: an unmatched mapping key omits worktree path, no cwd fallback exists" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/native-engineer"
  mkdir -p "$wt_path" "$TEST_TEMP_DIR/.lbwc-planning/.agent-worktrees"
  jq '.worktree_isolation = "on"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  echo '{"worktree_path":"/unused/engineer-01"}' > .lbwc-planning/.agent-worktrees/lbwc-python-engineer-01.json

  run env LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning" bash -c "cd '$wt_path' && echo '{\"agent_type\":\"python-engineer\",\"agent_id\":\"agent-abc123\"}' | bash '$SCRIPTS_DIR/post-compact.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

@test "post-compact: engineer without a worktree mapping omits path" {
  jq '.worktree_isolation = "off"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp
  mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
  run bash -c 'echo "{\"agent_name\":\"lbwc-python-engineer-01\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

@test "post-compact: lead role never gets worktree context" {
  local wt_path="$TEST_TEMP_DIR/.lbwc-worktrees/lead-01"
  mkdir -p "$wt_path"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$wt_path\"}" > .lbwc-planning/.agent-worktrees/lead.json

  run bash -c 'echo "{\"agent_name\":\"lbwc-lead\"}" | bash "'"$SCRIPTS_DIR"'/post-compact.sh"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Worktree working directory"* ]]
}

@test "session-stop: cleans stale worktree directories (>2hrs)" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  mkdir -p .lbwc-planning/.agent-worktrees
  set_stale_mtime_3h .lbwc-worktrees/01-01
  [ "$?" -eq 0 ]

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"

  [ ! -d ".lbwc-worktrees/01-01" ]
  run git branch --list "lbwc/01-01"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-cleanup: automatic cleanup preserves an active mapped worktree" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR/.lbwc-worktrees/01-01\"}" > .lbwc-planning/.agent-worktrees/lbwc-dev-01.json

  run env LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [[ "$output" == *"scan_only"* ]]
  [ -d ".lbwc-worktrees/01-01" ]
}

@test "worktree-cleanup: automatic cleanup preserves a worktree when map inspection is unavailable" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null

  run env LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [[ "$output" == *"scan_only"* ]]
  [ -d ".lbwc-worktrees/01-01" ]
}

@test "worktree-cleanup: automatic cleanup preserves a worktree when a map is malformed" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  mkdir -p .lbwc-planning/.agent-worktrees
  printf '{' > .lbwc-planning/.agent-worktrees/lbwc-dev-01.json

  run env LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [[ "$output" == *"scan_only"* ]]
  [ -d ".lbwc-worktrees/01-01" ]
}

@test "worktree-cleanup: automatic cleanup preserves a dirty worktree" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  echo "dirty" > .lbwc-worktrees/01-01/dirty.txt

  run env LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [[ "$output" == *"scan_only"* ]]
  [ -d ".lbwc-worktrees/01-01" ]
}

@test "worktree-cleanup: automatic cleanup retains agent map when target is absent" {
  mkdir -p .lbwc-planning/.agent-worktrees
  echo '{"worktree_path":"/active/worktree"}' > .lbwc-planning/.agent-worktrees/lbwc-dev-01-01.json

  run env LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [[ "$output" == *"scan_only"* ]]
  [ -f .lbwc-planning/.agent-worktrees/lbwc-dev-01-01.json ]
}

@test "worktree-cleanup: explicit target removes an active mapped worktree" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR/.lbwc-worktrees/01-01\"}" > .lbwc-planning/.agent-worktrees/lbwc-dev-01-01.json

  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01

  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]
}

@test "session-stop: preserves a stale dirty worktree" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  echo "dirty" > .lbwc-worktrees/01-01/dirty.txt
  set_stale_mtime_3h .lbwc-worktrees/01-01
  [ "$?" -eq 0 ]

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"

  [ -d ".lbwc-worktrees/01-01" ]
}

@test "session-stop: preserves a stale active mapped worktree" {
  git worktree add .lbwc-worktrees/01-01 -b lbwc/01-01 >/dev/null
  mkdir -p .lbwc-planning/.agent-worktrees
  echo "{\"worktree_path\":\"$TEST_TEMP_DIR/.lbwc-worktrees/01-01\"}" > .lbwc-planning/.agent-worktrees/lbwc-dev-01.json
  set_stale_mtime_3h .lbwc-worktrees/01-01
  [ "$?" -eq 0 ]

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"

  [ -d ".lbwc-worktrees/01-01" ]
}

@test "session-stop: preserves fresh worktree directories (<2hrs)" {
  mkdir -p .lbwc-worktrees/01-01

  echo '{"cost_usd":0,"duration_ms":0,"tokens_in":0,"tokens_out":0,"model":"test"}' | bash "$SCRIPTS_DIR/session-stop.sh"
  [ -d ".lbwc-worktrees/01-01" ]
}

@test "session-stop: handles no worktrees directory gracefully" {
  [ ! -d ".lbwc-worktrees" ]
  run bash -c 'echo "{\"cost_usd\":0,\"duration_ms\":0,\"tokens_in\":0,\"tokens_out\":0,\"model\":\"test\"}" | bash "'"$SCRIPTS_DIR"'/session-stop.sh"'
  [ "$status" -eq 0 ]
}

@test "doctor-cleanup scan: detects stale worktree" {
  mkdir -p .lbwc-worktrees/02-01
  set_stale_mtime_3h .lbwc-worktrees/02-01
  [ "$?" -eq 0 ]

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale_worktree|02-01"* ]]
}

@test "doctor-cleanup scan: ignores fresh worktree" {
  mkdir -p .lbwc-worktrees/01-01

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale_worktree|01-01"* ]]
}

@test "doctor-cleanup scan: handles no worktrees directory" {
  [ ! -d ".lbwc-worktrees" ]
  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" != *"stale_worktree"* ]]
}

@test "doctor-cleanup cleanup: reports unproven stale worktrees without removing them" {
  mkdir -p .lbwc-worktrees/02-01
  set_stale_mtime_3h .lbwc-worktrees/02-01
  [ "$?" -eq 0 ]

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" cleanup

  [ "$status" -eq 0 ]
  [ -d ".lbwc-worktrees/02-01" ]
  [[ "$(<.lbwc-planning/.hook-errors.log)" == *"scan-only stale worktree"* ]]
}

@test "doctor-cleanup cleanup: preserves a live non-LBWC process record" {
  sleep 30 &
  local child_pid=$!
  printf 'lbwc:%s\n' "$child_pid" > .lbwc-planning/.agent-pids

  run bash "$SCRIPTS_DIR/doctor-cleanup.sh" cleanup

  [ "$status" -eq 0 ]
  kill -0 "$child_pid"
  grep -Fq "scan-only process record: lbwc:$child_pid" .lbwc-planning/.hook-errors.log
  kill "$child_pid"
}

@test "doctor-cleanup scan: ignores unrelated Claude processes" {
  mkdir -p "$TEST_TEMP_DIR/bin"
  printf '#!/bin/bash\nprintf "999999 1 claude\\n"\n' > "$TEST_TEMP_DIR/bin/ps"
  chmod +x "$TEST_TEMP_DIR/bin/ps"

  run env PATH="$TEST_TEMP_DIR/bin:$PATH" bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan

  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan_process|999999"* ]]
}

@test "doctor-cleanup scan: continues when the Claude resolver is unavailable" {
  local isolated_scripts="$TEST_TEMP_DIR/isolated-scripts"
  mkdir -p "$isolated_scripts"
  cp "$SCRIPTS_DIR/doctor-cleanup.sh" "$isolated_scripts/doctor-cleanup.sh"

  run bash "$isolated_scripts/doctor-cleanup.sh" scan

  [ "$status" -eq 0 ]
}
