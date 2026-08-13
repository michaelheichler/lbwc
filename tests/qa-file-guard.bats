#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  EXTERNAL_TEST_DIR=""
  cd "$TEST_TEMP_DIR"
}

teardown() {
  [ -z "$EXTERNAL_TEST_DIR" ] || rm -rf "$EXTERNAL_TEST_DIR"
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

run_guard() {
  local file_path="$1" agent_id="${2:-}" tool_name="${3:-Write}"
  payload "tool_name=$tool_name" "tool_input.file_path=$file_path" "agent_id=$agent_id" | bash "$SCRIPTS_DIR/file-guard.sh"
}

run_notebook_guard() {
  local notebook_path="$1" agent_id="$2"
  payload "tool_name=NotebookEdit" "tool_input.notebook_path=$notebook_path" "agent_id=$agent_id" | bash "$SCRIPTS_DIR/file-guard.sh"
}

make_guard_contract() {
  local task="${1:-task-1}" path id
  path=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" "$task" \
    --command test --role python-engineer --team solo --job "guard write" \
    --write-allowance src/allowed.py)
  id=$(basename "$path" .json)
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null
  printf '%s' "$path"
}

@test "unscoped role writes anywhere" {
  run run_guard "src/main.py"
  [ "$status" -eq 0 ]
}

@test "scout may write its assigned planning file" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"scout-1\":{\"role\":\"scout\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\".lbwc-planning/phases/01-x/RESEARCH.md\"]}}}"
  run run_guard ".lbwc-planning/phases/01-x/RESEARCH.md" "scout-1"
  [ "$status" -eq 0 ]
}

@test "scout is blocked from writing product source" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  run run_guard "src/main.py" "scout-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"scout"* ]]
}

@test "generated identity without a project root fails closed" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"dev-1":{"role":"python-engineer","write_allowances":["src/main.py"]}}}'

  run run_guard "src/main.py" "dev-1"

  [ "$status" -eq 2 ]
}

@test "architect may write its assigned roadmap but not product source" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"architect-1\":{\"role\":\"architect\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\".lbwc-planning/ROADMAP.md\"]}}}"
  run run_guard ".lbwc-planning/ROADMAP.md" "architect-1"
  [ "$status" -eq 0 ]
  run run_guard "src/main.py" "architect-1"
  [ "$status" -eq 2 ]
}

@test "docs may write its assigned markdown but not product source" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"docs-1\":{\"role\":\"docs\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"README.md\"]}}}"
  run run_guard "README.md" "docs-1"
  [ "$status" -eq 0 ]
  run run_guard "src/main.py" "docs-1"
  [ "$status" -eq 2 ]
}

@test "qa-author may write an assigned test file but not product source" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"qaa-1\":{\"role\":\"qa-author\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"tests/test_thing.py\"]}}}"
  run run_guard "tests/test_thing.py" "qaa-1"
  [ "$status" -eq 0 ]
  run run_guard "src/main.py" "qaa-1"
  [ "$status" -eq 2 ]
}

@test "test-dev may write an assigned test file but not product source" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"td-1\":{\"role\":\"test-dev\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/thing.test.ts\"]}}}"
  run run_guard "src/thing.test.ts" "td-1"
  [ "$status" -eq 0 ]
  run run_guard "src/main.py" "td-1"
  [ "$status" -eq 2 ]
}

@test "worker may write only its exact assigned hook path" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  run run_guard "hooks/skill_gate.py" "dev-1"
  [ "$status" -eq 0 ]
}

@test "worker cannot write protected framework paths even when the manifest grants them" {
  local protected
  for protected in \
    config/subagent-critical-execution.txt \
    config/destructive-commands.txt \
    scripts/file-guard.sh \
    scripts/task-contract.sh \
    scripts/agent-lifecycle.sh \
    .lbwc-planning/.agent-manifest.json \
    .lbwc-planning/.contracts/tasks/forged.json \
    .claude/agents/forged.md
  do
    write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"$protected\"]}}}"
    run run_guard "$protected" "dev-1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot write LBWC policy"* ]]
  done
}

@test "contract worker may write its exact allowance" {
  local contract
  contract=$(make_guard_contract)
  local id="$(basename "$contract" .json)"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"],\"contract_path\":\"$contract\",\"contract_id\":\"$id\",\"contract_digest\":\"$(jq -r .contract_digest "$contract")\",\"task_identity\":\"$id\"}}}"
  run run_guard "src/allowed.py" "dev-1"
  [ "$status" -eq 0 ]
}

@test "contract worker is blocked when contract is missing" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"],\"contract_path\":\"$TEST_TEMP_DIR/missing.json\",\"contract_id\":\"guard-contract\",\"contract_digest\":\"deadbeef\",\"task_identity\":\"task-1\"}}}"
  run run_guard "src/allowed.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing"* ]]
}

@test "contract worker is blocked when contract is tampered" {
  local contract
  contract=$(make_guard_contract)
  jq '.write_allowances = ["src/other.py"]' "$contract" > "$contract.tmp" && mv "$contract.tmp" "$contract"
  local id="$(basename "$contract" .json)"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"],\"contract_path\":\"$contract\",\"contract_id\":\"$id\",\"contract_digest\":\"$(jq -r .contract_digest "$contract")\",\"task_identity\":\"$id\"}}}"
  run run_guard "src/allowed.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing"* ]]
}

@test "contract worker is blocked when manifest contract id mismatches" {
  local contract
  contract=$(make_guard_contract)
  local id="$(basename "$contract" .json)"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"],\"contract_path\":\"$contract\",\"contract_id\":\"wrong-id\",\"contract_digest\":\"$(jq -r .contract_digest "$contract")\",\"task_identity\":\"$id\"}}}"
  run run_guard "src/allowed.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing"* ]]
}

@test "contract worker is blocked when manifest task is stale" {
  local contract
  contract=$(make_guard_contract)
  local id="$(basename "$contract" .json)"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"],\"contract_path\":\"$contract\",\"contract_id\":\"$id\",\"contract_digest\":\"$(jq -r .contract_digest "$contract")\",\"task_identity\":\"old-task\"}}}"
  run run_guard "src/allowed.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing"* ]]
}

@test "worker cannot write a different hook path" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  run run_guard "hooks/context_usage.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"assigned write allowance"* ]]
}

@test "NotebookEdit is blocked outside the worker exact allowance" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"notebooks/allowed.ipynb\"]}}}"
  run run_notebook_guard "notebooks/unassigned.ipynb" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"assigned write allowance"* ]]
}

@test "NotebookEdit is registered with the manifest file guard" {
  run jq -e '
    .hooks.PreToolUse[]
    | select(.matcher == "Write|Edit|NotebookEdit")
    | .hooks[]
    | select(.command | contains("file-guard.sh"))
  ' "$PROJECT_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

@test "worker without an assigned write allowance is blocked" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\"}}}"
  run run_guard "src/main.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no assigned write allowance"* ]]
}

@test "hook allowance requires no worker file report" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  run run_guard "hooks/skill_gate.py" "dev-1"
  [ "$status" -eq 0 ]
}

@test "worker cannot use its allowance outside the primary workspace" {
  mkdir -p "$TEST_TEMP_DIR/secondary"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  local json
  json=$(payload "tool_name=Write" "tool_input.file_path=hooks/skill_gate.py" "agent_id=dev-1" "cwd=$TEST_TEMP_DIR/secondary")
  run bash -c "printf '%s' '$json' | LBWC_PLANNING_DIR='$TEST_TEMP_DIR/.lbwc-planning' bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"primary workspace"* ]]
}

@test "schema 3 directory capability permits descendants but not siblings" {
  mkdir -p "$TEST_TEMP_DIR/src/web"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "$(jq -cn --arg root "$TEST_TEMP_DIR" '{agents:{"dev-1":{role:"web-engineer",project_root:$root,capabilities:[{access:"write",kind:"directory",path:"src/web"}]}}}')"
  run run_guard "src/web/page.ts" "dev-1"
  [ "$status" -eq 0 ]
  run run_guard "src/api/page.ts" "dev-1"
  [ "$status" -eq 2 ]
}

@test "schema 3 repository root capability cannot write temporary control files" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "$(jq -cn --arg root "$TEST_TEMP_DIR" '{agents:{"dev-1":{role:"web-engineer",project_root:$root,capabilities:[{access:"write",kind:"directory",path:"."}]}}}')"
  run run_guard ".lbwc-planning/config.json" "dev-1"
  [ "$status" -eq 2 ]
  run run_guard ".temporary-agent-runfiles/runs/one/run.json" "dev-1"
  [ "$status" -eq 2 ]
}

@test "schema 3 repository root capability cannot write secrets" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/root-secrets" contract id
  mkdir -p "$control_root"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" "root-secrets" \
    --command team --role python-engineer --team solo --job "root scope" \
    --control-root "$control_root" --write-capability directory:.)
  id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null
  printf '%s' "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"schema_version\":3,\"capabilities\":[{\"access\":\"write\",\"kind\":\"directory\",\"path\":\".\"}],\"write_allowances\":[\".\"],\"contract_path\":\"$contract\",\"contract_id\":\"$id\",\"contract_digest\":\"$(jq -r .contract_digest "$contract")\",\"task_identity\":\"$id\"}}}" > "$control_root/agent-manifest.json"

  for secret in .env config/private.key credentials.json; do
    run bash -c 'jq -cn --arg path "$1" --arg cwd "$2" "{tool_name:\"Write\",tool_input:{file_path:\$path},agent_id:\"dev-1\",cwd:\$cwd}" | LBWC_CONTROL_ROOT="$3" bash "$4"' _ "$secret" "$TEST_TEMP_DIR" "$control_root" "$SCRIPTS_DIR/file-guard.sh"
    [ "$status" -eq 2 ]
  done
}

@test "registered lbwc worker outside primary workspace is blocked without planning override" {
  mkdir -p "$TEST_TEMP_DIR/secondary"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-dev-a\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  local json
  json=$(payload "tool_name=Write" "tool_input.file_path=hooks/skill_gate.py" "agent_id=lbwc-dev-a" "cwd=$TEST_TEMP_DIR/secondary")
  run bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"manifest"* ]]
}

@test "worker cannot write exact allowance through symlinked target outside primary root" {
  EXTERNAL_TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_TEMP_DIR/hooks"
  touch "$EXTERNAL_TEST_DIR/skill_gate.py"
  ln -s "$EXTERNAL_TEST_DIR/skill_gate.py" "$TEST_TEMP_DIR/hooks/skill_gate.py"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  run run_guard "hooks/skill_gate.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"canonical primary root"* ]]
}

@test "worker is blocked promptly when an exact allowance is a self-referential symlink" {
  mkdir -p "$TEST_TEMP_DIR/hooks"
  ln -s "skill_gate.py" "$TEST_TEMP_DIR/hooks/skill_gate.py"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  local json
  json=$(payload "tool_name=Write" "tool_input.file_path=hooks/skill_gate.py" "agent_id=dev-1")
  run timeout 2s bash "$SCRIPTS_DIR/file-guard.sh" <<< "$json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"canonical primary root"* ]]
}

@test "worker cannot write exact allowance through symlinked parent outside primary root" {
  EXTERNAL_TEST_DIR=$(mktemp -d)
  ln -s "$EXTERNAL_TEST_DIR" "$TEST_TEMP_DIR/hooks"
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"dev-1\":{\"role\":\"python-engineer\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"hooks/skill_gate.py\"]}}}"
  run run_guard "hooks/skill_gate.py" "dev-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"canonical primary root"* ]]
}

@test "main session must delegate product writes while a pair is open" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"lbwc-dev-a":{"role":"python-engineer","state":"running"}}}'
  run run_guard "src/main.py"
  [ "$status" -eq 2 ]
  [[ "$output" == *"delegate"* ]]
}

@test "main session may still write docs while a pair is open" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"lbwc-dev-a":{"role":"python-engineer","state":"running"}}}'
  run run_guard "docs/notes.md"
  [ "$status" -eq 0 ]
}

@test "main session writes freely once every pair member is used" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"lbwc-dev-a":{"role":"python-engineer","state":"used"}}}'
  run run_guard "src/main.py"
  [ "$status" -eq 0 ]
}

@test "path traversal in file path is blocked" {
  run run_guard "../outside/secret.py"
  [ "$status" -eq 2 ]
}

@test "qa-author may write a relative test helper resolved against the hook cwd" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"qaa-1\":{\"role\":\"qa-author\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"tests/helpers.py\"]}}}"
  local json
  json=$(payload "tool_name=Write" "tool_input.file_path=tests/helpers.py" "agent_id=qaa-1" "cwd=$TEST_TEMP_DIR")
  run bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "missing jq blocks file writes before input handling" {
  local no_jq_path="$TEST_TEMP_DIR/no-jq-bin"
  mkdir -p "$no_jq_path"
  ln -s "$(command -v bash)" "$no_jq_path/bash"

  run env PATH="$no_jq_path" bash -c "printf '%s' '{}' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq not available"* ]]
}
