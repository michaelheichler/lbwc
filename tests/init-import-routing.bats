#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMMAND="$REPO_ROOT/commands/init.md"
}

@test "init redirects external plans to the standalone importer" {
  grep -F '### Step 0.5: External plan redirect' "$COMMAND" >/dev/null
  grep -F '`Import external plan`, `Start fresh initialization`, or `Cancel`' "$COMMAND" >/dev/null
  grep -F '`/lbwc:import` is the only import authority' "$COMMAND" >/dev/null
}

@test "init no longer copies or archives GSD state" {
  run grep -E 'cp -r \.planning|gsd-archive|generate-gsd-index|GSD_IMPORTED|GSD_MIGRATION|\.gsd-isolation|\.lbwc-session' "$COMMAND"

  [ "$status" -eq 1 ]
}
