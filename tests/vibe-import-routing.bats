#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VIBE="$REPO_ROOT/commands/vibe.md"
  PARSING="$REPO_ROOT/references/vibe-input-parsing.md"
}

@test "vibe routes explicit import before init redirect" {
  import_line=$(grep -n '^### Mode: Import$' "$VIBE" | cut -d: -f1)
  init_line=$(grep -n '^### Mode: Init Redirect$' "$VIBE" | cut -d: -f1)

  [ "$import_line" -lt "$init_line" ]
  grep -F 'Explicit `--import [path]`' "$VIBE" >/dev/null
}

@test "uninitialized external plans offer import fresh init or cancel" {
  grep -F '`Import external plan`, `Start fresh initialization`, or `Cancel`' "$VIBE" >/dev/null
}

@test "vibe parsing preserves state priority without import intent" {
  grep -F 'Existing remediation and lifecycle state routes retain their priority when import intent is absent.' "$PARSING" >/dev/null
  grep -F 'planning_dir_exists=false` and no import intent' "$PARSING" >/dev/null
}
