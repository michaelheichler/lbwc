#!/usr/bin/env bats

load test_helper

GENERATOR="${SCRIPTS_DIR}/agent-generator.sh"
export GENERATOR

setup() {
  TEST_TEMP_DIR=$(mktemp -d /private/tmp/lbwc-generator.XXXXXX)
  export TEST_TEMP_DIR
  export _ORIG_HOME="${HOME:-}"
  export _ORIG_LBWC_PLANNING_DIR="${LBWC_PLANNING_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  unset LBWC_PLANNING_DIR CLAUDE_SESSION_ID 2>/dev/null || true
  mkdir -p "$TEST_TEMP_DIR/.lbwc-planning"
  ROUTE_BINARY="$TEST_TEMP_DIR/claude-generator-fixture"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "fixture"' > "$ROUTE_BINARY"
  chmod +x "$ROUTE_BINARY"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
  jq -n --arg binary "$ROUTE_BINARY" --arg sha "$ROUTE_SHA" '
    {
      schema_version: 1,
      source: {binary_path: $binary, version: "fixture", sha256: $sha, detected_at: "2035-01-02T03:04:05Z"},
      models: [
        {selector: "nova-route", label: "Nova Route", description: "Fixture selector"},
        {selector: "ember-path", label: "Ember Path", description: "Second fixture selector"}
      ],
      reasoning: {
        scope: "global",
        accepted_values: ["deliberate", "swift"],
        model_associations: {"nova-route": ["deliberate"]}
      }
    }
  ' > "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json"
  jq --slurpfile defaults "$PROJECT_ROOT/templates/agent-roles/defaults.json" '
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
  ' "$CONFIG_DIR/settings.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  CONTRACT_SEQUENCE=0
}

teardown() {
  teardown_temp_dir
}

generate() {
  local -a arguments=("$@") contract_args=()
  local mode=solo role job="" index=0 value contract task_id
  if [ "${arguments[0]:-}" = "--pair" ]; then mode=pair; index=1; fi
  if [ "${arguments[0]:-}" = "--trio" ]; then mode=trio; index=1; fi
  role="${arguments[$index]:-}"
  if [[ " ${arguments[*]} " != *" --contract "* ]] && jq -e --arg role "${role#lbwc-}" 'has($role)' "$PROJECT_ROOT/templates/agent-roles/defaults.json" >/dev/null 2>&1; then
    index=$((index + 1))
    while [ "$index" -lt "${#arguments[@]}" ]; do
      value=${arguments[$index]}
      case "$value" in
        --job) index=$((index + 1)); job=${arguments[$index]} ;;
        --job=*) job=${value#*=} ;;
        --write-allowance|--role-write-allowance)
          index=$((index + 1)); contract_args+=("$value" "${arguments[$index]}") ;;
        --write-allowance=*|--role-write-allowance=*)
          contract_args+=("${value%%=*}" "${value#*=}") ;;
      esac
      index=$((index + 1))
    done
    if [ -n "$job" ]; then
      CONTRACT_SEQUENCE=$((CONTRACT_SEQUENCE + 1))
      task_id="test-${BATS_TEST_NUMBER:-0}-${CONTRACT_SEQUENCE}"
      contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" "$task_id" \
        --command test --role "${role#lbwc-}" --team "$mode" --job "$job" "${contract_args[@]}")
      arguments+=(--contract "$contract" --task-id "$(basename "$contract" .json)")
    fi
  fi
  run bash -c 'cd "$TEST_TEMP_DIR" && exec bash "$GENERATOR" "$@"' _ "${arguments[@]}"
}

make_contract() {
  local role="$1" task="$2" allowances="$3" team="${4:-solo}" job="${5:-contract task}" path item
  local -a args=()
  while IFS= read -r item; do
    [ -n "$item" ] && args+=(--write-allowance "$item")
  done < <(jq -r '.[]' <<< "$allowances")
  path=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" "$task" \
    --command test --role "$role" --team "$team" --job "$job" "${args[@]}")
  printf '%s' "$path"
}

@test "no args exits 1 and prints usage" {
  generate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: agent-generator.sh"* ]]
}

@test "unknown role exits 1 with an invalid role message" {
  generate not-a-role --job "do something"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid role"* ]]
}

@test "valid role with --job generates a file, registers it, and prints SPAWN_READY" {
  generate docs --job "write a README"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPAWN_READY lbwc-docs-"* ]]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  [ -f "$TEST_TEMP_DIR/.claude/agents/$name.md" ]
  jq -e --arg name "$name" '.agents | has($name)' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "empty global question overrides still render denial and handoff" {
  generate docs --job "write a README" --disallowed-tools "" --initial-prompt ""
  [ "$status" -eq 0 ]
  local name rendered
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  rendered="$TEST_TEMP_DIR/.claude/agents/$name.md"
  grep -q '^disallowedTools: "AskUserQuestion"$' "$rendered"
  grep -q 'user_decision_required' "$rendered"
}

@test "partial question handoff override receives the complete structured contract" {
  generate docs --job "write a README" --initial-prompt "Return user_decision_required."
  [ "$status" -eq 0 ]
  local name rendered
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  rendered="$TEST_TEMP_DIR/.claude/agents/$name.md"
  grep -F '\"type\":\"user_decision_required\",\"question\":\"clear user question\",\"response_shape\":\"bounded choices or freeform\"' "$rendered"
}

@test "pending decision rejects direct transitions without creating runtime state" {
  run bash -c 'bash "$1" create "$2" session-1 && bash "$1" record-bounded "$2" session-1 Fast' \
    _ "$SCRIPTS_DIR/pending-decision.sh" "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -eq 2 ]
  [[ "$output" == *"direct decision transitions are disabled"* ]]
  [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.runtime" ]
}

@test "generated agents preserve the saved selector and reasoning" {
  jq '
    .routing.profiles.balanced.roles.architect
    = {model: "ember-path", reasoning: "swift", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  generate architect --job "build a roadmap"
  [ "$status" -eq 0 ]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-architect-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  jq -e --arg name "$name" '.agents[$name].model == "ember-path" and .agents[$name].effort == "swift"' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
  grep -F 'model: "ember-path"' "$TEST_TEMP_DIR/.claude/agents/$name.md" >/dev/null
  grep -F 'effort: "swift"' "$TEST_TEMP_DIR/.claude/agents/$name.md" >/dev/null
}

@test "generated agents omit default reasoning" {
  jq '.routing.profiles.balanced.roles.docs.reasoning = null' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  generate docs --job "write a README"
  [ "$status" -eq 0 ]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  ! grep -q '^effort:' "$TEST_TEMP_DIR/.claude/agents/$name.md"
  jq -e --arg name "$name" '.agents[$name].effort == null' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "generator blocks when the saved binary fingerprint is stale" {
  printf '%s\n' 'changed' >> "$ROUTE_BINARY"

  generate docs --job "write a README"

  [ "$status" -ne 0 ]
  [[ "$output" == *"fingerprint differs"* ]]
  [ ! -d "$TEST_TEMP_DIR/.claude/agents" ]
}

@test "generation uses saved routes when legacy model catalogs are absent" {
  local isolated="$TEST_TEMP_DIR/plugin"
  mkdir -p "$isolated"
  cp -R "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/templates" "$PROJECT_ROOT/config" "$isolated/"
  GENERATOR="$isolated/scripts/agent-generator.sh"
  export GENERATOR

  generate docs --job "write from saved routing authority"

  [ "$status" -eq 0 ]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  grep -F 'model: "nova-route"' "$TEST_TEMP_DIR/.claude/agents/$name.md" >/dev/null
  grep -F 'effort: "deliberate"' "$TEST_TEMP_DIR/.claude/agents/$name.md" >/dev/null
}

@test "task write allowance is registered as an exact repository path" {
  generate python-engineer --job "repair the failing hook" --write-allowance hooks/skill_gate.py
  [ "$status" -eq 0 ]
  local name
  local project_root
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-python-engineer-[a-z0-9-]*' | head -1)
  project_root=$(cd "$TEST_TEMP_DIR" && pwd -P)
  [ -n "$name" ]
  jq -e --arg name "$name" --arg root "$project_root" '
    .agents[$name].project_root == $root
    and .agents[$name].write_allowances == ["hooks/skill_gate.py"]
  ' "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "schema 3 generator uses the explicit temporary control root" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/team-one"
  mkdir -p "$control_root"
  local contract
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" team-scope \
    --command team --role web-engineer --team solo --job "write the web scope" \
    --control-root "$control_root" --write-capability directory:src/web)
  generate web-engineer --job "write the web scope" --task-id "$(basename "$contract" .json)" \
    --contract "$contract" --control-root "$control_root" --write-capability directory:src/web
  [ "$status" -eq 0 ]
  control_root=$(cd -P "$control_root" && pwd -P)
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-web-engineer-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  jq -e --arg name "$name" --arg root "$control_root" '
    .agents[$name].schema_version == 3
    and .agents[$name].control_root == $root
    and .agents[$name].capabilities == [{access:"write",kind:"directory",path:"src/web"}]
  ' "$control_root/agent-manifest.json" >/dev/null
  [ -f "$TEST_TEMP_DIR/.claude/agents/$name.md" ]
}

@test "schema 3 generator records runtime and communication policy" {
  local control_root="$TEST_TEMP_DIR/.temporary-agent-runfiles/runs/team-policy"
  mkdir -p "$control_root"
  local contract
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$TEST_TEMP_DIR" team-policy \
    --command team --role web-engineer --team solo --job "write the web scope" \
    --control-root "$control_root" --runtime-kind native-team \
    --communication-policy native-team --write-capability directory:src/web)
  generate web-engineer --job "write the web scope" --task-id "$(basename "$contract" .json)" \
    --contract "$contract" --control-root "$control_root" --write-capability directory:src/web
  [ "$status" -eq 0 ]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-web-engineer-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  jq -e --arg name "$name" '
    .agents[$name].runtime_kind == "native-team"
    and .agents[$name].communication_policy == "native-team"
  ' "$control_root/agent-manifest.json" >/dev/null
}

@test "--pair with a pairsWith role prints ENGINEER and CRITIC SPAWN_READY lines" {
  generate --pair python-engineer --job "build a parser"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENGINEER: SPAWN_READY lbwc-python-engineer-"* ]]
  [[ "$output" == *"CRITIC: SPAWN_READY lbwc-python-critic-"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'SPAWN_READY')" -eq 2 ]
}

@test "trio grants an exact test allowance only to test-dev" {
  generate --trio python-engineer --job "add parser coverage" \
    --write-allowance src/parser.py \
    --role-write-allowance test-dev:tests/parser.bats
  [ "$status" -eq 0 ]
  jq -e '
    [.agents[] | select(.role == "python-engineer") | .write_allowances] == [["src/parser.py"]]
    and [.agents[] | select(.role == "test-dev") | .write_allowances] == [["tests/parser.bats"]]
    and [.agents[] | select(.role == "python-critic") | .write_allowances] == [[]]
  ' "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "trio rejects a role-scoped allowance for a critic" {
  generate --trio python-engineer --job "add parser coverage" \
    --role-write-allowance python-critic:reviews/parser.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"only valid for test-dev"* ]]
}

@test "trio rejects a test-dev allowance outside the test directory" {
  generate --trio python-engineer --job "add parser coverage" \
    --role-write-allowance test-dev:src/parser.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"exact repository test path"* ]]
}

@test "generator rejects a pair that would exceed the live-agent capacity" {
  generate --trio python-engineer --job "hold the current build slot"
  [ "$status" -eq 0 ]
  [ "$(jq '[.agents[] | select(.state == "registered")] | length' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" -eq 3 ]

  generate --pair python-engineer --job "must wait for capacity"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent cap reached: 4"* ]]
  [ "$(jq '.agents | length' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" -eq 3 ]
}

@test "--exclusive rejects generation while a solo agent is registered" {
  generate docs --job "hold the exclusive slot"
  [ "$status" -eq 0 ]

  generate --pair python-engineer --exclusive --job "must wait for the solo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exclusive generation blocked: registered or running agent exists"* ]]
  [ "$(jq '.agents | length' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json")" -eq 1 ]
}

@test "--exclusive rejects generation while a solo agent is running" {
  generate docs --job "start before the exclusive pair"
  [ "$status" -eq 0 ]
  local manifest="$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json"
  local running_name
  running_name=$(jq -r '.agents | keys[0]' "$manifest")
  jq --arg name "$running_name" '.agents[$name].state = "running"' "$manifest" > "$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  generate --pair python-engineer --exclusive --job "must wait for the running solo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exclusive generation blocked: registered or running agent exists"* ]]
  [ "$(jq '.agents | length' "$manifest")" -eq 1 ]
  [ "$(find "$TEST_TEMP_DIR/.claude/agents" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "--exclusive admits generation after the solo agent becomes used" {
  generate docs --job "complete before the exclusive pair"
  [ "$status" -eq 0 ]
  local manifest="$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json"
  local used_name
  used_name=$(jq -r '.agents | keys[0]' "$manifest")
  jq --arg name "$used_name" '.agents[$name].state = "used"' "$manifest" > "$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  generate --pair python-engineer --exclusive --job "start after the solo"
  [ "$status" -eq 0 ]
  [ "$(jq '[.agents[] | select(.state == "used")] | length' "$manifest")" -eq 1 ]
  [ "$(jq '[.agents[] | select(.state == "registered")] | length' "$manifest")" -eq 2 ]
}

@test "--exclusive admits generation when existing agents are expired" {
  generate docs --job "expire before the exclusive pair"
  [ "$status" -eq 0 ]
  local manifest="$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json"
  local expired_name
  expired_name=$(jq -r '.agents | keys[0]' "$manifest")
  jq --arg name "$expired_name" '.agents[$name].state = "expired"' "$manifest" > "$manifest.tmp"
  mv "$manifest.tmp" "$manifest"

  generate --pair python-engineer --exclusive --job "start after expiration"
  [ "$status" -eq 0 ]
  [ "$(jq '[.agents[] | select(.state == "expired")] | length' "$manifest")" -eq 1 ]
  [ "$(jq '[.agents[] | select(.state == "registered")] | length' "$manifest")" -eq 2 ]
}

@test "--exclusive fails closed for malformed lifecycle states" {
  local transform
  for transform in \
    '.agents[.agents | keys[0]].state = null' \
    'del(.agents[.agents | keys[0]].state)' \
    '.agents[.agents | keys[0]].state = "paused"' \
    '.agents[.agents | keys[0]] = []' \
    '.agents[.agents | keys[0]] = 42'
  do
    generate docs --job "create an agent to corrupt"
    [ "$status" -eq 0 ]
    local manifest="$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json"
    jq "$transform" "$manifest" > "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"

    generate --pair python-engineer --exclusive --job "reject malformed state"
    [ "$status" -eq 1 ]
    [[ "$output" == *"exclusive generation blocked: invalid agent lifecycle state"* ]]
    [ "$(jq '.agents | length' "$manifest")" -eq 1 ]
    [ "$(find "$TEST_TEMP_DIR/.claude/agents" -type f | wc -l | tr -d ' ')" -eq 1 ]

    teardown_temp_dir
    setup
  done
}

@test "missing --job exits 1 naming the required flag" {
  generate docs
  [ "$status" -eq 1 ]
  [[ "$output" == *"--job is required"* ]]
}

@test "generated LBWC agent requires a contract before any mutation" {
  run bash -c 'cd "$TEST_TEMP_DIR" && exec bash "$GENERATOR" docs --job "write a README"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"--contract is required"* ]]
  [ ! -f "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" ]
  [ ! -d "$TEST_TEMP_DIR/.claude/agents" ]
}

@test "contract mode rejects a missing contract before rendering" {
  generate python-engineer --job "contract task" --task-id task-1 --contract missing.json --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract not found"* ]]
  [ ! -d "$TEST_TEMP_DIR/.claude/agents" ] || [ "$(find "$TEST_TEMP_DIR/.claude/agents" -type f | wc -l | tr -d ' ')" -eq 0 ]
}

@test "contract mode rejects a tampered digest" {
  local contract
  contract=$(make_contract python-engineer task-1 '["src/a.py"]')
  jq '.task_identity = "tampered"' "$contract" > "$contract.tmp" && mv "$contract.tmp" "$contract"
  generate python-engineer --job "contract task" --task-id "$(basename "$contract" .json)" --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract digest mismatch"* ]]
}

@test "contract mode rejects a task identity mismatch" {
  local contract
  contract=$(make_contract python-engineer task-1 '["src/a.py"]')
  generate python-engineer --job "contract task" --task-id task-2 --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"task identity mismatch"* ]]
}

@test "contract mode rejects an extra allowance" {
  local contract
  contract=$(make_contract python-engineer task-1 '["src/a.py"]')
  generate python-engineer --job "contract task" --task-id "$(basename "$contract" .json)" --contract "$contract" --write-allowance src/a.py --write-allowance src/b.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"write allowances do not match contract"* ]]
}

@test "contract mode requires explicit main provenance" {
  local contract
  contract=$(make_contract python-engineer task-1 '["src/a.py"]')
  jq '.created_by = "worker"' "$contract" > "$contract.tmp" && mv "$contract.tmp" "$contract"
  generate python-engineer --job "contract task" --task-id "$(basename "$contract" .json)" --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract digest mismatch"* || "$output" == *"planned main-session contract"* ]]
}

@test "pair contract rejects a role missing from roles array before rendering" {
  local contract
  contract=$(make_contract python-engineer task-1 '["src/a.py"]' pair "contract pair")
  jq '.roles = ["python-engineer"]' "$contract" > "$contract.tmp" && mv "$contract.tmp" "$contract"
  generate --pair python-engineer --job "contract pair" --task-id "$(basename "$contract" .json)" --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract"* ]]
  [ ! -d "$TEST_TEMP_DIR/.claude/agents" ] || [ "$(find "$TEST_TEMP_DIR/.claude/agents" -type f | wc -l | tr -d ' ')" -eq 0 ]
}

@test "generator accepts a real task-contract writer output" {
  cat > "$TEST_TEMP_DIR/PLAN.md" <<'EOF'
phase: 09
<tasks>
<task><name>wire-contract</name><action>implement</action><verify>tests</verify><done>green</done><strategy>small</strategy><role>python-engineer</role><files>src/a.py</files></task>
</tasks>
EOF
  local contract id
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" open "$TEST_TEMP_DIR/PLAN.md" "$TEST_TEMP_DIR" wire-contract --team solo --job "wire contract")
  id=$(basename "$contract" .json)
  generate python-engineer --job "wire contract" --task-id "$id" --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 0 ]
  jq -e --arg id "$id" '.agents[] | select(.contract_id == $id and .contract_enabled == true)' "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "generator rejects a real contract allowance subset before mutation" {
  cat > "$TEST_TEMP_DIR/PLAN.md" <<'EOF'
phase: 09
<tasks>
<task><name>wire-contract</name><action>implement</action><verify>tests</verify><done>green</done><strategy>small</strategy><role>python-engineer</role><files>src/a.py,src/b.py</files></task>
</tasks>
EOF
  local contract id
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" open "$TEST_TEMP_DIR/PLAN.md" "$TEST_TEMP_DIR" wire-contract --team solo --job "wire contract")
  id=$(basename "$contract" .json)
  generate python-engineer --job "wire contract" --task-id "$id" --contract "$contract" --write-allowance src/a.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"write allowances do not match contract"* ]]
  [ ! -f "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" ]
  [ ! -d "$TEST_TEMP_DIR/.claude/agents" ] || [ "$(find "$TEST_TEMP_DIR/.claude/agents" -type f | wc -l | tr -d ' ')" -eq 0 ]
}

@test "LBWC_AGENT_RANDOM_SEED is accepted and still generates a well-formed registered agent" {
  LBWC_AGENT_RANDOM_SEED=42 generate docs --job "write a README"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPAWN_READY lbwc-docs-"* ]]
  local name
  name=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$name" ]
  [[ "$name" =~ ^lbwc-docs-[a-z0-9]+-[a-z0-9]+-[a-z0-9]+$ ]]
  [ -f "$TEST_TEMP_DIR/.claude/agents/$name.md" ]
  jq -e --arg name "$name" '.agents | has($name)' \
    "$TEST_TEMP_DIR/.lbwc-planning/.agent-manifest.json" >/dev/null
}

@test "LBWC_AGENT_RANDOM_SEED yields a deterministic name across runs" {
  LBWC_AGENT_RANDOM_SEED=42 generate docs --job "first"
  [ "$status" -eq 0 ]
  local first
  first=$(printf '%s\n' "$output" | grep -o 'lbwc-docs-[a-z0-9-]*' | head -1)
  [ -n "$first" ]

  teardown_temp_dir
  setup

  LBWC_AGENT_RANDOM_SEED=42 generate docs --job "second"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SPAWN_READY $first"* ]]
}
