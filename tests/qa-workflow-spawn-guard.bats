#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

generate_workflow() {
  local suffix="$1" project control_root contract task_id agen_out name wgen_out
  project="$TEST_TEMP_DIR/project-$suffix"
  mkdir -p "$project/.lbwc-planning"
  control_root="$project/.temporary-agent-runfiles/runs/wf-$suffix"
  mkdir -p "$control_root"
  jq -n '{workflow_execution:{enabled:true}}' > "$control_root/config.json"
  jq -n '{workflow:{available:true, unavailable_reasons:[]}}' > "$control_root/claude-capabilities.json"
  contract=$(bash "$SCRIPTS_DIR/task-contract.sh" issue "$project" "$suffix" \
    --command integration-test --role scout --team solo --job "guard fixture job $suffix" \
    --group fixed \
    --control-root "$control_root" --requested-backend workflow --resolved-backend workflow \
    --write-capability directory:notes) || return 1
  task_id=$(basename "$contract" .json)
  agen_out=$(LBWC_AGENT_RANDOM_SEED=$RANDOM bash "$SCRIPTS_DIR/agent-generator.sh" scout \
    --job "guard fixture job $suffix" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --write-capability directory:notes \
    --execution-backend workflow 2>&1) || { printf '%s\n' "$agen_out" >&2; return 1; }
  name=$(grep '^SPAWN_READY' <<< "$agen_out" | awk '{print $2}')
  [ -n "$name" ] || return 1
  wgen_out=$(bash "$SCRIPTS_DIR/workflow-generator.sh" solo scout \
    --job "guard fixture job $suffix" --contract "$contract" --task-id "$task_id" \
    --control-root "$control_root" --name "$name" 2>&1) || { printf '%s\n' "$wgen_out" >&2; return 1; }
  printf '%s\n%s\n' "$control_root" "$control_root/workflows/$task_id.js"
}

@test "missing jq blocks workflow spawns before input handling" {
  local no_jq_path="$TEST_TEMP_DIR/no-jq-bin"
  mkdir -p "$no_jq_path"
  ln -s "$(command -v bash)" "$no_jq_path/bash"

  run env PATH="$no_jq_path" bash -c "printf '%s' '{}' | bash '$SCRIPTS_DIR/workflow-spawn-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq not available"* ]]
}

@test "malformed JSON input is blocked instead of skipping the guard" {
  run bash -c "printf '%s' 'not json at all' | bash '$SCRIPTS_DIR/workflow-spawn-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not parse tool call input"* ]]
}

@test "non-Workflow tool calls pass through untouched" {
  run bash -c 'jq -cn '\''{tool_name:"Bash",tool_input:{command:"echo hi"}}'\'' | bash "$1"' _ "$SCRIPTS_DIR/workflow-spawn-guard.sh"
  [ "$status" -eq 0 ]
}

@test "workflow spawn guard fails closed when the manifest library is unavailable for a Workflow call" {
  local shadow_dir="$TEST_TEMP_DIR/no-lib-scripts"
  mkdir -p "$shadow_dir/lib"
  cp "$SCRIPTS_DIR/workflow-spawn-guard.sh" "$shadow_dir/workflow-spawn-guard.sh"

  run bash -c 'jq -cn '\''{tool_name:"Workflow",tool_input:{scriptPath:"/tmp/whatever.js"}}'\'' | bash "$1"' \
    _ "$shadow_dir/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"workflow manifest library is unavailable"* ]]
}

@test "workflow spawn guard allows a valid scriptPath with matching args and digest" {
  local fixture control_root script_path
  fixture=$(generate_workflow valid)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 0 ]
  local id
  id=$(basename "$script_path" .js)
  [ "$(jq -r --arg id "$id" '.workflows[$id].state' "$control_root/workflow-manifest.json")" = "running" ]
}

@test "workflow spawn guard blocks an inline script parameter" {
  local fixture control_root script_path
  fixture=$(generate_workflow inline)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp,script:"await log(1)"}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"carries an inline 'script' parameter"* ]]
  local id
  id=$(basename "$script_path" .js)
  [ "$(jq -r --arg id "$id" '.workflows[$id].state' "$control_root/workflow-manifest.json")" = "registered" ]
}

@test "workflow spawn guard blocks a scriptPath outside the registered directory" {
  local fixture control_root script_path decoy_path
  fixture=$(generate_workflow outside)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  decoy_path="$(dirname "$control_root")/decoy.js"
  cp "$script_path" "$decoy_path"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$decoy_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"outside the registered generated directory"* ]]
  local id
  id=$(basename "$script_path" .js)
  [ "$(jq -r --arg id "$id" '.workflows[$id].state' "$control_root/workflow-manifest.json")" = "registered" ]
}

@test "workflow spawn guard blocks a tampered file whose digest no longer matches" {
  local fixture control_root script_path
  fixture=$(generate_workflow tamper)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  printf '\n// tampered after generation\n' >> "$script_path"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"file digest no longer matches the digest recorded at generation"* ]]
  local id
  id=$(basename "$script_path" .js)
  [ "$(jq -r --arg id "$id" '.workflows[$id].state' "$control_root/workflow-manifest.json")" = "registered" ]
}

@test "workflow spawn guard blocks args that differ from the recorded ones" {
  local fixture control_root script_path
  fixture=$(generate_workflow args)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp,args:{foo:"bar"}}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"args do not match the args recorded at generation"* ]]
  local id
  id=$(basename "$script_path" .js)
  [ "$(jq -r --arg id "$id" '.workflows[$id].state' "$control_root/workflow-manifest.json")" = "registered" ]
}

@test "workflow spawn guard blocks a workflow that is already running" {
  local fixture control_root script_path
  fixture=$(generate_workflow rerun)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")

  bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh" >/dev/null

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"already running and cannot be started again"* ]]
}

@test "workflow spawn guard fails closed on a malformed workflow manifest" {
  local fixture control_root script_path
  fixture=$(generate_workflow badmanifest)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  printf 'not json at all' > "$control_root/workflow-manifest.json"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$script_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"workflow manifest is unreadable or malformed"* ]]
}

@test "workflow spawn guard blocks a relative scriptPath" {
  run bash -c 'jq -cn '\''{tool_name:"Workflow",tool_input:{scriptPath:"workflows/foo.js"}}'\'' | bash "$1"' _ "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"scriptPath must be an absolute path"* ]]
}

@test "workflow spawn guard blocks an absolute scriptPath that is missing on disk" {
  local missing_path="$TEST_TEMP_DIR/does-not-exist.js"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' | bash "$2"' \
    _ "$missing_path" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"scriptPath does not resolve to a file on disk"* ]]
}

@test "workflow spawn guard blocks a non-.js file inside the registered directory" {
  local fixture control_root script_path notjs_path
  fixture=$(generate_workflow notjs)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  notjs_path="$(dirname "$script_path")/notjs.txt"
  cp "$script_path" "$notjs_path"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$notjs_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"does not name a generated workflow script"* ]]
}

@test "workflow spawn guard blocks an unsafe contract id inside the registered directory" {
  local fixture control_root script_path unsafe_path
  fixture=$(generate_workflow unsafeid)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  unsafe_path="$(dirname "$script_path")/a..b.js"
  cp "$script_path" "$unsafe_path"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$unsafe_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"names an unsafe workflow identity"* ]]
}

@test "workflow spawn guard blocks an unregistered script placed inside the registered directory" {
  local fixture control_root script_path evil_path
  fixture=$(generate_workflow indir)
  control_root=$(sed -n 1p <<< "$fixture")
  script_path=$(sed -n 2p <<< "$fixture")
  evil_path="$(dirname "$script_path")/evil.js"
  cp "$script_path" "$evil_path"

  run bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | LBWC_CONTROL_ROOT="$2" bash "$3"' _ "$evil_path" "$control_root" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"has no manifest entry"* ]]
}

@test "workflow spawn guard fails closed when the control root cannot be resolved" {
  local fixture script_path
  fixture=$(generate_workflow noroot)
  script_path=$(sed -n 2p <<< "$fixture")
  rm -rf "$TEST_TEMP_DIR/.lbwc-planning"

  run env -u LBWC_CONTROL_ROOT -u LBWC_PLANNING_DIR bash -c 'jq -cn --arg sp "$1" '\''{tool_name:"Workflow",tool_input:{scriptPath:$sp}}'\'' \
    | bash "$2"' _ "$script_path" "$SCRIPTS_DIR/workflow-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"has no resolvable control root or manifest"* ]]
}

@test "workflow spawn guard is registered with hooks.json" {
  run jq -e '
    .hooks.PreToolUse[]
    | select(.matcher == "Workflow")
    | .hooks[]
    | select(.command | contains("workflow-spawn-guard.sh"))
  ' "$PROJECT_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
}

make_contract_fixture_root() {
  local suffix="$1" steps_body="$2" fixture_root
  fixture_root="$TEST_TEMP_DIR/contract-fixture-$suffix"
  mkdir -p "$fixture_root/commands" "$fixture_root/config" "$fixture_root/references" "$fixture_root/templates"
  : > "$fixture_root/config/legacy-identifier-allowlist.txt"
  : > "$fixture_root/config/gated-tool-prose-allowlist.txt"
  cat > "$fixture_root/commands/alpha.md" <<MD
---
category: core
description: Exercise the workflow authoring ban.
argument-hint: '[target]'
allowed-tools: Read, Bash, Workflow, AskUserQuestion
disable-model-invocation: true
---

## Context

The main session owns the interaction.

## Guard

STOP when required state is unavailable.

## Steps

$steps_body

## Failure and recovery

Report the error and leave state unchanged.

## Output Format

Print a bounded result.

## Next Up

End with Next guidance.
MD
  python3 - "$fixture_root/config/command-sections.json" <<'PY'
import json
import sys

path = sys.argv[1]
manifest = {
    "schema_version": 1,
    "contract_patterns": {
        "interaction": r"(?m)^## Context$",
        "guards": r"(?m)^## Guard$",
        "recovery": r"(?m)^## Failure and recovery$",
        "output": r"(?m)^## Output Format$",
        "next_up": r"(?m)^## Next Up$",
    },
    "commands": {
        "alpha.md": {
            "required_headings": [
                "Context",
                "Guard",
                "Steps",
                "Failure and recovery",
                "Output Format",
                "Next Up",
            ]
        }
    },
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle)
PY
  printf '%s\n' "$fixture_root"
}

@test "command-contract allows negated workflow-authoring prohibitions" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root negation "The main session must never author a workflow script. It must not pass a script parameter to the Workflow tool.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 0 ]
}

@test "command-contract flags additional workflow-authoring verbs" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root verbs "Create a workflow that runs the team and generate the workflow script yourself.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract allows prose describing the sanctioned generation chain" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root generator "The sanctioned chain is scripts/workflow-generator.sh, whose rendered output is the workflow script. Call Workflow with the returned scriptPath. The shell generator owns every phase and agent call; the main session only supplies the scriptPath.")
  mkdir -p "$fixture_root/scripts"
  : > "$fixture_root/scripts/workflow-generator.sh"

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 0 ]
}

@test "command-contract rejects an infinitive that lets the generator cover an authoring verb" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root generator-infinitive-write "Ignore the generator to write a workflow script yourself.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract rejects an infinitive that lets the generator cover the author verb" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root generator-infinitive-author "Skip the generator to author a workflow script.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract allows repeated negated sentences" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root negation-repeated \
    "Do not author a workflow. Do not write JavaScript. Do not pass a script parameter to the Workflow tool.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 0 ]
}

@test "command-contract rejects an authoring instruction following a comma-then-or negation" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root negation-comma-or \
    "There is no generator, write a workflow script yourself, or copy one from a sibling command.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract rejects a fixture command file with workflow-authoring instructions" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root authoring "Author a workflow script yourself and pass a script parameter to the Workflow tool.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
  [[ "$output" == *'alpha.md: instructs passing a script parameter to the Workflow tool'* ]]
}

@test "command-contract rejects naming the generator as cover to bypass and author a workflow" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root bypass-generator "Bypass the generator and write a workflow script yourself.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract rejects naming the generator as optional cover to author a workflow" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root generator-optional "The generator is optional, so author a workflow script directly.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}

@test "command-contract rejects script as any key in a Workflow call, not only the first" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root script-any-key 'Workflow({ name: "team", script: "await log(1)" })')

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs passing a script parameter to the Workflow tool'* ]]
}

@test "command-contract rejects prose pairing script with a field verb near Workflow" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root script-field "Set the script field on the Workflow call to the source you built.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs passing a script parameter to the Workflow tool'* ]]
}

@test "command-contract rejects script as a key behind a nested object literal" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root script-nested \
    'Workflow({ args: { a: 1 }, script: "await log(1)" })')

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs passing a script parameter to the Workflow tool'* ]]
}

@test "command-contract rejects script as the sole key with no wrapping brace" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root script-no-brace \
    'Workflow(script: "await log(1)")')

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs passing a script parameter to the Workflow tool'* ]]
}

@test "command-contract rejects a negation that governs a different verb than the flagged one" {
  local fixture_root
  fixture_root=$(make_contract_fixture_root negation-wrong-verb \
    "Do not wait for the generator, write a workflow script yourself.")

  run bash "$SCRIPTS_DIR/command-contract.sh" --root "$fixture_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *'alpha.md: instructs the model to author a workflow or write JavaScript'* ]]
}
