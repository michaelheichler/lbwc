#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$REPO_ROOT/scripts/lbwc-config.sh"
  TEST_ROOT="$(mktemp -d)"
  SETTINGS="$TEST_ROOT/settings.json"
  printf '%s\n' '{}' > "$SETTINGS"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "agent teams status reports disabled without changing settings" {
  run env CLAUDE_CONFIG_DIR="$TEST_ROOT/claude" \
    bash "$SCRIPT" agent-teams-status --settings "$SETTINGS"

  [ "$status" -eq 0 ]
  jq -e '.enabled == false and .source == "none"' <<< "$output" >/dev/null
  [ "$(jq -c . "$SETTINGS")" = "{}" ]
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
}

@test "team command is registered in the command section contract" {
  jq -e '.commands["team.md"].required_headings == ["Context","Guard","Steps","Failure and recovery","Output Format","Next Up"]' \
    "$REPO_ROOT/config/command-sections.json" >/dev/null
}
