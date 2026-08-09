#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/agent-lifecycle.sh"
  TEST_ROOT="$(mktemp -d)"
  TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  mkdir -p "$PLANNING_DIR/.contracts/tasks"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "agent-lifecycle: malformed manifest fails with its status" {
  mkdir -p "$PLANNING_DIR"
  printf '{not valid json\n' > "$PLANNING_DIR/.agent-manifest.json"

  run env LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT" sweep

  [ "$status" -ne 0 ]
  [ "$output" = "agent_manifest_status=malformed" ]
}

@test "agent-lifecycle: unavailable manifest library fails with its status" {
  local shim_dir="$TEST_ROOT/scripts"
  mkdir -p "$shim_dir"
  cp "$SCRIPT" "$shim_dir/agent-lifecycle.sh"

  run env LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$shim_dir/agent-lifecycle.sh" sweep

  [ "$status" -ne 0 ]
  [ "$output" = "agent_manifest_status=unavailable" ]
}

@test "agent-lifecycle: ignores a touch for an unknown agent" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"agents":{}}' > "$PLANNING_DIR/.agent-manifest.json"

  run bash -c "printf '%s' '{\"hook_event_name\":\"SubagentStart\",\"agent_type\":\"unknown-agent\"}' | LBWC_PLANNING_DIR='$PLANNING_DIR' bash '$SCRIPT' touch"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

write_contract_and_manifest() {
  local state="${1:-running}" contract_path contract_id contract_digest
  contract_path=$(bash "$REPO_ROOT/scripts/task-contract.sh" issue "$TEST_ROOT" task-10 --command test --role python-engineer --team solo --job "implement owned script" --write-allowance scripts/owned.sh)
  contract_id=$(jq -r '.contract_id' "$contract_path")
  contract_digest=$(jq -r '.contract_digest' "$contract_path")
  cat > "$PLANNING_DIR/.agent-manifest.json" <<EOF
{"agents":{"lbwc-python-engineer-calm-fox":{"name":"lbwc-python-engineer-calm-fox","role":"python-engineer","state":"$state","project_root":"$TEST_ROOT","write_allowances":["scripts/owned.sh"],"contract_enabled":true,"contract_path":"$contract_path","contract_id":"$contract_id","contract_digest":"$contract_digest","task_identity":"$contract_id","created_at":"2026-08-09T12:00:00Z","last_activity_at":"2026-08-09T12:00:00Z"}}}
EOF
}

write_idle_sleep_shim() {
  local bin="$TEST_ROOT/idle-bin"
  mkdir -p "$bin"
  cat > "$bin/sleep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "120" ] || exit 9
printf '%s\n' "$1" > "$LBWC_TEST_SLEEP_LOG"
EOF
  chmod +x "$bin/sleep"
  printf '%s\n' "$bin"
}

@test "agent-lifecycle: native start event promotes a registered known agent" {
  write_contract_and_manifest registered

  run bash -c "printf '%s' '{\"hook_event_name\":\"SubagentStart\",\"agent_type\":\"lbwc-python-engineer-calm-fox\"}' | LBWC_PLANNING_DIR='$PLANNING_DIR' LBWC_LIFECYCLE_NOW=1786280400 bash '$SCRIPT' touch start"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].state' "$PLANNING_DIR/.agent-manifest.json")" = "running" ]
}

@test "agent-lifecycle: ignores self-reported state without a native event" {
  write_contract_and_manifest registered

  run bash -c "printf '%s' '{\"agent_type\":\"lbwc-python-engineer-calm-fox\",\"state\":\"running\"}' | LBWC_PLANNING_DIR='$PLANNING_DIR' bash '$SCRIPT' touch start"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].state' "$PLANNING_DIR/.agent-manifest.json")" = "registered" ]
}

@test "agent-lifecycle: idle event stops a known contracted teammate after revalidation" {
  local bin sleep_log="$TEST_ROOT/sleep.log"
  write_contract_and_manifest running
  bin=$(write_idle_sleep_shim)
  mkdir -p "$TEST_ROOT/.claude/agents"
  printf 'generated definition\n' > "$TEST_ROOT/.claude/agents/lbwc-python-engineer-calm-fox.md"

  run bash -c "printf '%s' '{\"hook_event_name\":\"TeammateIdle\",\"teammate_name\":\"lbwc-python-engineer-calm-fox\"}' | PATH='$bin':\$PATH LBWC_TEST_SLEEP_LOG='$sleep_log' LBWC_PLANNING_DIR='$PLANNING_DIR' LBWC_LIFECYCLE_NOW=1786280400 bash '$SCRIPT' idle"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.continue' <<< "$output")" = "false" ]
  [[ "$(jq -r '.stopReason' <<< "$output")" == *"shell-observed inactivity"* ]]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].state' "$PLANNING_DIR/.agent-manifest.json")" = "expired" ]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].idle_observed_by' "$PLANNING_DIR/.agent-manifest.json")" = "TeammateIdle" ]
  [ -f "$TEST_ROOT/.claude/agents/lbwc-python-engineer-calm-fox.md" ]
  [ "$(cat "$sleep_log")" = "120" ]
}

@test "agent-lifecycle: revalidation preserves a teammate that became active" {
  local bin="$TEST_ROOT/bin"
  write_contract_and_manifest running
  mkdir -p "$bin"
  cat > "$bin/sleep" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "120" ] || exit 9
printf '%s\n' "$1" > "$LBWC_TEST_SLEEP_LOG"
tmp="${LBWC_TEST_MANIFEST}.tmp"
jq 'del(.agents["lbwc-python-engineer-calm-fox"].idle_observation_token) | .agents["lbwc-python-engineer-calm-fox"].last_activity_at = "2026-08-09T13:00:01Z"' "$LBWC_TEST_MANIFEST" > "$tmp" && mv "$tmp" "$LBWC_TEST_MANIFEST"
EOF
  chmod +x "$bin/sleep"

  run bash -c "printf '%s' '{\"hook_event_name\":\"TeammateIdle\",\"teammate_name\":\"lbwc-python-engineer-calm-fox\"}' | PATH='$bin':\$PATH LBWC_TEST_SLEEP_LOG='$TEST_ROOT/sleep.log' LBWC_TEST_MANIFEST='$PLANNING_DIR/.agent-manifest.json' LBWC_PLANNING_DIR='$PLANNING_DIR' LBWC_LIFECYCLE_NOW=1786280400 bash '$SCRIPT' idle"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].state' "$PLANNING_DIR/.agent-manifest.json")" = "running" ]
  [ "$(cat "$TEST_ROOT/sleep.log")" = "120" ]
}

@test "agent-lifecycle: invalid contract never produces a stop decision" {
  write_contract_and_manifest running
  local contract_path
  contract_path=$(jq -r '.agents["lbwc-python-engineer-calm-fox"].contract_path' "$PLANNING_DIR/.agent-manifest.json")
  jq '.created_by = "worker"' "$contract_path" > "$TEST_ROOT/contract.tmp"
  mv "$TEST_ROOT/contract.tmp" "$contract_path"

  run bash -c "printf '%s' '{\"hook_event_name\":\"TeammateIdle\",\"teammate_name\":\"lbwc-python-engineer-calm-fox\"}' | LBWC_PLANNING_DIR='$PLANNING_DIR' bash '$SCRIPT' idle"

  [ "$status" -ne 0 ]
  [ "$output" = "agent_contract_status=invalid" ]
  [ "$(jq -r '.agents["lbwc-python-engineer-calm-fox"].state' "$PLANNING_DIR/.agent-manifest.json")" = "running" ]
}

@test "agent-lifecycle: validates critic allowances from the shared pair contract" {
  local contract_path contract_id contract_digest bin sleep_log="$TEST_ROOT/sleep.log"
  bin=$(write_idle_sleep_shim)
  contract_path=$(bash "$REPO_ROOT/scripts/task-contract.sh" issue "$TEST_ROOT" paired-task --command build --role python-engineer --team pair --job "implement paired task" --write-allowance scripts/owned.sh)
  contract_id=$(jq -r '.contract_id' "$contract_path")
  contract_digest=$(jq -r '.contract_digest' "$contract_path")
  cat > "$PLANNING_DIR/.agent-manifest.json" <<EOF
{"agents":{"lbwc-python-critic-calm-owl":{"name":"lbwc-python-critic-calm-owl","role":"python-critic","state":"running","project_root":"$TEST_ROOT","write_allowances":[],"contract_enabled":true,"contract_path":"$contract_path","contract_id":"$contract_id","contract_digest":"$contract_digest","task_identity":"$contract_id","created_at":"2026-08-09T12:00:00Z","last_activity_at":"2026-08-09T12:00:00Z"}}}
EOF

  run bash -c "printf '%s' '{\"hook_event_name\":\"TeammateIdle\",\"teammate_name\":\"lbwc-python-critic-calm-owl\"}' | PATH='$bin':\$PATH LBWC_TEST_SLEEP_LOG='$sleep_log' LBWC_PLANNING_DIR='$PLANNING_DIR' LBWC_LIFECYCLE_NOW=1786280400 bash '$SCRIPT' idle"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.continue' <<< "$output")" = "false" ]
  [ "$(jq -r '.agents["lbwc-python-critic-calm-owl"].state' "$PLANNING_DIR/.agent-manifest.json")" = "expired" ]
  [ "$(cat "$sleep_log")" = "120" ]
}

@test "agent-lifecycle: TeammateIdle hook has no matcher and enforces the two minute wait" {
  local hooks="$REPO_ROOT/hooks/hooks.json"

  run jq -e '
    .hooks.TeammateIdle | length == 1
    and (.[0] | has("matcher") | not)
    and .[0].hooks[0].timeout == 135
    and (.[0].hooks[0].command | contains("agent-lifecycle.sh idle"))
    and (.[0].hooks | length == 1)
  ' "$hooks"

  [ "$status" -eq 0 ]
}
