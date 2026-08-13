#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HELP_OUTPUT="$REPO_ROOT/scripts/help-output.sh"
  TEST_ROOT="$(mktemp -d)"
  PLUGIN_ROOT="$TEST_ROOT/plugin"
  mkdir -p "$PLUGIN_ROOT/.claude-plugin" "$PLUGIN_ROOT/commands"
  jq -n '{name: "lbwc", version: "test"}' > "$PLUGIN_ROOT/.claude-plugin/plugin.json"
  cat > "$PLUGIN_ROOT/commands/vibe.md" <<'EOF'
---
category: lifecycle
description: Continue the project workflow.
argument-hint: '[brief]'
allowed-tools: Read
disable-model-invocation: true
---
EOF
  cat > "$PLUGIN_ROOT/commands/list-todos.md" <<'EOF'
---
category: supporting
description: List project todos.
argument-hint: ''
allowed-tools: Read
disable-model-invocation: true
---
EOF
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "help output derives names from the plugin manifest and filenames" {
  run bash "$HELP_OUTPUT" "$PLUGIN_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"/lbwc:vibe '[brief]'"* ]]
  [[ "$output" == *'/lbwc:list-todos'* ]]
  [[ "$output" != *'/lbwc:lbwc:vibe'* ]]
  [ "$(printf '%s\n' "$output" | grep -c '^  /lbwc:vibe ')" -eq 1 ]
}
