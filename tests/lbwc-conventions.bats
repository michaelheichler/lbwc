#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/lbwc-conventions.sh"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lbwc-conventions.XXXXXX")"
  PROJECT_DIR="$TEST_ROOT/project"
  PLANNING_DIR="$PROJECT_DIR/.lbwc-planning"
  mkdir -p "$PLANNING_DIR/codebase"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

run_conventions() {
  run bash "$SCRIPT" "$@"
}

write_candidates() {
  local path="$1"
  shift
  jq -n --argjson conventions "$1" '{schema_version: 1, conventions: $conventions}' > "$path"
}

@test "list returns a stable empty artifact before conventions exist" {
  run_conventions --json list "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = '{"conventions":[],"schema_version":1}' ]
  [ ! -e "$PLANNING_DIR/conventions.json" ]
}

@test "add writes a user convention with the compiler tag and rule projection" {
  run_conventions --json add "$PLANNING_DIR" naming "Components use PascalCase"

  [ "$status" -eq 0 ]
  run jq -ce '.conventions == [{
    added: (.conventions[0].added),
    category: "naming",
    confidence: null,
    detected_from: null,
    id: "CONV-001",
    rule: "Components use PascalCase",
    source: "user-defined",
    tag: "NAMING"
  }] and (.conventions[0].added | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))' "$PLANNING_DIR/conventions.json"
  [ "$status" -eq 0 ]
}

@test "add rejects a multiline rule before changing convention state" {
  run_conventions add "$PLANNING_DIR" naming "Components use PascalCase"
  [ "$status" -eq 0 ]
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"

  run_conventions add "$PLANNING_DIR" style $'Use formatter\nUse linter'

  [ "$status" -eq 2 ]
  [ "$output" = "Error: convention rule must be one non-empty line" ]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "group returns conventions keyed by category in stable order" {
  run_conventions add "$PLANNING_DIR" testing "Tests use Bats"
  [ "$status" -eq 0 ]
  run_conventions add "$PLANNING_DIR" naming "Shell functions use snake_case"
  [ "$status" -eq 0 ]

  run_conventions --json group "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$(jq -cS '{naming: [.conventions[1]], testing: [.conventions[0]]}' "$PLANNING_DIR/conventions.json")" ]
}

@test "add rejects a normalized redundant rule without changing the artifact" {
  run_conventions add "$PLANNING_DIR" naming "Components use PascalCase"
  [ "$status" -eq 0 ]
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"

  run_conventions add "$PLANNING_DIR" naming "  components   USE pascalcase  "

  [ "$status" -eq 3 ]
  [[ "$output" == *"redundant with CONV-001"* ]]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "add requires an explicit resolution for a declared conflict" {
  run_conventions add "$PLANNING_DIR" style "Use tabs for indentation"
  [ "$status" -eq 0 ]

  run_conventions add "$PLANNING_DIR" style "Use spaces for indentation" --conflicts-with CONV-001

  [ "$status" -eq 4 ]
  [[ "$output" == *"conflict with CONV-001 requires --replace or --keep-both"* ]]
  [ "$(jq '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 1 ]

  run_conventions add "$PLANNING_DIR" style "Use spaces for indentation" --conflicts-with CONV-001 --keep-both
  [ "$status" -eq 0 ]
  [ "$(jq '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 2 ]
}

@test "add can replace the exact convention selected by the user" {
  run_conventions add "$PLANNING_DIR" tooling "Use npm"
  [ "$status" -eq 0 ]

  run_conventions add "$PLANNING_DIR" tooling "Use pnpm" --conflicts-with CONV-001 --replace CONV-001

  [ "$status" -eq 0 ]
  [ "$(jq -r '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 1 ]
  [ "$(jq -r '.conventions[0].rule' "$PLANNING_DIR/conventions.json")" = "Use pnpm" ]
  [ "$(jq -r '.conventions[0].source' "$PLANNING_DIR/conventions.json")" = "user-defined" ]
}

@test "remove requires confirmation and removes only the selected id" {
  run_conventions add "$PLANNING_DIR" testing "Run unit tests"
  [ "$status" -eq 0 ]
  run_conventions add "$PLANNING_DIR" style "Format before commit"
  [ "$status" -eq 0 ]

  run_conventions remove "$PLANNING_DIR" CONV-001
  [ "$status" -eq 4 ]
  [ "$(jq '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 2 ]

  run_conventions remove "$PLANNING_DIR" CONV-001 --yes
  [ "$status" -eq 0 ]
  [ "$(jq -r '.conventions[].id' "$PLANNING_DIR/conventions.json")" = "CONV-002" ]
}

@test "refresh preserves user conventions and replaces stale auto detections" {
  run_conventions add "$PLANNING_DIR" naming "Components use PascalCase"
  [ "$status" -eq 0 ]
  candidates_one="$TEST_ROOT/candidates-one.json"
  write_candidates "$candidates_one" '[
    {"rule":"Tests live beside source files","category":"testing","confidence":"high","detected_from":"PATTERNS.md"}
  ]'
  run_conventions refresh "$PLANNING_DIR" "$candidates_one"
  [ "$status" -eq 0 ]

  candidates_two="$TEST_ROOT/candidates-two.json"
  write_candidates "$candidates_two" '[
    {"rule":"components use pascalcase","category":"naming","confidence":"high","detected_from":"ARCHITECTURE.md"},
    {"rule":"Use shellcheck for shell scripts","category":"tooling","confidence":"medium","detected_from":"CONCERNS.md"}
  ]'
  run_conventions refresh "$PLANNING_DIR" "$candidates_two"

  [ "$status" -eq 0 ]
  [ "$(jq '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 2 ]
  [ "$(jq -r '.conventions[] | select(.source == "user-defined") | .rule' "$PLANNING_DIR/conventions.json")" = "Components use PascalCase" ]
  [ "$(jq -r '.conventions[] | select(.source == "auto-detected") | .rule' "$PLANNING_DIR/conventions.json")" = "Use shellcheck for shell scripts" ]
  run jq -e '.conventions | any(.rule == "Tests live beside source files") | not' "$PLANNING_DIR/conventions.json"
  [ "$status" -eq 0 ]
}

@test "refresh drops auto candidates that explicitly conflict with a user convention" {
  run_conventions add "$PLANNING_DIR" tooling "Use pnpm"
  [ "$status" -eq 0 ]
  candidates="$TEST_ROOT/conflict.json"
  write_candidates "$candidates" '[
    {"rule":"Use npm","category":"tooling","confidence":"high","detected_from":"STACK.md","conflicts_with":["CONV-001"]}
  ]'

  run_conventions refresh "$PLANNING_DIR" "$candidates"

  [ "$status" -eq 0 ]
  [ "$(jq '.conventions | length' "$PLANNING_DIR/conventions.json")" -eq 1 ]
  [ "$(jq -r '.conventions[0].rule' "$PLANNING_DIR/conventions.json")" = "Use pnpm" ]
}

@test "reconcile previews the next artifact without mutating current state" {
  run_conventions add "$PLANNING_DIR" patterns "Services use repository objects"
  [ "$status" -eq 0 ]
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"
  candidates="$TEST_ROOT/reconcile.json"
  write_candidates "$candidates" '[
    {"rule":"HTTP handlers are thin","category":"patterns","confidence":"high","detected_from":"ARCHITECTURE.md"}
  ]'

  run_conventions --json reconcile "$PLANNING_DIR" "$candidates"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.conventions | length' <<< "$output")" -eq 2 ]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "malformed refresh input fails atomically" {
  run_conventions add "$PLANNING_DIR" testing "Tests use fixtures"
  [ "$status" -eq 0 ]
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"
  printf '%s\n' '{broken' > "$TEST_ROOT/broken.json"

  run_conventions refresh "$PLANNING_DIR" "$TEST_ROOT/broken.json"

  [ "$status" -eq 2 ]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "refresh requires candidate schema version one" {
  run_conventions add "$PLANNING_DIR" testing "Tests use fixtures"
  [ "$status" -eq 0 ]
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"
  printf '%s\n' '{"schema_version":2,"conventions":[]}' > "$TEST_ROOT/version-two.json"

  run_conventions refresh "$PLANNING_DIR" "$TEST_ROOT/version-two.json"

  [ "$status" -eq 2 ]
  [ "$output" = "Error: invalid convention candidates" ]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "malformed existing artifact blocks every write" {
  printf '%s\n' '{"conventions":"wrong"}' > "$PLANNING_DIR/conventions.json"
  before="$(shasum -a 256 "$PLANNING_DIR/conventions.json")"

  run_conventions add "$PLANNING_DIR" style "Use formatter"

  [ "$status" -eq 2 ]
  [ "$(shasum -a 256 "$PLANNING_DIR/conventions.json")" = "$before" ]
}

@test "planning traversal and symbolic link boundaries fail closed" {
  run_conventions list "$PROJECT_DIR/child/../.lbwc-planning"
  [ "$status" -eq 2 ]
  [[ "$output" == *"traversal"* ]]

  mv "$PLANNING_DIR" "$PROJECT_DIR/real-planning"
  ln -s "$PROJECT_DIR/real-planning" "$PLANNING_DIR"
  run_conventions list "$PLANNING_DIR"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symbolic link"* ]]
}

@test "an ancestor symbolic link is rejected before physical path normalization" {
  physical_project="$TEST_ROOT/physical-project"
  mkdir -p "$physical_project/.lbwc-planning"
  ln -s "$physical_project" "$TEST_ROOT/linked-project"

  run_conventions list "$TEST_ROOT/linked-project/.lbwc-planning"

  [ "$status" -eq 2 ]
  [[ "$output" == *"symbolic link paths are not allowed:"*"linked-project"* ]]
}

@test "a symbolic conventions artifact is never read or replaced" {
  target="$TEST_ROOT/target.json"
  printf '%s\n' '{"protected":true}' > "$target"
  ln -s "$target" "$PLANNING_DIR/conventions.json"

  run_conventions add "$PLANNING_DIR" other "Keep this rule"

  [ "$status" -eq 2 ]
  [ "$(jq -r '.protected' "$target")" = true ]
  [ -L "$PLANNING_DIR/conventions.json" ]
}

@test "stable JSON survives repeated list and refresh calls byte for byte" {
  candidates="$TEST_ROOT/stable.json"
  write_candidates "$candidates" '[
    {"rule":"B rule","category":"style","confidence":"medium","detected_from":"PATTERNS.md"},
    {"rule":"A rule","category":"naming","confidence":"high","detected_from":"ARCHITECTURE.md"}
  ]'
  run_conventions refresh "$PLANNING_DIR" "$candidates"
  [ "$status" -eq 0 ]
  first="$(bash "$SCRIPT" --json list "$PLANNING_DIR")"

  run_conventions refresh "$PLANNING_DIR" "$candidates"
  [ "$status" -eq 0 ]
  second="$(bash "$SCRIPT" --json list "$PLANNING_DIR")"

  [ "$first" = "$second" ]
}

@test "human output provides a readable table and refresh change counts" {
  run_conventions add "$PLANNING_DIR" naming "Components use PascalCase"
  [ "$status" -eq 0 ]
  candidates="$TEST_ROOT/human.json"
  write_candidates "$candidates" '[
    {"rule":"Tests use Bats","category":"testing","confidence":"high","detected_from":"PATTERNS.md"}
  ]'

  run_conventions refresh "$PLANNING_DIR" "$candidates"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Added: 1 | Updated: 0 | Removed: 0 | Kept: 1"* ]]
  [[ "$output" == *"ID"*"Category"*"Source"*"Confidence"*"Rule"* ]]
}

@test "refresh rejects conflict references outside the current artifact" {
  candidates="$TEST_ROOT/unknown-conflict.json"
  write_candidates "$candidates" '[
    {"rule":"Use pnpm","category":"tooling","confidence":"high","detected_from":"STACK.md","conflicts_with":["CONV-999"]}
  ]'

  run_conventions refresh "$PLANNING_DIR" "$candidates"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown conflict reference: CONV-999"* ]]
  [ ! -e "$PLANNING_DIR/conventions.json" ]
}

@test "legacy tag and rule entries migrate without changing the compiler projection" {
  printf '%s\n' '{"conventions":[{"tag":"STYLE","rule":"Use formatter"}]}' > "$PLANNING_DIR/conventions.json"

  run_conventions --json list "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$(jq -r '.conventions[0] | [.tag, .rule, .source, .category] | @tsv' <<< "$output")" = $'STYLE\tUse formatter\tuser-defined\tstyle' ]
}

@test "only schema version one or the legacy tag and rule shape is accepted" {
  printf '%s\n' '{"schema_version":2,"conventions":[]}' > "$PLANNING_DIR/conventions.json"

  run_conventions --json list "$PLANNING_DIR"

  [ "$status" -eq 2 ]
  [ "$output" = "Error: invalid conventions artifact" ]

  printf '%s\n' '{"conventions":[{"id":"CONV-001","tag":"STYLE","rule":"Use formatter","source":"user-defined","category":"style","confidence":null,"detected_from":null,"added":"2026-08-10"}]}' > "$PLANNING_DIR/conventions.json"

  run_conventions --json list "$PLANNING_DIR"

  [ "$status" -eq 2 ]
  [ "$output" = "Error: invalid conventions artifact" ]
}

@test "human success output ends with next guidance" {
  run_conventions add "$PLANNING_DIR" style "Use formatter"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\nNext: continue your current LBWC workflow.' ]]
}

@test "a failed lock acquisition never removes another writer lock" {
  mkdir "$PLANNING_DIR/.conventions.lock"

  run_conventions add "$PLANNING_DIR" style "Use formatter"

  [ "$status" -eq 2 ]
  [[ "$output" == *"could not acquire conventions lock"* ]]
  [ -d "$PLANNING_DIR/.conventions.lock" ]
  [ ! -e "$PLANNING_DIR/conventions.json" ]
}
