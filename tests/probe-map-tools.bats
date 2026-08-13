#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test"
  touch dummy && git add dummy && git commit -m "init" --quiet
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

mock_serena_enabled() {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"enabledPlugins":{"serena@claude-plugins-official":true}}' > "$HOME/.claude/settings.json"
}

mock_serena_absent() {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"enabledPlugins":{}}' > "$HOME/.claude/settings.json"
}

mock_gitnexus_enabled() {
  printf '%s' '{"mcpServers":{"gitnexus":{"command":"/opt/homebrew/bin/gitnexus","args":["mcp"]}}}' > "$HOME/.claude.json"
}

mock_gitnexus_absent() {
  printf '%s' '{"mcpServers":{}}' > "$HOME/.claude.json"
}

mock_lsp_enabled() {
  mkdir -p "$HOME/.claude"
  printf '%s' '{"enabledPlugins":{},"env":{"ENABLE_LSP_TOOL":"1"}}' > "$HOME/.claude/settings.json"
  echo '#!/usr/bin/env bash' > "$PROJECT_DIR/probe.sh"
}

run_probe() {
  run bash "$SCRIPTS_DIR/probe-map-tools.sh"
}

map_data() {
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext | fromjson'
}

@test "serena available wins over gitnexus also available" {
  mock_serena_enabled
  mock_gitnexus_enabled

  run_probe

  [ "$status" -eq 0 ]
  data=$(map_data)
  echo "$data" | jq -e '.serena.available == true' >/dev/null
  echo "$data" | jq -e '.gitnexus.available == true' >/dev/null
  echo "$data" | jq -e '.recommended_route == "serena"' >/dev/null
}

@test "gitnexus wins when serena unavailable" {
  mock_serena_absent
  mock_gitnexus_enabled

  run_probe

  [ "$status" -eq 0 ]
  data=$(map_data)
  echo "$data" | jq -e '.serena.available == false' >/dev/null
  echo "$data" | jq -e '.gitnexus.available == true' >/dev/null
  echo "$data" | jq -e '.recommended_route == "gitnexus"' >/dev/null
}

@test "lsp wins when only lsp available" {
  mock_serena_absent
  mock_gitnexus_absent
  mock_lsp_enabled

  run_probe

  [ "$status" -eq 0 ]
  data=$(map_data)
  echo "$data" | jq -e '.serena.available == false' >/dev/null
  echo "$data" | jq -e '.gitnexus.available == false' >/dev/null
  echo "$data" | jq -e '.lsp.env_needed == false' >/dev/null
  echo "$data" | jq -e '.recommended_route == "lsp"' >/dev/null
}

@test "grep-only when nothing is available" {
  mock_serena_absent
  mock_gitnexus_absent

  run_probe

  [ "$status" -eq 0 ]
  data=$(map_data)
  echo "$data" | jq -e '.serena.available == false' >/dev/null
  echo "$data" | jq -e '.gitnexus.available == false' >/dev/null
  echo "$data" | jq -e '.recommended_route == "grep-only"' >/dev/null
}

@test "does not create .lbwc-planning when absent, still returns route" {
  mock_serena_absent
  mock_gitnexus_absent
  [ ! -d "$PROJECT_DIR/.lbwc-planning" ]

  run_probe

  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT_DIR/.lbwc-planning" ]
  data=$(map_data)
  echo "$data" | jq -e '.recommended_route' >/dev/null
  echo "$data" | jq -e '.codebase_map.available == false and .codebase_map.canonical_path == null' >/dev/null
}

@test "reports canonical codebase map pointer, digest, and freshness" {
  mock_serena_absent
  mock_gitnexus_absent
  mkdir -p "$PROJECT_DIR/.lbwc-planning/codebase"
  current_hash=$(git -C "$PROJECT_DIR" rev-parse HEAD)
  printf 'mapped_at: 2026-08-01T00:00:00Z\ngit_hash: %s\nfile_count: 1\n' \
    "$current_hash" > "$PROJECT_DIR/.lbwc-planning/codebase/META.md"

  run_probe

  [ "$status" -eq 0 ]
  data=$(map_data)
  digest=$(shasum -a 256 "$PROJECT_DIR/.lbwc-planning/codebase/META.md" | awk '{print "sha256:" $1}')
  echo "$data" | jq -e --arg path "$(cd "$PROJECT_DIR/.lbwc-planning/codebase" && pwd -P)/META.md" \
    --arg digest "$digest" \
    '.codebase_map == {available:true,canonical_path:$path,digest:$digest,freshness:"fresh"}' >/dev/null
}

@test "writes MAP-TOOLS.json when .lbwc-planning already exists" {
  mock_serena_absent
  mock_gitnexus_absent
  mkdir -p "$PROJECT_DIR/.lbwc-planning"

  run_probe

  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.lbwc-planning/MAP-TOOLS.json" ]
  jq -e '.recommended_route' "$PROJECT_DIR/.lbwc-planning/MAP-TOOLS.json" >/dev/null
}
