#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMMAND="$REPO_ROOT/commands/import.md"
}

@test "import command resolves plugin and project roots in one self-contained directive" {
  run grep -c '^!`' "$COMMAND"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  grep -F 'scripts/resolve-plugin-root.sh' "$COMMAND" >/dev/null
  grep -F 'lbwc-target-root.sh' "$COMMAND" >/dev/null
  grep -F '{LINK}/scripts/plan-import.sh' "$COMMAND" >/dev/null
  grep -F '{PROJECT_ROOT}' "$COMMAND" >/dev/null
}

@test "import command stages and previews before explicit promotion" {
  grep -F 'plan-import.sh" stage' "$COMMAND" >/dev/null
  grep -F 'validate-stage' "$COMMAND" >/dev/null
  grep -F '## Preview' "$COMMAND" >/dev/null
  grep -F 'one explicit `--artifact` argument per accepted artifact' "$COMMAND" >/dev/null
  grep -F 'Never copy, move, or edit canonical LBWC files directly' "$COMMAND" >/dev/null
  grep -F '## Promotion' "$COMMAND" >/dev/null
}

@test "import command uses one-question conflict decisions and preserves cancel state" {
  grep -F 'ask exactly one bounded question' "$COMMAND" >/dev/null
  grep -F '`Keep existing`' "$COMMAND" >/dev/null
  grep -F '`Use imported`' "$COMMAND" >/dev/null
  grep -F '`Cancel import`' "$COMMAND" >/dev/null
  grep -F 'leaves the previously canonical artifact set intact' "$COMMAND" >/dev/null
}

@test "import command keeps generic Markdown visibly unverified" {
  grep -F 'visibly unverified `markdown` adapter' "$COMMAND" >/dev/null
  grep -F 'Generic Markdown remains labeled `unverified`' "$COMMAND" >/dev/null
}

@test "import command requires unchanged reimport detection and source recheck" {
  grep -F 'plan-import.sh" reimport' "$COMMAND" >/dev/null
  grep -F 're-verifies the source digest' "$COMMAND" >/dev/null
  grep -F 'source change' "$COMMAND" >/dev/null
}
