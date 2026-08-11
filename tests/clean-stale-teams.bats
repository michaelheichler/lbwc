#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  export LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning"
  export LBWC_STALE_TEAM_SECONDS=7200
  mkdir -p "$CLAUDE_CONFIG_DIR/teams" "$CLAUDE_CONFIG_DIR/tasks" "$LBWC_PLANNING_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "clean-stale-teams removes a configless LBWC team and its tasks" {
  mkdir -p "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01" "$CLAUDE_CONFIG_DIR/tasks/lbwc-plan-01"

  run bash "$SCRIPTS_DIR/clean-stale-teams.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/tasks/lbwc-plan-01" ]
  [[ "$output" == *"teams_cleaned=1"* ]]
}

@test "clean-stale-teams preserves non-LBWC directories" {
  mkdir -p "$CLAUDE_CONFIG_DIR/teams/other-team"

  run bash "$SCRIPTS_DIR/clean-stale-teams.sh"

  [ "$status" -eq 0 ]
  [ -d "$CLAUDE_CONFIG_DIR/teams/other-team" ]
}

@test "clean-stale-teams preserves a recent configured team" {
  mkdir -p "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/inboxes"
  printf '{}\n' > "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/config.json"
  printf 'recent\n' > "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/inboxes/member"

  run bash "$SCRIPTS_DIR/clean-stale-teams.sh"

  [ "$status" -eq 0 ]
  [ -d "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01" ]
  [[ "$output" == *"teams_cleaned=0"* ]]
}

@test "clean-stale-teams removes a configured team after the stale threshold" {
  mkdir -p "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/inboxes" "$CLAUDE_CONFIG_DIR/tasks/lbwc-plan-01"
  printf '{}\n' > "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/config.json"
  printf 'old\n' > "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/inboxes/member"
  touch -t 200001010000 "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01/inboxes/member"

  run bash "$SCRIPTS_DIR/clean-stale-teams.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_CONFIG_DIR/teams/lbwc-plan-01" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/tasks/lbwc-plan-01" ]
  [[ "$output" == *"teams_cleaned=1"* ]]
}
