#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  ROUTE_BINARY="$TEST_TEMP_DIR/claude-route-fixture"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" fixture' > "$ROUTE_BINARY"
  chmod +x "$ROUTE_BINARY"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
  jq -n --arg binary "$ROUTE_BINARY" --arg sha "$ROUTE_SHA" '{schema_version:1,source:{binary_path:$binary,version:"fixture",sha256:$sha,detected_at:"2035-01-02T03:04:05Z"},models:[{selector:"nova-route",label:"Nova Route",description:"Fixture"}],reasoning:{scope:"global",accepted_values:["deliberate"],model_associations:{"nova-route":["deliberate"]}}}' > "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json"
  jq --slurpfile defaults "$PROJECT_ROOT/templates/agent-roles/defaults.json" '. + {schema_version:1,routing:{active_profile:"balanced",profiles:{quality:{roles:{}},balanced:{roles:($defaults[0]|keys|map({key:.,value:{model:"nova-route",reasoning:"deliberate",status:"resolved"}})|from_entries)},turbo:{roles:{}}}}}' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.tmp"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.tmp" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "missing jq blocks agent spawns before input handling" {
  local no_jq_path="$TEST_TEMP_DIR/no-jq-bin"
  mkdir -p "$no_jq_path"
  ln -s "$(command -v bash)" "$no_jq_path/bash"

  run env PATH="$no_jq_path" bash -c "printf '%s' '{}' | bash '$SCRIPTS_DIR/agent-spawn-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq not available"* ]]
}

@test "malformed JSON input is blocked instead of skipping the guard" {
  run bash -c "printf '%s' 'not json at all' | bash '$SCRIPTS_DIR/agent-spawn-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not parse tool call input"* ]]
}

@test "generated identity without a control root fails closed" {
  rm -rf "$TEST_TEMP_DIR/.lbwc-planning"

  run bash -c 'jq -cn '\''{tool_name:"Agent",tool_input:{subagent_type:"lbwc-docs-missing"}}'\'' | bash "$1"' _ "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"no resolvable control root or manifest"* ]]
}

@test "ordinary agent without a control root remains outside LBWC enforcement" {
  rm -rf "$TEST_TEMP_DIR/.lbwc-planning"

  run bash -c 'jq -cn '\''{tool_name:"Agent",tool_input:{subagent_type:"general-purpose"}}'\'' | bash "$1"' _ "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 0 ]
}

@test "spawn guard rejects a member of a second unclaimed generated group" {
  local first_contract second_contract first_id second_id
  first_contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" first-pair \
    --command test --role python-engineer --team pair --job "first build team")
  first_id=$(basename "$first_contract" .json)
  run bash "$SCRIPTS_DIR/agent-generator.sh" --pair python-engineer \
    --job "first build team" --contract "$first_contract" --task-id "$first_id"
  [ "$status" -eq 0 ]
  local first_engineer
  first_engineer=$(printf '%s\n' "$output" | grep 'ENGINEER: SPAWN_READY' | awk '{print $3}')
  [ -n "$first_engineer" ]
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$first_id" dispatched >/dev/null

  second_contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" second-pair \
    --command test --role python-engineer --team pair --job "second build team")
  second_id=$(basename "$second_contract" .json)
  run bash "$SCRIPTS_DIR/agent-generator.sh" --pair python-engineer \
    --job "second build team" --contract "$second_contract" --task-id "$second_id"
  [ "$status" -eq 0 ]
  local second_engineer
  second_engineer=$(printf '%s\n' "$output" | grep 'ENGINEER: SPAWN_READY' | awk '{print $3}')
  [ -n "$second_engineer" ]
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$second_id" dispatched >/dev/null

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | bash "$2"' _ "$second_engineer" "$SCRIPTS_DIR/agent-spawn-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Pair "*" is open, spawn every member before starting other work."* ]]
  [[ "$output" == *"$first_engineer"* ]]
  [ "$(jq -r --arg name "$second_engineer" '.agents[$name].state' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" = "registered" ]
}

@test "spawn guard rejects a generated agent whose contract was not dispatched" {
  local contract id name
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" planned-agent \
    --command test --role docs --team solo --job "write docs")
  id=$(basename "$contract" .json)
  run bash "$SCRIPTS_DIR/agent-generator.sh" docs --job "write docs" \
    --contract "$contract" --task-id "$id"
  [ "$status" -eq 0 ]
  name=$(printf '%s\n' "$output" | grep 'SPAWN_READY' | awk '{print $2}')

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing, stale, tampered, or not dispatched"* ]]
  [ "$(jq -r --arg name "$name" '.agents[$name].state' "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" = "registered" ]
}

@test "spawn guard rejects a manifest communication policy mismatch" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/spawn-policy" contract name
  mkdir -p "$control_root"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" spawn-policy \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:src/web)
  local contract_id
  contract_id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/agent-generator.sh" web-engineer --job "scope" \
    --contract "$contract" --task-id "$contract_id" --control-root "$control_root" \
    --write-capability directory:src/web >/dev/null
  name=$(jq -r '.agents | keys[0]' "$control_root/agent-manifest.json")
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$contract_id" dispatched >/dev/null
  jq --arg name "$name" '.agents[$name].communication_policy = "critic-relay"' \
    "$control_root/agent-manifest.json" > "$control_root/manifest.tmp"
  mv "$control_root/manifest.tmp" "$control_root/agent-manifest.json"

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"runtime or communication policy"* ]]
}

@test "native spawn guard rejects a conflicting model override" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/spawn-override" contract id name
  mkdir -p "$control_root"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" spawn-override \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:.)
  id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/agent-generator.sh" --native-team web-engineer --job "scope" \
    --task-id "$id" --contract "$contract" --control-root "$control_root" \
    --write-capability directory:. >/dev/null
  name=$(jq -r '.agents | keys[0]' "$control_root/agent-manifest.json")
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name,model:"wrong-model"}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"call-time model override conflicts with generated definition"* ]]
  [ "$(jq -r --arg name "$name" '.agents[$name].state' "$control_root/agent-manifest.json")" = "registered" ]
}

@test "spawn guard rewrites a full selector to the live host alias" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/spawn-map" contract id name
  mkdir -p "$control_root"
  jq --arg custom "leverframe:openai-oauth:codex-auto-review" '
    .models += [
      {selector:"claude-sonnet-5",label:"Sonnet 5",description:"Sonnet 5"},
      {selector:"sonnet",label:"sonnet",description:"sonnet"},
      {selector:$custom,label:$custom,description:$custom}
    ]
    | .host_agent_enum = ["sonnet","opus",$custom]
    | .agent_model_ids = {
        "nova-route":"nova-route",
        "claude-sonnet-5":"sonnet",
        "sonnet":"sonnet"
      }
    | .agent_model_ids[$custom] = $custom
  ' "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" > "$control_root/claude-capabilities.json"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
  jq --arg binary "$ROUTE_BINARY" --arg sha "$ROUTE_SHA" \
    '.source.binary_path = $binary | .source.sha256 = $sha' \
    "$control_root/claude-capabilities.json" > "$control_root/catalog.tmp"
  mv "$control_root/catalog.tmp" "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" spawn-map \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:.)
  id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/agent-generator.sh" --native-team web-engineer --job "scope" \
    --task-id "$id" --contract "$contract" --control-root "$control_root" \
    --write-capability directory:. >/dev/null
  name=$(jq -r '.agents | keys[0]' "$control_root/agent-manifest.json")
  jq --arg name "$name" '.agents[$name].model = "claude-sonnet-5"' \
    "$control_root/agent-manifest.json" > "$control_root/manifest.tmp"
  mv "$control_root/manifest.tmp" "$control_root/agent-manifest.json"
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | LBWC_CONTROL_ROOT="$2" CLAUDE_CODE_EXECPATH="$4" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh" "$ROUTE_BINARY"

  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.updatedInput.model == "sonnet"' <<< "$output" >/dev/null
}

@test "spawn guard leaves a live custom id unchanged" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/spawn-custom" contract id name custom
  custom="leverframe:openai-oauth:codex-auto-review"
  mkdir -p "$control_root"
  jq --arg custom "$custom" '
    .models += [{selector:$custom,label:$custom,description:$custom}]
    | .host_agent_enum = ["sonnet",$custom]
    | .agent_model_ids = {"nova-route":"nova-route"}
    | .agent_model_ids[$custom] = $custom
  ' "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" > "$control_root/claude-capabilities.json"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
  jq --arg binary "$ROUTE_BINARY" --arg sha "$ROUTE_SHA" \
    '.source.binary_path = $binary | .source.sha256 = $sha' \
    "$control_root/claude-capabilities.json" > "$control_root/catalog.tmp"
  mv "$control_root/catalog.tmp" "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" spawn-custom \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:.)
  id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/agent-generator.sh" --native-team web-engineer --job "scope" \
    --task-id "$id" --contract "$contract" --control-root "$control_root" \
    --write-capability directory:. >/dev/null
  name=$(jq -r '.agents | keys[0]' "$control_root/agent-manifest.json")
  jq --arg name "$name" --arg custom "$custom" '.agents[$name].model = $custom' \
    "$control_root/agent-manifest.json" > "$control_root/manifest.tmp"
  mv "$control_root/manifest.tmp" "$control_root/agent-manifest.json"
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | LBWC_CONTROL_ROOT="$2" CLAUDE_CODE_EXECPATH="$4" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh" "$ROUTE_BINARY"

  [ "$status" -eq 0 ]
  jq -e --arg custom "$custom" '.hookSpecificOutput.updatedInput.model == $custom' <<< "$output" >/dev/null
}

@test "spawn guard fails closed for a model missing from the live host enum" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/spawn-unknown" contract id name
  mkdir -p "$control_root"
  jq '
    .host_agent_enum = ["sonnet"]
    | .agent_model_ids = {"sonnet":"sonnet"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" > "$control_root/claude-capabilities.json"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
  jq --arg binary "$ROUTE_BINARY" --arg sha "$ROUTE_SHA" \
    '.source.binary_path = $binary | .source.sha256 = $sha' \
    "$control_root/claude-capabilities.json" > "$control_root/catalog.tmp"
  mv "$control_root/catalog.tmp" "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" spawn-unknown \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:.)
  id=$(basename "$contract" .json)
  bash "$SCRIPTS_DIR/agent-generator.sh" --native-team web-engineer --job "scope" \
    --task-id "$id" --contract "$contract" --control-root "$control_root" \
    --write-capability directory:. >/dev/null
  name=$(jq -r '.agents | keys[0]' "$control_root/agent-manifest.json")
  jq --arg name "$name" '.agents[$name].model = "not-a-model"' \
    "$control_root/agent-manifest.json" > "$control_root/manifest.tmp"
  mv "$control_root/manifest.tmp" "$control_root/agent-manifest.json"
  bash "$SCRIPTS_DIR/task-contract.sh" state "$TEST_TEMP_DIR" "$id" dispatched >/dev/null

  run bash -c 'jq -cn --arg name "$1" \
    '\''{tool_name:"Agent",tool_input:{subagent_type:$name}}'\'' \
    | LBWC_CONTROL_ROOT="$2" CLAUDE_CODE_EXECPATH="$4" bash "$3"' _ "$name" "$control_root" "$SCRIPTS_DIR/agent-spawn-guard.sh" "$ROUTE_BINARY"

  [ "$status" -eq 2 ]
  [[ "$output" == *"not present in the live host Agent enum"* ]]
}

@test "build contract serializes task teams within each dependency wave" {
  run grep -F \
    "Within a dependency wave, process tasks in PLAN order and admit exactly one task team at a time." \
    "$PROJECT_ROOT/commands/build.md"
  [ "$status" -eq 0 ]

  run grep -F \
    "Do not generate the next task's pair or trio until every manifest member of the current task team is \`used\` or \`expired\`." \
    "$PROJECT_ROOT/references/agent-spawn-protocol.md"
  [ "$status" -eq 0 ]
}
