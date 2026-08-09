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
