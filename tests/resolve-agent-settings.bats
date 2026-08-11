#!/usr/bin/env bats

load test_helper

RESOLVER="${SCRIPTS_DIR}/resolve-agent-settings.sh"

setup() {
  TEST_TEMP_DIR=$(mktemp -d /private/tmp/lbwc-resolver.XXXXXX)
  export TEST_TEMP_DIR
  export _ORIG_HOME="${HOME:-}"
  export _ORIG_LBWC_PLANNING_DIR="${LBWC_PLANNING_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  unset LBWC_PLANNING_DIR CLAUDE_SESSION_ID 2>/dev/null || true
  mkdir -p "$TEST_TEMP_DIR/.lbwc-planning"
  ROUTE_BINARY="$TEST_TEMP_DIR/claude-resolver-fixture"
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
        accepted_values: ["deliberate", "swift", "default"],
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
}

teardown() {
  teardown_temp_dir
}

resolve() {
  run bash "$RESOLVER" "$@"
}

update_config() {
  local filter="$1" path="$TEST_TEMP_DIR/.lbwc-planning/config.json"
  jq "$filter" "$path" > "$path.next"
  mv "$path.next" "$path"
}

@test "profile value resolves with no project override" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_AGENT_MODEL='nova-route'"* ]]
  [[ "$output" == *"RESOLVED_MODEL='nova-route'"* ]]
  [[ "$output" == *"RESOLVED_REASONING='deliberate'"* ]]
}

@test "active profile selects its exact saved route" {
  update_config '.routing.active_profile = "quality" | .routing.profiles.quality.roles.lead = {model: "ember-path", reasoning: "swift", status: "resolved"}'
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_AGENT_MODEL='ember-path'"* ]]
  [[ "$output" == *"RESOLVED_REASONING='swift'"* ]]
}

@test "CLI route values remain exact after catalog validation" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model ember-path --reasoning swift
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_AGENT_MODEL='ember-path'"* ]]
  [[ "$output" == *"RESOLVED_MODEL='ember-path'"* ]]
  [[ "$output" == *"RESOLVED_REASONING='swift'"* ]]
}

@test "an unknown model exits 3" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model missing-route
  [ "$status" -eq 3 ]
  [[ "$output" == *"saved capability catalog"* ]]
}

@test "an absent active route fails closed" {
  update_config 'del(.routing.profiles.balanced.roles.lead)'
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"route is unresolved or absent"* ]]
}

@test "null reasoning emits an empty renderer effort" {
  update_config '.routing.profiles.balanced.roles.docs.reasoning = null'
  resolve docs "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_REASONING=''"* ]]
  [[ "$output" == *"RESOLVED_EFFORT=''"* ]]
}

@test "global reasoning ignores model associations" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model nova-route --reasoning swift
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_REASONING='swift'"* ]]
}

@test "detected reasoning named default remains an exact string" {
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --model nova-route --reasoning default
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_REASONING='default'"* ]]
  [[ "$output" == *"RESOLVED_REASONING_JSON='\"default\"'"* ]]
}

@test "docs renders through render-agent-template.sh" {
  run bash "${SCRIPTS_DIR}/render-agent-template.sh" docs \
    NAME=lbwc-docs-test JOB="write a README" MODEL=nova-route EFFORT=deliberate
  [ "$status" -eq 0 ]
  [[ "$output" == *"lbwc-docs-test"* ]]
}

@test "qa-author renders through render-agent-template.sh" {
  run bash "${SCRIPTS_DIR}/render-agent-template.sh" qa-author \
    NAME=lbwc-qa-author-test JOB="write failing tests" MODEL=ember-path EFFORT=swift
  [ "$status" -eq 0 ]
  [[ "$output" == *"lbwc-qa-author-test"* ]]
}

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
  update_config '.roles."python-engineer".max_turns = 99'
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
  update_config '.roles.lead.max_turns = 33'
  resolve lead "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT" --max-turns 99
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='99'"* ]]
}

@test "max_turns: project roles override for lead-critic wins over defaults.json" {
  update_config '.roles."lead-critic".max_turns = 33'
  resolve lead-critic "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MAX_TURNS='33'"* ]]
}
