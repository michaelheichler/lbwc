#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SCRIPT="$REPO_ROOT/scripts/claude-capabilities.sh"
  ROUTING="$REPO_ROOT/scripts/lbwc-routing.sh"
  test_root="$(mktemp -d)"
  TEST_ROOT="$(cd "$test_root" && pwd -P)"
  PLANNING_DIR="$TEST_ROOT/project/.lbwc-planning"
  INVOCATION_MARKER="$TEST_ROOT/model-invoked"
  mkdir -p "$PLANNING_DIR"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_claude_fixture() {
  local binary="$1" version="$2" efforts="$3" models_json="$4" associations="$5" unrelated_table="${6:-}" inspection_marker="${7:-}" host_enum="${8:-}"
  mkdir -p "$(dirname "$binary")"
  cat > "$binary" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -n '$inspection_marker' ]; then
  printf '%s\n' used > '$inspection_marker'
fi
case "\${1:-}" in
  --version)
    printf '%s\n' '$version'
    ;;
  --help)
    printf '%s\n' '  --effort <level>  Session reasoning' '                      ($efforts)'
    ;;
  *)
    printf '%s\n' invoked > "$INVOCATION_MARKER"
    exit 97
    ;;
esac
exit 0
: 'models:$models_json'
: '$unrelated_table'
: '$associations'
: '$host_enum'
EOF
  chmod +x "$binary"
}

@test "catalog keeps a host enum that starts with a custom id" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-amber-route",family:"amber",display_name:"Amber Route"},{id:"claude-violet-route",family:"violet",display_name:"Violet Route"}]' \
    '' \
    '' \
    '' \
    '["leverframe:openai-oauth:codex-auto-review","amber","violet"]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .host_agent_enum == ["leverframe:openai-oauth:codex-auto-review","amber","violet"]
    and .agent_model_ids["claude-amber-route"] == "amber"
    and .agent_model_ids["leverframe:openai-oauth:codex-auto-review"] == "leverframe:openai-oauth:codex-auto-review"
    and ([.models[].selector] | index("leverframe:openai-oauth:codex-auto-review")) != null
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "catalog stores extracted host aliases and custom ids from the fixture enum" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-amber-route",family:"amber",display_name:"Amber Route"},{id:"claude-violet-route",family:"violet",display_name:"Violet Route"}]' \
    '' \
    '' \
    '' \
    '["amber","violet","leverframe:openai-oauth:codex-auto-review"]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    ([.models[].selector] | index("claude-amber-route")) != null
    and ([.models[].selector] | index("amber")) != null
    and ([.models[].selector] | index("violet")) != null
    and ([.models[].selector] | index("leverframe:openai-oauth:codex-auto-review")) != null
    and .host_agent_enum == ["amber","violet","leverframe:openai-oauth:codex-auto-review"]
    and .agent_model_ids["claude-amber-route"] == "amber"
    and .agent_model_ids["leverframe:openai-oauth:codex-auto-review"] == "leverframe:openai-oauth:codex-auto-review"
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "map-agent-model rewrites a full selector to the host enum alias" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-sonnet-5",family:"sonnet",display_name:"Sonnet 5"},{id:"claude-opus-5",family:"opus",display_name:"Opus 5"}]' \
    '' \
    '' \
    '' \
    '["sonnet","opus","haiku","fable","leverframe:openai-oauth:codex-auto-review"]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" map-agent-model "$binary" "claude-sonnet-5"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "map-agent-model leaves a live custom id unchanged" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-sonnet-5",family:"sonnet",display_name:"Sonnet 5"},{id:"claude-opus-5",family:"opus",display_name:"Opus 5"}]' \
    '' \
    '' \
    '' \
    '["sonnet","opus","haiku","fable","leverframe:openai-oauth:codex-auto-review"]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" map-agent-model "$binary" "leverframe:openai-oauth:codex-auto-review"
  [ "$status" -eq 0 ]
  [ "$output" = "leverframe:openai-oauth:codex-auto-review" ]
}

@test "map-agent-model fails closed for an unknown model" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-amber-route",family:"amber",display_name:"Amber Route"},{id:"claude-violet-route",family:"violet",display_name:"Violet Route"}]' \
    '' \
    '' \
    '' \
    '["amber","violet"]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" map-agent-model "$binary" "not-a-model"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not present in the live host Agent enum"* ]]
}

@test "routing check accepts an extracted host alias" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-sonnet-5",family:"sonnet",display_name:"Sonnet 5"},{id:"claude-opus-5",family:"opus",display_name:"Opus 5"}]' \
    '' \
    '' \
    '' \
    '["sonnet","opus"]'
  mkdir -p "$PLANNING_DIR"
  jq '
    {
      schema_version: 1,
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {roles: {}},
          turbo: {roles: {}}
        }
      }
    }
  ' "$REPO_ROOT/config/settings.json" > "$PLANNING_DIR/config.json"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  run bash "$ROUTING" check "$PLANNING_DIR" sonnet '"careful"'
  [ "$status" -eq 0 ]
  jq -e '.model == "sonnet"' <<< "$output" >/dev/null
}

@test "routing check rejects a model missing from the extracted catalog" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-sonnet-5",family:"sonnet",display_name:"Sonnet 5"},{id:"claude-opus-5",family:"opus",display_name:"Opus 5"}]' \
    '' \
    '' \
    '' \
    '["sonnet","opus"]'
  mkdir -p "$PLANNING_DIR"
  jq '
    {
      schema_version: 1,
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {roles: {}},
          turbo: {roles: {}}
        }
      }
    }
  ' "$REPO_ROOT/config/settings.json" > "$PLANNING_DIR/config.json"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -eq 0 ]

  run bash "$ROUTING" check "$PLANNING_DIR" missing-route '"careful"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not present in the saved capability catalog"* ]]
}
