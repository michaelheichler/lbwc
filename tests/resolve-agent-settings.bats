#!/usr/bin/env bats

load test_helper

RESOLVER="${SCRIPTS_DIR}/resolve-agent-settings.sh"

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
}

resolve() {
  run bash "$RESOLVER" "$@"
}

@test "profile value resolves with no project override" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='claude-fable-5'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT='medium'"* ]]
}

@test "project roles override wins over the profile" {
  echo '{"roles":{"lead":{"model":"terra","effort":"high"}}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='gpt-5.6-terra'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT='high'"* ]]
}

@test "a CLI flag wins over a project roles override" {
  echo '{"roles":{"lead":{"model":"terra","effort":"high"}}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model sonnet --reasoning low
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='claude-sonnet-5'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT='low'"* ]]
}

@test "the sol alias canonicalizes to gpt-5.6-sol" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model sol
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='gpt-5.6-sol'"* ]]
}

@test "an unknown model exits 3" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model not-a-real-model
  [ "$status" -eq 3 ]
  [[ "$output" == *"unknown model"* ]]
}

@test "a retired project config key is rejected with its replacement named" {
  echo '{"model_overrides":{"lead":"opus"}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"model_overrides"* ]]
  [[ "$output" == *"roles.<role>.model"* ]]
}

@test "the inherit model passes through without pricing validation" {
  resolve qa-author "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='inherit'"* ]]
}

@test "reasoning effort clamps to the model's ladder" {
  resolve docs "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model haiku
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='claude-haiku-4-5'"* ]]
  [[ "$output" == *"RESOLVED_EFFORT=''"* ]]
}

@test "docs is a valid role and resolves" {
  resolve docs "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='claude-sonnet-5'"* ]]
}

@test "qa-author is a valid role and resolves" {
  resolve qa-author "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='inherit'"* ]]
}

@test "docs renders through render-agent-template.sh" {
  run bash "${SCRIPTS_DIR}/render-agent-template.sh" docs \
    NAME=lbwc-docs-test JOB="write a README" MODEL=claude-sonnet-5 EFFORT=medium
  [ "$status" -eq 0 ]
  [[ "$output" == *"lbwc-docs-test"* ]]
}

@test "qa-author renders through render-agent-template.sh" {
  run bash "${SCRIPTS_DIR}/render-agent-template.sh" qa-author \
    NAME=lbwc-qa-author-test JOB="write failing tests" MODEL=inherit EFFORT=medium
  [ "$status" -eq 0 ]
  [[ "$output" == *"lbwc-qa-author-test"* ]]
}

# --- max_turns resolution characterization (default effort = balanced, multiplier 1/1) ---

@test "max_turns: defaults.json value wins for python-engineer" {
  resolve python-engineer "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='50'"* ]]
}

@test "max_turns: architect falls back to the hardcoded table" {
  resolve architect "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='50'"* ]]
}

@test "max_turns: debugger falls back to the hardcoded table" {
  resolve debugger "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='40'"* ]]
}

@test "max_turns: qa falls back to the hardcoded table" {
  resolve qa "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='20'"* ]]
}

@test "max_turns: scout falls back to the hardcoded table" {
  resolve scout "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='30'"* ]]
}

@test "max_turns: docs falls back to the hardcoded table" {
  resolve docs "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='30'"* ]]
}

@test "max_turns: qa-author falls back to the hardcoded table" {
  resolve qa-author "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='30'"* ]]
}

@test "max_turns: deviq resolves from defaults.json, not the catch-all" {
  resolve deviq "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='15'"* ]]
}

@test "max_turns: CLI --max-turns wins outright regardless of role" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --max-turns 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='7'"* ]]
}

@test "max_turns: CLI --max-turns 0 normalizes to empty" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --max-turns 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS=''"* ]]
}

@test "max_turns: CLI --max-turns with a negative value normalizes to empty" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --max-turns -3
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS=''"* ]]
}

@test "max_turns: project roles override beats the defaults.json value" {
  echo '{"roles":{"python-engineer":{"max_turns":99}}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve python-engineer "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='99'"* ]]
}

@test "max_turns: every role resolves to its pinned base-turns value at balanced effort" {
  local expected=(
    "lead=50"
    "lead-critic=20"
    "coding-dijkstra=50"
    "coding-dijkstra-critic=20"
    "python-engineer=50"
    "python-critic=20"
    "web-engineer=50"
    "web-code-critic=20"
    "test-dev=40"
    "architect=50"
    "debugger=40"
    "qa=20"
    "scout=30"
    "ux-oracle=20"
    "docs=30"
    "qa-author=30"
    "deviq=15"
  )
  local entry role want
  for entry in "${expected[@]}"; do
    role="${entry%%=*}"
    want="${entry##*=}"
    resolve "$role" "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESOLVED_MAX_TURNS='${want}'"* ]] || {
      echo "role $role: expected RESOLVED_MAX_TURNS='$want', got:" >&2
      echo "$output" >&2
      return 1
    }
  done
}

@test "max_turns: CLI --max-turns 99 wins over everything" {
  echo '{"roles":{"lead":{"max_turns":33}}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --max-turns 99
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='99'"* ]]
}

@test "max_turns: project roles override for lead-critic wins over defaults.json" {
  echo '{"roles":{"lead-critic":{"max_turns":33}}}' > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  resolve lead-critic "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='33'"* ]]
}
