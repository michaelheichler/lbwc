#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/infer-project-context.sh"
  TEST_ROOT="$(mktemp -d)"
  MAP_DIR="$TEST_ROOT/codebase"
  TEST_REPO="$TEST_ROOT/repo"
  mkdir -p "$MAP_DIR" "$TEST_REPO"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_stack() {
  local heading="$1" purpose="$2"
  printf '%s\n' \
    '# Stack' \
    '' \
    "## $heading" \
    '' \
    "$purpose" \
    '' \
    'This second paragraph is outside the inferred purpose.' \
    '' \
    '## Languages' \
    '' \
    '| Language | Evidence |' \
    '| --- | --- |' \
    '| Bash | scripts and hooks |' \
    '' \
    '## Key Technologies' \
    '' \
    '- **jq**: JSON processing' \
    > "$MAP_DIR/STACK.md"
}

write_supporting_map() {
  printf '%s\n' \
    '# Architecture' \
    '' \
    '## Overview' \
    '' \
    'Markdown commands delegate work to Bash scripts.' \
    > "$MAP_DIR/ARCHITECTURE.md"
  printf '%s\n' \
    '# Codebase Map Index' \
    '' \
    '## Cross-Cutting Themes' \
    '' \
    '- **Lifecycle**: Plan, execute, and verify work.' \
    > "$MAP_DIR/INDEX.md"
}

write_concerns() {
  printf '%s\n' \
    '# DO NOT USE THIS AS PURPOSE' \
    '' \
    '## Catastrophic data loss risk' \
    '' \
    '## Credential leakage risk' \
    > "$MAP_DIR/CONCERNS.md"
}

@test "canonical map infers every project context field without concern text" {
  local purpose="A Claude Code plugin for a plan, execute, verify workflow."
  write_stack "Purpose" "$purpose"
  write_supporting_map
  write_concerns

  run bash "$SCRIPT" "$MAP_DIR" "$TEST_REPO"

  [ "$status" -eq 0 ]
  jq -e --arg expected "$purpose" '
    .purpose == {value: $expected, source: "STACK.md: Purpose"} and
    (.purpose.value | contains("DO NOT USE THIS AS PURPOSE") | not) and
    (.purpose.value | contains("Catastrophic data loss risk") | not) and
    (.tech_stack.value != null) and
    (.architecture.value != null) and
    (.features.value != null)
  ' <<< "$output" > /dev/null
}

@test "transitional purpose heading remains supported" {
  local purpose="A transitional map purpose."
  write_stack "What this repo is" "$purpose"

  run bash "$SCRIPT" "$MAP_DIR" "$TEST_REPO"

  [ "$status" -eq 0 ]
  jq -e --arg expected "$purpose" \
    '.purpose == {value: $expected, source: "STACK.md: What this repo is"}' \
    <<< "$output" > /dev/null
}

@test "missing purpose section returns the null object" {
  write_stack "Languages and tools" "No purpose exists in this map."
  write_concerns

  run bash "$SCRIPT" "$MAP_DIR" "$TEST_REPO"

  [ "$status" -eq 0 ]
  jq -e '.purpose == {value: null, source: null}' <<< "$output" > /dev/null
}
