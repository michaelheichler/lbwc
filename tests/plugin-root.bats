#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_SESSION_ID="plugin-root-$$"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  export ROOT_LINK="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID}"
  rm -rf "$ROOT_LINK"
}

teardown() {
  rm -rf "$ROOT_LINK"
  teardown_temp_dir
}

@test "resolver prints the configured root and creates its session link" {
  local plugin_root="$TEST_TEMP_DIR/plugin"
  mkdir -p "$plugin_root/scripts"
  touch "$plugin_root/scripts/hook-wrapper.sh"
  ln -s "$SCRIPTS_DIR/ensure-plugin-root-link.sh" "$plugin_root/scripts/ensure-plugin-root-link.sh"

  run env CLAUDE_PLUGIN_ROOT="$plugin_root" bash "$SCRIPTS_DIR/resolve-plugin-root.sh"

  local canonical_root
  canonical_root=$(cd "$plugin_root" && pwd -P)

  [ "$status" -eq 0 ]
  [ "$output" = "$canonical_root" ]
  [ -L "$ROOT_LINK" ]
  [ "$(readlink "$ROOT_LINK")" = "$canonical_root" ]
}

@test "resolver does not select a plugin cache candidate" {
  local cache_root="$CLAUDE_CONFIG_DIR/plugins/cache/lbwc-marketplace/lbwc/local"
  mkdir -p "$cache_root/scripts"
  touch "$cache_root/scripts/hook-wrapper.sh"

  run env -u CLAUDE_PLUGIN_ROOT bash "$SCRIPTS_DIR/resolve-plugin-root.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"LBWC: plugin root unavailable"* ]]
  [ ! -e "$ROOT_LINK" ]
}

@test "root link replaces a stale directory with the requested session symlink" {
  local plugin_root="$TEST_TEMP_DIR/plugin"
  mkdir -p "$plugin_root" "$ROOT_LINK"
  touch "$ROOT_LINK/stale"

  run bash "$SCRIPTS_DIR/ensure-plugin-root-link.sh" "$ROOT_LINK" "$plugin_root"

  [ "$status" -eq 0 ]
  [ -L "$ROOT_LINK" ]
  [ "$(readlink "$ROOT_LINK")" = "$plugin_root" ]
}

@test "root link rejects a non-LBWC link name" {
  local plugin_root="$TEST_TEMP_DIR/plugin"
  mkdir -p "$plugin_root"

  run bash "$SCRIPTS_DIR/ensure-plugin-root-link.sh" "/tmp/.not-lbwc-plugin-root-link-${CLAUDE_SESSION_ID}" "$plugin_root"

  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected link path basename"* ]]
}
