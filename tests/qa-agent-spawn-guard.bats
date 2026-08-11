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
    | bash "$2"' _ "$name" "$SCRIPTS_DIR/agent-spawn-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"contract is missing, stale, tampered, or not dispatched"* ]]
  [ "$(jq -r --arg name "$name" '.agents[$name].state' "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" = "registered" ]
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
