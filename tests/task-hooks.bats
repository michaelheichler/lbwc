#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ADMISSION="$REPO_ROOT/scripts/task-admission-guard.sh"
  COMPLETION="$REPO_ROOT/scripts/task-completion-guard.sh"
  TEST_ROOT="$(mktemp -d)"
  TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
  CONTROL_ROOT="$TEST_ROOT/.temporary-agent-runfiles/runs/native-task"
  mkdir -p "$CONTROL_ROOT"
  CONTRACT=$(bash "$REPO_ROOT/scripts/task-contract.sh" issue "$TEST_ROOT" native-task \
    --command team --role web-engineer --team solo --job "implement native task" \
    --control-root "$CONTROL_ROOT" --write-capability directory:src/web)
  CONTRACT_ID="$(basename "$CONTRACT" .json)"
  jq -n --arg contract "$CONTRACT" --arg id "$CONTRACT_ID" --arg root "$TEST_ROOT" \
    '{agents:{"lbwc-web-engineer-native":{
      name:"lbwc-web-engineer-native", role:"web-engineer", state:"running",
      project_root:$root, contract_enabled:true, contract_path:$contract,
      contract_id:$id, contract_digest:(input_filename | ""), task_identity:$id,
      schema_version:3, capabilities:[{access:"write",kind:"directory",path:"src/web"}],
      write_allowances:["src/web"], runtime_kind:"native-team", communication_policy:"native-team"
    }}}' /dev/null > "$CONTROL_ROOT/agent-manifest.json"
  CONTRACT_DIGEST=$(jq -r '.contract_digest' "$CONTRACT")
  jq --arg digest "$CONTRACT_DIGEST" '.agents["lbwc-web-engineer-native"].contract_digest = $digest' \
    "$CONTROL_ROOT/agent-manifest.json" > "$CONTROL_ROOT/manifest.tmp"
  mv "$CONTROL_ROOT/manifest.tmp" "$CONTROL_ROOT/agent-manifest.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

task_event() {
  local event="$1" task_id="$2" subject="$3"
  jq -cn --arg event "$event" --arg cwd "$TEST_ROOT" --arg id "$task_id" --arg subject "$subject" \
    '{hook_event_name:$event,cwd:$cwd,task_id:$id,task_subject:$subject,task_description:"implement native task",team_name:"native-team"}'
}

@test "TaskCreated binds a native task to one pending schema 3 contract" {
  run bash -c 'jq -cn --arg cwd "$1" --arg id native-1 --arg subject "$2" '\''{hook_event_name:"TaskCreated",cwd:$cwd,task_id:$id,task_subject:$subject,task_description:"implement native task"}'\'' | LBWC_CONTROL_ROOT="$3" bash "$4"' _ "$TEST_ROOT" "$CONTRACT_ID" "$CONTROL_ROOT" "$ADMISSION"
  [ "$status" -eq 0 ]
  jq -e --arg id native-1 --arg contract "$CONTRACT_ID" \
    '.tasks[$id].contract_id == $contract and .tasks[$id].state == "created"' \
    "$CONTROL_ROOT/agent-manifest.json" >/dev/null
}

@test "TaskCreated blocks an uncontracted native task" {
  run bash -c 'jq -cn --arg cwd "$1" '\''{hook_event_name:"TaskCreated",cwd:$cwd,task_id:"native-2",task_subject:"unrelated-task"}'\'' | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$TEST_ROOT" "$CONTROL_ROOT" "$ADMISSION"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no pending native-team contract"* ]]
}

@test "TaskCompleted blocks until the bound contract is verified" {
  task_event TaskCreated native-3 "$CONTRACT_ID" | LBWC_CONTROL_ROOT="$CONTROL_ROOT" bash "$ADMISSION"
  run bash -c 'jq -cn --arg cwd "$1" '\''{hook_event_name:"TaskCompleted",cwd:$cwd,task_id:"native-3"}'\'' | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$TEST_ROOT" "$CONTROL_ROOT" "$COMPLETION"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is not verified"* ]]
}

@test "TaskCompleted allows a verified bound contract and records completion" {
  task_event TaskCreated native-4 "$CONTRACT_ID" | LBWC_CONTROL_ROOT="$CONTROL_ROOT" bash "$ADMISSION"
  bash "$REPO_ROOT/scripts/task-contract.sh" state "$TEST_ROOT" "$CONTRACT_ID" dispatched >/dev/null
  bash "$REPO_ROOT/scripts/task-contract.sh" state "$TEST_ROOT" "$CONTRACT_ID" running >/dev/null
  bash "$REPO_ROOT/scripts/task-contract.sh" state "$TEST_ROOT" "$CONTRACT_ID" awaiting_review >/dev/null
  bash "$REPO_ROOT/scripts/task-contract.sh" state "$TEST_ROOT" "$CONTRACT_ID" verified >/dev/null

  run bash -c 'jq -cn --arg cwd "$1" '\''{hook_event_name:"TaskCompleted",cwd:$cwd,task_id:"native-4"}'\'' | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$TEST_ROOT" "$CONTROL_ROOT" "$COMPLETION"
  [ "$status" -eq 0 ]
  jq -e '.tasks["native-4"].state == "completed"' "$CONTROL_ROOT/agent-manifest.json" >/dev/null
}

@test "hooks register native task admission and completion without native config edits" {
  run jq -e '
    (.hooks.TaskCreated[0].hooks[0].command | contains("task-admission-guard.sh"))
    and (.hooks.TaskCompleted[0].hooks[0].command | contains("task-completion-guard.sh"))
  ' "$REPO_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_ROOT/.claude/teams" ]
}
