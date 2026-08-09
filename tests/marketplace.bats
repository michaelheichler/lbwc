#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
  PLUGIN="$ROOT/.claude-plugin/plugin.json"
}

@test "marketplace declares the root LBWC plugin with synchronized versions" {
  run jq -e --arg version "$(tr -d '[:space:]' < "$ROOT/VERSION")" '
    .name == "lbwc-marketplace"
    and .version == $version
    and (.plugins | length == 1)
    and .plugins[0].name == "lbwc"
    and .plugins[0].source == "."
    and .plugins[0].version == $version
  ' "$MARKETPLACE"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' "$PLUGIN")" = "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]
}
