#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUSLINE="$REPO_ROOT/scripts/lbwc-statusline.sh"
  INSTALLER="$REPO_ROOT/scripts/statusline-install.sh"
  TEST_ROOT="$(mktemp -d)"
  PROJECT="$TEST_ROOT/project"
  BIN="$TEST_ROOT/bin"
  mkdir -p "$PROJECT/.lbwc-planning/.contracts/tasks" "$BIN"
  cat > "$BIN/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'branch --show-current'*) printf 'feature/status\n' ;;
  *'status --porcelain'*) printf ' M scripts/example.sh\n' ;;
  *'rev-parse --is-inside-work-tree'*) printf 'true\n' ;;
  *'rev-parse --path-format=absolute --git-dir'*)
    if [ "${LBWC_TEST_GIT_WORKTREE:-false}" = true ]; then
      printf '%s\n' "$PWD/.git/worktrees/agent"
    else
      printf '%s\n' "$PWD/.git"
    fi
    ;;
  *'rev-parse --path-format=absolute --git-common-dir'*) printf '%s\n' "$PWD/.git" ;;
esac
EOF
  chmod +x "$BIN/git"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

status_input() {
  jq -cn --arg project "$PROJECT" '{
    model:{display_name:"Claude Opus"}, effort:"high",
    workspace:{project_dir:$project},
    context_window:{used_percentage:42,current_usage:{input_tokens:1200,output_tokens:340,cache_creation_input_tokens:20,cache_read_input_tokens:800}},
    cost:{total_cost_usd:1.25,total_duration_ms:65000,total_lines_added:12,total_lines_removed:3},
    rate_limits:{five_hour:{used_percentage:25,resets_at:"2026-08-09T18:00:00Z"},seven_day:{used_percentage:60,resets_at:"2026-08-15T18:00:00Z"}}
  }'
}

write_tmux_config() {
  local hide="$1" collapse="$2"
  jq -n \
    --argjson hide "$hide" \
    --argjson collapse "$collapse" \
    '{agent_execution_mode:"tmux",tmux_execution:{enabled:true,heartbeat_stale_seconds:120},statusline_hide_agent_in_tmux:$hide,statusline_collapse_agent_in_tmux:$collapse}' \
    > "$PROJECT/.lbwc-planning/config.json"
}

write_tmux_registry() {
  local state="$1" heartbeat="$2"
  local runtime="$PROJECT/.lbwc-planning/.runtime/tmux-bus"
  mkdir -p "$runtime"
  jq -n \
    --arg state "$state" \
    --argjson heartbeat "$heartbeat" \
    '{tmux:{session:"none"},agents:[{state:$state,heartbeat_at_ms:$heartbeat}]}' \
    > "$runtime/registry.json"
}

@test "statusline: renders native metrics, quota, and orchestration state without writes" {
  mkdir -p "$PROJECT/.lbwc-planning/phases/10-status"
  cat > "$PROJECT/.lbwc-planning/.contracts/tasks/task.json" <<EOF
{"phase":"10"}
EOF
  cat > "$PROJECT/.lbwc-planning/.agent-manifest.json" <<EOF
{"agents":{"lbwc-python-engineer-a":{"state":"running","role":"python-engineer","pair_id":"pair-1","task_identity":"task-10","contract_path":"$PROJECT/.lbwc-planning/.contracts/tasks/task.json"},"lbwc-python-critic-b":{"state":"running","role":"python-critic","pair_id":"pair-1","task_identity":"task-10","contract_path":"$PROJECT/.lbwc-planning/.contracts/tasks/task.json"}}}
EOF
  printf '%s\n' '---' 'result: PASS' '---' > "$PROJECT/.lbwc-planning/phases/10-status/10-VERIFICATION.md"
  printf '%s\n' '---' 'status: complete' '---' > "$PROJECT/.lbwc-planning/phases/10-status/10-UAT.md"
  python3 "$REPO_ROOT/scripts/lib/session-telemetry.py" record --root "$PROJECT/.lbwc-planning" --event session_start --outcome success >/dev/null
  local before
  before=$(find "$PROJECT" -type f -exec cksum {} \; | sort)
  status_input > "$TEST_ROOT/status-input.json"

  run bash -c "PATH='$BIN':\$PATH bash '$STATUSLINE' < '$TEST_ROOT/status-input.json'"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Claude Opus"* ]]
  [[ "$output" == *"feature/status"* ]]
  [[ "$output" == *"5h"*"25%"*"7d"*"60%"* ]]
  [[ "$output" == *"phase 10"*"task task-10"*"pair 1 active"* ]]
  [[ "$output" == *"QA PASS"*"UAT complete"*"Telemetry"*"1 events"* ]]
  [ "$before" = "$(find "$PROJECT" -type f -exec cksum {} \; | sort)" ]
}

@test "statusline: omits quota when Claude Code does not provide rate limits" {
  run env PATH="$BIN:$PATH" bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" != *"Quota"* ]]
  [[ "$output" == *"Telemetry"*"off"* ]]
}

@test "statusline: summarizes healthy and failed agent runtime with diagnostics" {
  local runtime="$PROJECT/.lbwc-planning/.runtime/tmux-bus"
  mkdir -p "$runtime" "$runtime/locks" "$runtime/claims" "$runtime/transactions"
  printf '%s\n' '{"agent_execution_mode":"tmux","tmux_execution":{"enabled":true,"heartbeat_stale_seconds":120}}' > "$PROJECT/.lbwc-planning/config.json"
  jq -n '{
    schema_version: 2,
    main: {agent_id:"main-session",session_id:"main-session",role:"orchestrator",capability_hash:("0" * 64)},
    tmux: {session:"lbwc-main",orchestrator_target:"lbwc-main:0.0",orchestrator_pane:"0",topology:"detached-new-session",managed_session:true,ownership_token:"owned"},
    agents: [
      {agent_id:"agent-running",parent_id:"main-session",contract_id:"contract-running",generated_name:"running",tmux_target:"lbwc-main:0.1",claude_session_id:"session-running",capability_hash:("1" * 64),state:"running",heartbeat_at_ms:2000000000000},
      {agent_id:"agent-idle",parent_id:"main-session",contract_id:"contract-idle",generated_name:"idle",tmux_target:"lbwc-main:0.2",claude_session_id:"session-idle",capability_hash:("2" * 64),state:"idle",heartbeat_at_ms:2000000000000},
      {agent_id:"agent-failed",parent_id:"main-session",contract_id:"contract-failed",generated_name:"failed",tmux_target:"lbwc-main:0.3",claude_session_id:"session-failed",capability_hash:("3" * 64),state:"failed",heartbeat_at_ms:1}
    ],
    routes: {
      "main-session": {inbox:"main-session",tmux_target:"lbwc-main:0.0"},
      "agent-running": {inbox:"agent-running",tmux_target:"lbwc-main:0.1"},
      "agent-idle": {inbox:"agent-idle",tmux_target:"lbwc-main:0.2"},
      "agent-failed": {inbox:"agent-failed",tmux_target:"lbwc-main:0.3"}
    }
  }' > "$runtime/registry.json"
  chmod 600 "$runtime/registry.json"
  jq -n '{schema_version:1,routes:{
    "main-session":{agent_id:"main-session",session_id:"main-session",contract_id:null,inbox:"main-session",tmux_target:"lbwc-main:0.0"},
    "agent-running":{agent_id:"agent-running",session_id:"session-running",contract_id:"contract-running",inbox:"agent-running",tmux_target:"lbwc-main:0.1"},
    "agent-idle":{agent_id:"agent-idle",session_id:"session-idle",contract_id:"contract-idle",inbox:"agent-idle",tmux_target:"lbwc-main:0.2"},
    "agent-failed":{agent_id:"agent-failed",session_id:"session-failed",contract_id:"contract-failed",inbox:"agent-failed",tmux_target:"lbwc-main:0.3"}
  }}' > "$runtime/routing-table.json"
  chmod 600 "$runtime/routing-table.json"
  jq -n '{pid:999999,acquired_at_ms:1,lease_ms:1}' > "$runtime/locks/stale.lock.owner.json"
  mkdir -p "$runtime/locks/stale.lock"
  mv "$runtime/locks/stale.lock.owner.json" "$runtime/locks/stale.lock/owner.json"
  chmod 600 "$runtime/locks/stale.lock/owner.json"
  cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 0 ;;
  list-panes) printf '%s\n' '0' '1' '2' '3' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/tmux"

  run timeout 10 env PATH="$BIN:$PATH" TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"Backend tmux"* ]]
  [[ "$output" == *"session lbwc-main up"* ]]
  [[ "$output" == *"panes 4/4"* ]]
  [[ "$output" == *"agents 3"*"running:1"*"idle:1"*"failed:1"* ]]
  [[ "$output" == *"stale 1"*"failed 1"* ]]
  [[ "$output" == *"Diagnostics"*"stale lock"* ]]
}

@test "statusline: hides flow only inside tmux when configured" {
  write_tmux_config true false
  write_tmux_registry running 2000000000000

  run env PATH="$BIN:$PATH" TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" != *"Flow"* ]]
  [[ "$output" == *"Context"*"Quality"* ]]
  [[ "$output" == *"Backend tmux"* ]]
  [[ "$output" == *"agents 1 running:1 idle:0 failed:0"* ]]
}

@test "statusline: collapses agent worktree panes inside tmux" {
  write_tmux_config false true
  write_tmux_registry failed 1

  run env PATH="$BIN:$PATH" LBWC_TEST_GIT_WORKTREE=true TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"LBWC"*"TMUX agents 1 running:0 idle:0 failed:1"* ]]
  [[ "$output" == *"Diagnostics failed agent"* ]]
  [[ "$output" != *"Context"* ]]
  [[ "$output" != *"Flow"* ]]
  [[ "$output" != *"Quality"* ]]
  [[ "$output" != *"Backend"* ]]
}

@test "statusline: collapse takes precedence over hide in tmux worktrees" {
  write_tmux_config true true
  write_tmux_registry running 2000000000000

  run env PATH="$BIN:$PATH" LBWC_TEST_GIT_WORKTREE=true TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"TMUX agents 1 running:1 idle:0 failed:0"* ]]
  [[ "$output" != *"Context"* ]]
  [[ "$output" != *"Flow"* ]]
  [[ "$output" != *"Quality"* ]]
}

@test "statusline: preserves the standard contract outside tmux" {
  write_tmux_config true true
  write_tmux_registry failed 1

  run env PATH="$BIN:$PATH" LBWC_TEST_GIT_WORKTREE=true bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"Context"*"Flow"*"Quality"* ]]
  [[ "$output" != *"Backend"* ]]
  [[ "$output" != *"TMUX"* ]]
  [[ "$output" != *"Diagnostics"* ]]
}

@test "statusline: malformed tmux settings fail closed without hiding health" {
  printf '%s\n' '{"agent_execution_mode":"tmux","statusline_hide_agent_in_tmux":"true","statusline_collapse_agent_in_tmux":false}' > "$PROJECT/.lbwc-planning/config.json"
  write_tmux_registry failed 1

  run env PATH="$BIN:$PATH" TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"Flow"* ]]
  [[ "$output" == *"Backend invalid"* ]]
  [[ "$output" == *"Diagnostics configuration drift"* ]]
}

@test "statusline: workflow backend reports as itself without configuration drift" {
  printf '%s\n' '{"agent_execution_mode":"workflow","workflow_execution":{"enabled":true}}' > "$PROJECT/.lbwc-planning/config.json"

  run env PATH="$BIN:$PATH" TMUX=1 bash "$STATUSLINE" <<EOF
{"model":{"display_name":"Claude"},"workspace":{"project_dir":"$PROJECT"}}
EOF

  [ "$status" -eq 0 ]
  [[ "$output" == *"Backend workflow"* ]]
  [[ "$output" != *"Backend invalid"* ]]
  [[ "$output" != *"Diagnostics"* ]]
}

@test "statusline installer: requires explicit confirmation and replacement approval" {
  local settings="$TEST_ROOT/settings.json"
  printf '%s\n' '{"statusLine":{"type":"command","command":"other-status"}}' > "$settings"

  run bash "$INSTALLER" --settings "$settings"
  [ "$status" -eq 2 ]
  [ "$output" = "statusline_install=confirmation_required" ]

  run bash "$INSTALLER" --settings "$settings" --yes
  [ "$status" -eq 2 ]
  [ "$output" = "statusline_install=replacement_confirmation_required" ]
  [ "$(jq -r '.statusLine.command' "$settings")" = "other-status" ]
}

@test "statusline installer: writes object format and fifteen second refresh after approval" {
  local settings="$TEST_ROOT/settings.json"
  printf '{}\n' > "$settings"

  run bash "$INSTALLER" --settings "$settings" --yes

  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.type' "$settings")" = "command" ]
  [ "$(jq -r '.statusLine.refreshInterval' "$settings")" -eq 15 ]
  [[ "$(jq -r '.statusLine.command' "$settings")" == *lbwc-statusline.sh* ]]
  [ -f "${settings}.lbwc-statusline.bak" ]
}

@test "statusline installer: replaces another statusline only with both approvals" {
  local settings="$TEST_ROOT/settings.json"
  printf '%s\n' '{"statusLine":{"type":"command","command":"other-status"}}' > "$settings"

  run bash "$INSTALLER" --settings "$settings" --yes --replace

  [ "$status" -eq 0 ]
  [[ "$(jq -r '.statusLine.command' "$settings")" == *lbwc-statusline.sh* ]]
  [ "$(jq -r '.statusLine.refreshInterval' "$settings")" -eq 15 ]
  [ "$(jq -r '.statusLine.command' "${settings}.lbwc-statusline.bak")" = "other-status" ]
}
