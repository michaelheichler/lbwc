#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/lbwc-config.sh"
  test_root=$(mktemp -d)
  TEST_ROOT="$(cd "$test_root" && pwd -P)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_config() {
  run bash "$SCRIPT" "$@"
}

make_planning_swap_mv() {
  local shim_dir="$TEST_ROOT/shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/mv" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 3 ] && [ "$1" = "-f" ] || exit 64
source_path="$2"
destination_path="$3"
/bin/mv "$SWAP_PLANNING_DIR" "$SWAP_OPENED_DIR"
ln -s "$SWAP_EXTERNAL_DIR" "$SWAP_PLANNING_DIR"
if [[ "$source_path" = /* ]]; then
  source_path="$SWAP_OPENED_DIR/${source_path##*/}"
fi
exec /bin/mv -f "$source_path" "$destination_path"
SHIM
  chmod +x "$shim_dir/mv"
  printf '%s\n' "$shim_dir"
}

@test "init creates a versioned configuration with empty routing profiles" {
  run_config init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PLANNING_DIR/config.json" ]
  run jq -e '
    .schema_version == 1
    and .effort == "balanced"
    and .routing.active_profile == "balanced"
    and .routing.profiles.quality.roles == {}
    and .routing.profiles.balanced.roles == {}
    and .routing.profiles.turbo.roles == {}
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "the platform bash executes the shared configuration transaction" {
  [ -x /bin/bash ] || skip '/bin/bash is unavailable'

  run /bin/bash "$SCRIPT" init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PLANNING_DIR/config.json" ]
  [ ! -e "$PLANNING_DIR/.routing.lock" ]
}

@test "init persists VBW parity preference defaults without model data" {
  run_config init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .skill_suggestions == true
    and .auto_install_skills == false
    and .discovery_questions == true
    and .discussion_mode == "questions"
    and .visual_format == "unicode"
    and .pipeline_research == false
    and .branch_per_milestone == false
    and .plain_summary == true
    and .active_profile == "default"
    and .custom_profiles == {}
    and .agent_max_turns == {}
    and .qa_skip_agents == []
    and .token_budgets == true
    and .two_phase_completion == true
    and .smart_routing == true
    and .validation_gates == true
    and .snapshot_resume == true
    and .lease_locks == true
    and .event_recovery == true
    and .worktree_isolation == "off"
    and .monorepo_routing == true
    and .debug_logging == false
    and .statusline_hide_limits == false
    and .statusline_hide_limits_for_api_key == false
    and .statusline_hide_agent_in_tmux == false
    and .statusline_collapse_agent_in_tmux == false
    and (has("model_profile") | not)
    and (has("model_overrides") | not)
    and (has("model_matrix") | not)
    and (has("model_catalog") | not)
    and (has("reasoning_matrix") | not)
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "set persists each accepted parity preference domain" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  while IFS=$'\t' read -r setting literal; do
    run_config set "$PLANNING_DIR" "$setting" "$literal"
    if [ "$status" -ne 0 ]; then
      printf '%s\n' "$setting=$literal: $output" >&3
      return 1
    fi
  done <<'VALUES'
skill_suggestions	false
auto_install_skills	true
discovery_questions	false
discussion_mode	"assumptions"
visual_format	"ascii"
pipeline_research	true
branch_per_milestone	true
plain_summary	false
custom_profiles	{"release":{"effort":"thorough","autonomy":"cautious","verification_tier":"deep"}}
active_profile	"release"
agent_max_turns	{"lead":{"thorough":120,"turbo":false},"qa":0}
qa_skip_agents	["docs","qa-author"]
token_budgets	false
two_phase_completion	false
smart_routing	false
validation_gates	false
snapshot_resume	false
lease_locks	false
event_recovery	false
worktree_isolation	"on"
monorepo_routing	false
debug_logging	true
statusline_hide_limits	true
statusline_hide_limits_for_api_key	true
statusline_hide_agent_in_tmux	true
statusline_collapse_agent_in_tmux	true
VALUES
}

@test "set rejects invalid parity preferences without changing saved configuration" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  while IFS=$'\t' read -r setting literal; do
    before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    run_config set "$PLANNING_DIR" "$setting" "$literal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid configuration"* ]]
    after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
  done <<'VALUES'
discussion_mode	"freeform"
visual_format	"ansi"
active_profile	"release profile"
active_profile	"unknown"
custom_profiles	{"default":{"effort":"balanced","autonomy":"standard","verification_tier":"standard"}}
agent_max_turns	{"unknown":1}
qa_skip_agents	["docs","docs"]
worktree_isolation	"maybe"
VALUES
}

@test "init preserves legacy role settings and maps budget to turbo" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"model_profile":"budget","roles":{"lead":{"model":"legacy-selector"}},"metrics":true,"skill_suggestions":false,"custom_profiles":{"release":{"effort":"thorough","autonomy":"cautious","verification_tier":"deep"}},"active_profile":"release"}' > "$PLANNING_DIR/config.json"

  run_config init "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .model_profile == "budget"
    and .roles.lead.model == "legacy-selector"
    and .metrics == true
    and .skill_suggestions == false
    and .active_profile == "release"
    and .custom_profiles.release.verification_tier == "deep"
    and .token_budgets == true
    and .statusline_hide_limits == false
    and .routing.active_profile == "turbo"
    and .routing.profiles.quality.roles == {}
  ' "$PLANNING_DIR/config.json"
  [ "$status" -eq 0 ]
}

@test "set updates a validated setting and get returns its JSON value" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  run_config set "$PLANNING_DIR" effort '"turbo"'
  [ "$status" -eq 0 ]

  run_config get "$PLANNING_DIR" effort
  [ "$status" -eq 0 ]
  [ "$output" = '"turbo"' ]
}

@test "get returns a stored false value" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  run_config set "$PLANNING_DIR" auto_commit false
  [ "$status" -eq 0 ]

  run_config get "$PLANNING_DIR" auto_commit
  [ "$status" -eq 0 ]
  [ "$output" = 'false' ]
}

@test "set rejects an invalid setting without changing the saved configuration" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config set "$PLANNING_DIR" effort '"invalid"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid configuration"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "init rejects a symlinked planning directory without writing its target" {
  external_dir="$TEST_ROOT/external"
  mkdir -p "$external_dir"
  ln -s "$external_dir" "$PLANNING_DIR"

  run_config init "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ ! -e "$external_dir/config.json" ]
}

@test "init accepts the macOS var temporary directory alias" {
  local logical_planning
  [[ "$TEST_ROOT" == /private/var/* ]] || skip 'temporary directory is not under /private/var'
  logical_planning="/var/${TEST_ROOT#/private/var/}/.lbwc-planning"

  run_config init "$logical_planning"

  [ "$status" -eq 0 ]
  [ -f "$PLANNING_DIR/config.json" ]
}

@test "init rejects a symlinked intermediate directory without creating external state" {
  external_dir="$TEST_ROOT/external"
  linked_parent="$TEST_ROOT/linked-parent"
  mkdir -p "$external_dir"
  ln -s "$external_dir" "$linked_parent"
  nested_planning="$linked_parent/project/.lbwc-planning"

  run_config init "$nested_planning"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ ! -e "$external_dir/project" ]
}

@test "init rejects a symlinked config path without creating its external target" {
  external_dir="$TEST_ROOT/external"
  mkdir -p "$PLANNING_DIR" "$external_dir"
  ln -s "$external_dir/config.json" "$PLANNING_DIR/config.json"

  run_config init "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ ! -e "$external_dir/config.json" ]
}

@test "init rejects a symlinked lock path without writing configuration" {
  external_dir="$TEST_ROOT/external"
  mkdir -p "$PLANNING_DIR" "$external_dir"
  ln -s "$external_dir" "$PLANNING_DIR/.config.lock"

  run_config init "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ ! -e "$PLANNING_DIR/config.json" ]
}

@test "set keeps the verified planning directory identity during final rename" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  external_dir="$TEST_ROOT/external"
  opened_dir="$TEST_ROOT/opened-planning"
  mkdir -p "$external_dir"
  printf '%s\n' 'external sentinel' > "$external_dir/config.json"
  external_before=$(shasum -a 256 "$external_dir/config.json" | awk '{print $1}')
  shim_dir=$(make_planning_swap_mv)

  run env \
    PATH="$shim_dir:$PATH" \
    SWAP_PLANNING_DIR="$PLANNING_DIR" \
    SWAP_OPENED_DIR="$opened_dir" \
    SWAP_EXTERNAL_DIR="$external_dir" \
    bash "$SCRIPT" set "$PLANNING_DIR" effort '"turbo"'
  command_status="$status"

  external_after=$(shasum -a 256 "$external_dir/config.json" | awk '{print $1}')
  [ "$external_before" = "$external_after" ]
  [ -L "$PLANNING_DIR" ]
  [ -f "$opened_dir/config.json" ]
  if [ "$command_status" -eq 0 ]; then
    run jq -e '.effort == "turbo"' "$opened_dir/config.json"
  else
    run jq -e '.effort == "balanced"' "$opened_dir/config.json"
  fi
  [ "$status" -eq 0 ]
}

@test "set accepts every supported non-dynamic setting domain" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  while IFS=$'\t' read -r setting literal; do
    run_config set "$PLANNING_DIR" "$setting" "$literal"
    if [ "$status" -ne 0 ]; then
      printf '%s\n' "$setting=$literal: $output" >&3
      return 1
    fi
  done <<'VALUES'
effort	"thorough"
effort	"balanced"
effort	"fast"
effort	"turbo"
autonomy	"cautious"
autonomy	"standard"
autonomy	"confident"
autonomy	"pure-vibe"
auto_commit	false
auto_commit	true
planning_tracking	"manual"
planning_tracking	"ignore"
planning_tracking	"commit"
auto_push	"never"
auto_push	"after_phase"
auto_push	"always"
verification_tier	"quick"
verification_tier	"standard"
verification_tier	"deep"
context_compiler	false
context_compiler	true
max_tasks_per_plan	1
prefer_teams	"always"
prefer_teams	"auto"
prefer_teams	"never"
auto_uat	true
auto_uat	false
require_phase_discussion	true
require_phase_discussion	false
rolling_summary	true
rolling_summary	false
metrics	true
metrics	false
caveman_style	"none"
caveman_style	"lite"
caveman_style	"full"
caveman_style	"ultra"
caveman_style	"auto"
caveman_commit	true
caveman_commit	false
caveman_review	true
caveman_review	false
max_uat_remediation_rounds	1
max_uat_remediation_rounds	false
routing.active_profile	"quality"
routing.active_profile	"balanced"
routing.active_profile	"turbo"
VALUES
}

@test "set rejects invalid values for every writable non-dynamic setting" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  while IFS=$'\t' read -r setting literal; do
    before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    run_config set "$PLANNING_DIR" "$setting" "$literal"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid configuration"* ]]
    after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
  done <<'VALUES'
effort	"slow"
autonomy	"unbounded"
auto_commit	"true"
planning_tracking	"automatic"
auto_push	"sometimes"
verification_tier	"none"
context_compiler	"true"
max_tasks_per_plan	0
prefer_teams	"sometimes"
auto_uat	"false"
require_phase_discussion	"false"
rolling_summary	"false"
metrics	"false"
caveman_style	"extreme"
caveman_commit	"false"
caveman_review	"false"
max_uat_remediation_rounds	"many"
routing.active_profile	"budget"
VALUES
}

@test "validate rejects a configuration that lacks a required routing profile" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"schema_version":1,"effort":"balanced","routing":{"active_profile":"balanced","profiles":{"quality":{"roles":{}},"balanced":{"roles":{}}}}}' > "$PLANNING_DIR/config.json"

  run_config validate "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid configuration"* ]]
}

@test "init rejects an unknown root key without overwriting the configuration" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"unknown_setting":true}' > "$PLANNING_DIR/config.json"
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config init "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid configuration"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "validate rejects an unexpected routing profile without overwriting the configuration" {
  run_config init "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  jq '.routing.profiles.shadow = {roles:{}}' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.json.tmp"
  mv "$PLANNING_DIR/config.json.tmp" "$PLANNING_DIR/config.json"
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config validate "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid configuration"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "init rejects an unsupported configuration version without overwriting it" {
  mkdir -p "$PLANNING_DIR"
  printf '%s\n' '{"schema_version":99,"effort":"balanced"}' > "$PLANNING_DIR/config.json"
  before=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')

  run_config init "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported configuration version"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}
