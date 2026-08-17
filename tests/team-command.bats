#!/usr/bin/env bats

load test_helper

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$REPO_ROOT/scripts/lbwc-config.sh"
  TRANSACTION="$REPO_ROOT/scripts/team-command-transaction.sh"
  TEST_ROOT="$(mktemp -d)"
  SETTINGS="$TEST_ROOT/settings.json"
  printf '%s\n' '{}' > "$SETTINGS"
  PROJECT="$TEST_ROOT/project"
  mkdir -p "$PROJECT/src"
  git -C "$PROJECT" init -q
  export LBWC_SETTINGS_PATH="$SETTINGS"
}

teardown() {
  rm -rf "$TEST_ROOT" 2>/dev/null || { sleep 1; rm -rf "$TEST_ROOT" 2>/dev/null || true; }
}

prepare_run() {
  local run_id="$1"
  shift
  LBWC_SETTINGS_PATH="$SETTINGS" run bash "$TRANSACTION" prepare \
    --project-root "$PROJECT" --run-id "$run_id" --instruction "implement scoped change" "$@"
  [ "$status" -eq 0 ]
  CONTRACT_ID=$(jq -r '.contract_id' <<< "$output")
  RUN_ROOT=$(jq -r '.run_root' <<< "$output")
  [ -n "$CONTRACT_ID" ]
  [ -n "$RUN_ROOT" ]
}

manifest_set_running() {
  local manifest="$RUN_ROOT/agent-manifest.json" updated
  updated=$(jq -c '.agents |= with_entries(.value.state = "running")' "$manifest")
  printf '%s\n' "$updated" > "$manifest"
}

manifest_bind_task() {
  local manifest="$RUN_ROOT/agent-manifest.json" updated
  updated=$(jq -c --arg task "$1" --arg contract "$CONTRACT_ID" '
    .tasks = ((.tasks // {}) + {($task): {native_task_id:$task, contract_id:$contract, contract_path:"", contract_digest:"", subject:$contract, state:"created", created_at:"2026-01-01T00:00:00Z"}})
  ' "$manifest")
  printf '%s\n' "$updated" > "$manifest"
}

record_full_roster() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
      --contract-id "$CONTRACT_ID" --teammate "$name"
    [ "$status" -eq 0 ]
  done < <(jq -r '.teammates[].name' <<< "$output")
}

@test "agent teams status reports disabled without changing settings" {
  run env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CONFIG_DIR="$TEST_ROOT/claude" \
    bash "$SCRIPT" agent-teams-status --settings "$SETTINGS"

  [ "$status" -eq 0 ]
  jq -e '.enabled == false and .source == "none"' <<< "$output" >/dev/null
  [ "$(jq -c . "$SETTINGS")" = "{}" ]
}

@test "agent teams check is RED when settings omit the teams flag" {
  run env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
    bash "$SCRIPT" agent-teams-check --settings "$SETTINGS"

  [ "$status" -eq 0 ]
  [ "$output" = "TEAM CHECK IS NOT ENABLED." ]
}

@test "agent teams check is GREEN when user settings enable the teams flag" {
  jq -n '{env:{CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:"1"}}' > "$SETTINGS"

  run env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
    bash "$SCRIPT" agent-teams-check --settings "$SETTINGS"

  [ "$status" -eq 0 ]
  [ "$output" = "TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK." ]
}

@test "agent teams check is GREEN when project settings enable the teams flag" {
  mkdir -p "$PROJECT/.claude" "$TEST_ROOT/claude"
  jq -n '{env:{CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:"1"}}' \
    > "$PROJECT/.claude/settings.json"

  run env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CONFIG_DIR="$TEST_ROOT/claude" \
    bash "$SCRIPT" agent-teams-check --project-root "$PROJECT"

  [ "$status" -eq 0 ]
  [ "$output" = "TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK." ]
}

@test "agent teams check stays RED on an explicit empty settings pin even if project is enabled" {
  mkdir -p "$PROJECT/.claude"
  jq -n '{env:{CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:"1"}}' \
    > "$PROJECT/.claude/settings.json"

  run env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
    bash "$SCRIPT" agent-teams-check --settings "$SETTINGS" --project-root "$PROJECT"

  [ "$status" -eq 0 ]
  [ "$output" = "TEAM CHECK IS NOT ENABLED." ]
}

@test "agent teams enable requires explicit approval" {
  run bash "$SCRIPT" agent-teams-enable --settings "$SETTINGS"

  [ "$status" -ne 0 ]
  [[ "$output" == *"explicit approval"* ]]
  jq -e 'has("env") | not' "$SETTINGS" >/dev/null
}

@test "approved agent teams enable writes settings and restart guidance is observable" {
  run bash "$SCRIPT" agent-teams-enable --settings "$SETTINGS" --approved

  [ "$status" -eq 0 ]
  jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"' \
    "$SETTINGS" >/dev/null
  [[ "$output" == *"restart Claude Code"* ]]
}

@test "team command documents proposal gating, repeatable root scope, and native spawn rules" {
  command="$REPO_ROOT/commands/team.md"

  grep -F -- '--scope <path>' "$command"
  grep -F -- 'default scope is `.`' "$command"
  grep -F -- 'No contract, native task, generated definition, or teammate exists until confirmation.' "$command"
  grep -F -- 'Never pass `team_name`' "$command"
  grep -F -- 'Do not edit Claude Code native team configuration' "$command"
  grep -F 'TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK.' "$command"
  grep -F 'TEAM CHECK IS NOT ENABLED.' "$command"
  grep -F 'do not ask whether team agents should be enabled' "$command"
  grep -F 'agent-teams-check --project-root' "$command"
  grep -F 'lbwc-model" refresh' "$command"
  grep -F 'lbwc-routing.sh check' "$command"
}

@test "team command documents execution choice and an explicit tmux spawn branch" {
  command="$REPO_ROOT/commands/team.md"

  grep -F 'agent_execution_mode=ask' "$command"
  grep -F 'Native team' "$command"
  grep -F 'TMUX panes' "$command"
  grep -F 'Cancel spawn' "$command"
  grep -F 'Do not replace native teams' "$command"
  grep -F -- '--requested-backend' "$command"
  grep -F -- '--resolved-backend' "$command"
  grep -F -- '--control-root' "$command"
  grep -F -- '--assert-snapshot' "$command"
  grep -F 'agent-generator.sh --execution-backend' "$command"
  grep -F 'Schema 2 generation omits `--execution-backend`' "$command"
  grep -F 'references/tmux-spawn-protocol.md' "$command"
  grep -F 'tmux-spawn-group.sh" dispatch' "$command"
  grep -F 'CLAUDE_SESSION_ID' "$command"
  grep -F 'If `snapshot.resolved_backend` is `in_process`' "$command"
  grep -F 'If `snapshot.resolved_backend` is `tmux`' "$command"
  grep -F 'Do not call native Agent.' "$command"
  grep -F 'Do not run `prepare`' "$command"
  grep -F 'Choose one collision-safe run id, then issue' "$command"
  grep -F '[ -f "$SNAPSHOT_PATH" ]' "$command"
  ! grep -F 'MAIN_ID=main-session' "$command"
  ! grep -F '$AGENTS_JSON' "$command"
}

@test "team command is registered in the command section contract" {
  jq -e '.commands["team.md"].required_headings == ["Context","Guard","Steps","Failure and recovery","Output Format","Next Up"]' \
    "$REPO_ROOT/config/command-sections.json" >/dev/null
}

@test "preflight is read-only and reports canonical scopes and no side effects" {
  run bash "$TRANSACTION" preflight --project-root "$PROJECT" --scope src --scope src

  [ "$status" -eq 0 ]
  expected_root=$(cd -P "$PROJECT" && pwd -P)
  jq -e --arg root "$expected_root" '
    .project_root == $root
    and .scopes == ["src"]
    and .side_effects == false
    and .team_mode == "pair"
  ' <<< "$output" >/dev/null
  [ ! -e "$PROJECT/.temporary-agent-runfiles" ]
}

@test "preflight defaults scope to the repository root" {
  run bash "$TRANSACTION" preflight --project-root "$PROJECT"

  [ "$status" -eq 0 ]
  jq -e '.scopes == ["."]' <<< "$output" >/dev/null
}

@test "preflight rejects a protected scope" {
  mkdir -p "$PROJECT/.claude"
  run bash "$TRANSACTION" preflight --project-root "$PROJECT" --scope .claude

  [ "$status" -ne 0 ]
  [[ "$output" == *"protected"* ]]
  [ ! -e "$PROJECT/.temporary-agent-runfiles" ]
}

@test "prepare creates a run root, one dispatched pair contract, and generated definitions" {
  prepare_run run-pair --scope src

  jq -e --argjson scopes '["src"]' '.ordered_actions == ["agent_spawn", "task_create"]
    and .team_mode == "pair"
    and .scopes == $scopes
    and (.teammates | length) == 2
    and .contract_state == "dispatched"' <<< "$output" >/dev/null
  [ -f "$RUN_ROOT/run.json" ]
  [ -f "$RUN_ROOT/diagnostics.jsonl" ]
  jq -e '.status == "planned"' "$RUN_ROOT/run.json" >/dev/null
  contract_path="$RUN_ROOT/contracts/tasks/$CONTRACT_ID.json"
  [ -f "$contract_path" ]
  jq -e --arg id "$CONTRACT_ID" '
    .schema_version == 3
    and .contract_id == $id
    and .team_mode == "pair"
    and .roles == ["web-engineer", "web-code-critic"]
    and .runtime_kind == "native-team"
    and .communication_policy == "native-team"
    and .requested_backend == "in_process"
    and .resolved_backend == "in_process"
    and .state == "dispatched"
    and .capabilities_by_role["web-engineer"] == [{access:"write",kind:"directory",path:"src"}]
    and .capabilities_by_role["web-code-critic"] == []
  ' "$contract_path" >/dev/null
  manifest="$RUN_ROOT/agent-manifest.json"
  [ -f "$manifest" ]
  while IFS= read -r name; do
    jq -e --arg name "$name" --arg id "$CONTRACT_ID" '
      .agents[$name].contract_id == $id
      and .agents[$name].schema_version == 3
      and .agents[$name].runtime_kind == "native-team"
      and .agents[$name].state == "registered"
    ' "$manifest" >/dev/null
    [ -f "$PROJECT/.claude/agents/$name.md" ]
  done < <(jq -r '.teammates[].name' <<< "$output")
}

@test "prepare derives backend records from the contract before native spawn" {
  prepare_run run-backend --scope src

  jq -e '
    .schema_version == 3
    and .requested_backend == "in_process"
    and .resolved_backend == "in_process"
    and .ordered_actions == ["agent_spawn", "task_create"]
  ' <<< "$output" >/dev/null
  jq -e '
    .requested_backend == "in_process"
    and .resolved_backend == "in_process"
    and (.teammates | length) == 2
  ' "$RUN_ROOT/run.json" >/dev/null
  jq -e '
    .requested_backend == "in_process"
    and .resolved_backend == "in_process"
  ' "$RUN_ROOT/contract.json" >/dev/null
}

@test "spawn-payload rejects backend sidecar drift from the contract" {
  prepare_run run-backend-drift --scope src
  jq '.resolved_backend = "tmux"' "$RUN_ROOT/run.json" > "$TEST_ROOT/run.json"
  mv "$TEST_ROOT/run.json" "$RUN_ROOT/run.json"

  run bash "$TRANSACTION" spawn-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"backend metadata does not match the contract"* ]]
}

@test "prepare with --test-dev issues a trio contract and registers three teammates" {
  prepare_run run-trio --scope src --test-dev

  jq -e '.team_mode == "trio" and (.teammates | length) == 3' <<< "$output" >/dev/null
  contract_path="$RUN_ROOT/contracts/tasks/$CONTRACT_ID.json"
  jq -e '
    .team_mode == "trio"
    and .roles == ["web-engineer", "web-code-critic", "test-dev"]
    and .test_dev == true
    and .capabilities_by_role["test-dev"] == []
  ' "$contract_path" >/dev/null
}

@test "prepare issues exactly one contract for the whole roster" {
  prepare_run run-single

  [ "$(find "$RUN_ROOT/contracts/tasks" -name '*.json' | wc -l | tr -d ' ')" -eq 1 ]
  jq -e '.teammates | length == 2' "$RUN_ROOT/run.json" >/dev/null
}

@test "prepare keeps an initialized project control root while always creating a run root" {
  mkdir -p "$PROJECT/.lbwc-planning"
  route_binary="$TEST_ROOT/claude-route-fixture"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "fixture"' > "$route_binary"
  chmod +x "$route_binary"
  route_sha=$(shasum -a 256 "$route_binary" | awk '{print $1}')
  jq -n --arg binary "$route_binary" --arg sha "$route_sha" '
    {
      schema_version: 1,
      source: {binary_path: $binary, version: "fixture", sha256: $sha, detected_at: "2035-01-02T03:04:05Z"},
      models: [{selector: "nova-route", label: "Nova Route", description: "Fixture selector"}],
      reasoning: {scope: "global", accepted_values: ["deliberate"], model_associations: {"nova-route": ["deliberate"]}}
    }
  ' > "$PROJECT/.lbwc-planning/claude-capabilities.json"
  jq --slurpfile defaults "$REPO_ROOT/templates/agent-roles/defaults.json" '
    . + {
      schema_version: 1,
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {
            roles: ($defaults[0] | keys | map({key: ., value: {model: "nova-route", reasoning: "deliberate", status: "resolved"}}) | from_entries)
          },
          turbo: {roles: {}}
        }
      }
    }
  ' "$REPO_ROOT/config/settings.json" > "$PROJECT/.lbwc-planning/config.json"

  prepare_run run-init --scope src

  jq -e '.control_root_kind == "active-planning" and (.run_root | length) > 0' <<< "$output" >/dev/null
  [ -f "$RUN_ROOT/run.json" ]
  [ -f "$RUN_ROOT/contract.json" ]
  [ -f "$RUN_ROOT/diagnostics.jsonl" ]
  [ -f "$PROJECT/.lbwc-planning/.agent-manifest.json" ]
  [ -f "$PROJECT/.lbwc-planning/.contracts/tasks/$CONTRACT_ID.json" ]
}

@test "spawn-payload emits Agent calls with only subagent_type and name" {
  prepare_run run-spawn --scope src

  run bash "$TRANSACTION" spawn-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"

  [ "$status" -eq 0 ]
  jq -e '
    (.agent_payloads | length) == 2
    and all(.agent_payloads[]; (keys | sort) == ["name", "subagent_type"])
    and (.next_action == "task-payload")
  ' <<< "$output" >/dev/null
  jq -e '[.agent_payloads[].subagent_type] == .roster' <<< "$output" >/dev/null
}

@test "spawn-payload blocks a teammate whose manifest identity does not match the contract" {
  prepare_run run-spawn-guard --scope src
  manifest="$RUN_ROOT/agent-manifest.json"
  name=$(jq -r '.teammates[0].name' "$RUN_ROOT/run.json")
  updated=$(jq -c --arg name "$name" '.agents[$name].contract_id = "tampered"' "$manifest")
  printf '%s\n' "$updated" > "$manifest"

  run bash "$TRANSACTION" spawn-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest backend metadata does not match the contract"* ]]
}

@test "record-spawn tracks the roster and blocks unknown or unclaimed teammates" {
  prepare_run run-record --scope src

  run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --teammate "lbwc-ghost"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not registered"* ]]

  name=$(jq -r '.teammates[0].name' "$RUN_ROOT/run.json")
  run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --teammate "$name"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not running"* ]]

  manifest_set_running
  run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --teammate "$name"
  [ "$status" -eq 0 ]
  jq -e '.recorded == true and .spawn_complete == false' <<< "$output" >/dev/null
}

@test "task-payload blocks until every roster teammate has recorded spawn evidence" {
  prepare_run run-gate --scope src
  manifest_set_running

  run bash "$TRANSACTION" task-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"spawn evidence is missing"* ]]

  first=$(jq -r '.teammates[0].name' "$RUN_ROOT/run.json")
  run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --teammate "$first"
  [ "$status" -eq 0 ]

  run bash "$TRANSACTION" task-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"spawn evidence is missing"* ]]

  second=$(jq -r '.teammates[1].name' "$RUN_ROOT/run.json")
  run bash "$TRANSACTION" record-spawn --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --teammate "$second"
  [ "$status" -eq 0 ]
  jq -e '.spawn_complete == true' <<< "$output" >/dev/null

  run bash "$TRANSACTION" task-payload --project-root "$PROJECT" --run-root "$RUN_ROOT"
  [ "$status" -eq 0 ]
  jq -e --arg id "$CONTRACT_ID" '.task.subject == $id and .task.description == $id' <<< "$output" >/dev/null
}

@test "record-task binds the contract-bound native task after spawns" {
  prepare_run run-task --scope src
  manifest_set_running
  record_full_roster

  run bash "$TRANSACTION" record-task --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --task-id task-1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not bound"* ]]

  manifest_bind_task task-1
  run bash "$TRANSACTION" record-task --project-root "$PROJECT" --run-root "$RUN_ROOT" \
    --contract-id "$CONTRACT_ID" --task-id task-1
  [ "$status" -eq 0 ]
  jq -e '.recorded == true' <<< "$output" >/dev/null
  jq -e '.records["task:task-1"].status == "bound"' "$RUN_ROOT/run.json" >/dev/null
}

@test "fail retains runfiles and appends diagnostics" {
  prepare_run run-fail --scope src

  run bash "$TRANSACTION" fail --project-root "$PROJECT" --run-root "$RUN_ROOT" --event "spawn rejected"
  [ "$status" -eq 0 ]
  jq -e '.status == "failed"' <<< "$output" >/dev/null
  [ -f "$RUN_ROOT/run.json" ]
  jq -e '.status == "failed"' "$RUN_ROOT/run.json" >/dev/null
  grep -F 'spawn rejected' "$RUN_ROOT/diagnostics.jsonl" >/dev/null
}

@test "summary reports terminal status and records" {
  prepare_run run-summary --scope src
  run bash "$TRANSACTION" complete --project-root "$PROJECT" --run-root "$RUN_ROOT" --event "done"
  [ "$status" -eq 0 ]

  run bash "$TRANSACTION" summary --project-root "$PROJECT" --run-root "$RUN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"run_id: run-summary"* ]]
  [[ "$output" == *"status: completed"* ]]
  [[ "$output" == *"$CONTRACT_ID=dispatched"* ]]
}

@test "team context directive is self-contained and resolves plugin root, project root, and RED team check with LINK unset" {
  command="$REPO_ROOT/commands/team.md"
  directive=$(awk '/^!`/{sub(/^!`/,""); sub(/`$/,""); print; exit}' "$command")
  [ -n "$directive" ]
  [[ "$directive" != *'${LINK}'* ]]

  run env -u LINK -u PROJECT_ROOT -u AGENT_TEAMS_CHECK -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_CONFIG_DIR="$TEST_ROOT/claude" \
    LBWC_SETTINGS_PATH="$SETTINGS" \
    bash -c "cd \"$PROJECT\" && $directive"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Plugin root: "* ]]
  [[ "$output" == *"Project root: "* ]]
  [[ "$output" == *"TEAM CHECK IS NOT ENABLED."* ]]
  [[ "$output" != *"TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK."* ]]
  [ ! -e "$PROJECT/.temporary-agent-runfiles" ]
  [ ! -e "$PROJECT/.lbwc-planning" ]
  [ "$(jq -c . "$SETTINGS")" = "{}" ]
}

@test "team context directive is GREEN when Claude Code settings already enable agent teams" {
  command="$REPO_ROOT/commands/team.md"
  directive=$(awk '/^!`/{sub(/^!`/,""); sub(/`$/,""); print; exit}' "$command")
  mkdir -p "$TEST_ROOT/claude"
  jq -n '{env:{CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:"1"}}' \
    > "$TEST_ROOT/claude/settings.json"

  run env -u LINK -u PROJECT_ROOT -u AGENT_TEAMS_CHECK -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_CONFIG_DIR="$TEST_ROOT/claude" \
    bash -c "cd \"$PROJECT\" && $directive"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK."* ]]
  [[ "$output" != *"TEAM CHECK IS NOT ENABLED."* ]]
}

@test "team command uses literal {LINK} and {PROJECT_ROOT} placeholders outside the first directive" {
  command="$REPO_ROOT/commands/team.md"
  remainder=$(sed '/^!`/d' "$command")

  ! grep -F '${LINK}' <<< "$remainder"
  ! grep -F '$LINK' <<< "$remainder"
  ! grep -F '$PROJECT_ROOT' <<< "$remainder"
  grep -F '{LINK}' <<< "$remainder" >/dev/null
  grep -F '{PROJECT_ROOT}' <<< "$remainder" >/dev/null
}
