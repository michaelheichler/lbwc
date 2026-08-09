#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PARSER="$REPO_ROOT/scripts/extract-frontmatter-array-items.awk"
SUMMARY_UTILS="$REPO_ROOT/scripts/summary-utils.sh"
QA_PATH_EVIDENCE="$REPO_ROOT/scripts/lib/qa-result-gate-path-evidence.sh"
FRESHNESS="$REPO_ROOT/scripts/verification-freshness.sh"

setup() {
  FIXTURE="$(mktemp)"
  cat > "$FIXTURE" <<'FRONTMATTER'
---
flow_paths: ["app/one.py", 'lib/it''s.py', "", '', bare.py]
block_paths:
  - "app/one.py"
  - 'lib/it''s.py'
  - ""
  - ''
  - bare.py
---
FRONTMATTER
}

teardown() {
  rm -f "$FIXTURE"
}

assert_canonical_items() {
  local key_name="$1"
  local expected=$'app/one.py\nlib/it\'s.py\nbare.py'

  run awk -v key="$key_name" -f "$PARSER" "$FIXTURE"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]

  run bash -c 'source "$1"; summary_extract_frontmatter_array_items "$2" "$3"' \
    _ "$SUMMARY_UTILS" "$FIXTURE" "$key_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]

  run bash -c 'source "$1"; extract_frontmatter_array_items "$2" "$3"' \
    _ "$QA_PATH_EVIDENCE" "$FIXTURE" "$key_name"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "frontmatter array consumers canonicalize quoted flow items" {
  assert_canonical_items flow_paths
}

@test "frontmatter array consumers canonicalize quoted block items" {
  assert_canonical_items block_paths
}

@test "verification freshness preserves commas in quoted recorded paths" {
  local phase_dir="$BATS_TEST_TMPDIR/phase"

  mkdir -p "$phase_dir"
  cat > "$phase_dir/01-PLAN.md" <<'FRONTMATTER'
---
files_modified: ["src/has,comma.py"]
---
FRONTMATTER

  run bash -c 'source "$1"; _freshness_recorded_paths "$2"' \
    _ "$FRESHNESS" "$phase_dir"
  [ "$status" -eq 0 ]
  [ "$output" = "src/has,comma.py" ]
}
