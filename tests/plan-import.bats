#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  SCRIPT="$SCRIPTS_DIR/plan-import.sh"
  GSD_SOURCE="$PROJECT_ROOT/tests/fixtures/import/gsd/.planning"
}

teardown() {
  teardown_temp_dir
}

@test "GSD adapter emits verified schema 1 IR with source provenance" {
  output_path="$TEST_TEMP_DIR/gsd-ir.json"

  run bash "$SCRIPT" normalize --adapter gsd --source "$GSD_SOURCE" --output "$output_path"

  [ "$status" -eq 0 ]
  jq -e '
    .schema_version == 1 and
    .source.system == "gsd" and
    .source.trust_tier == "verified-adapter" and
    .source.root == ".planning" and
    .source.gsd_version == "3" and
    .project.name == "Fixture Project" and
    .phases[0].status == "complete" and
    (.provenance | any(.field == "project.name" and .extraction_method == "markdown-heading")) and
    (.provenance | any(.field == "phases[0].status" and .extraction_method == "summary-file-presence"))
  ' "$output_path" >/dev/null
}

@test "GSD digest changes when a hidden source file changes" {
  first="$TEST_TEMP_DIR/first.json"
  second="$TEST_TEMP_DIR/second.json"
  original_hidden=$(<"$GSD_SOURCE/.source-marker")

  run bash "$SCRIPT" digest --source "$GSD_SOURCE" --output "$first"
  [ "$status" -eq 0 ]
  printf '%s\n' 'changed hidden source content' > "$GSD_SOURCE/.source-marker"
  run bash "$SCRIPT" digest --source "$GSD_SOURCE" --output "$second"
  [ "$status" -eq 0 ]

  first_digest=$(jq -r '.digest' "$first")
  second_digest=$(jq -r '.digest' "$second")
  [ "$first_digest" != "$second_digest" ]
  printf '%s\n' "$original_hidden" > "$GSD_SOURCE/.source-marker"
}

@test "legacy GSD index wrapper does not modify its source" {
  before=$(find "$GSD_SOURCE" -type f -print | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')

  run bash "$SCRIPTS_DIR/generate-gsd-index.sh" "$GSD_SOURCE"

  [ "$status" -eq 0 ]
  jq -e '(.gsd_version == "3") and (.quick_paths.roadmap | endswith("/ROADMAP.md"))' <<< "$output" >/dev/null
  after=$(find "$GSD_SOURCE" -type f -print | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
  [ "$before" = "$after" ]
  [ ! -e "$GSD_SOURCE/INDEX.json" ]
}

@test "generic Markdown adapter is unverified and enforces file and byte caps" {
  source="$TEST_TEMP_DIR/markdown"
  output_path="$TEST_TEMP_DIR/markdown-ir.json"
  mkdir -p "$source"
  for number in $(seq 1 65); do
    printf '# Generic %s\n' "$number" > "$source/plan-$number.md"
  done
  dd if=/dev/zero of="$source/oversized.md" bs=1048577 count=1 2>/dev/null

  run bash "$SCRIPT" normalize --adapter markdown --source "$source" --output "$output_path"

  [ "$status" -eq 0 ]
  jq -e '
    .source.trust_tier == "unverified-markdown" and
    (.plans | length) == 64 and
    (.source.limits.max_files == 64) and
    (.source.limits.max_file_bytes == 1048576) and
    (.source.limits.max_total_bytes == 8388608) and
    (.plans | all(.status == null and .depends_on == null)) and
    (.warnings | any(contains("file-count-cap"))) and
    (.warnings | any(contains("file-size-cap")))
  ' "$output_path" >/dev/null
}

@test "generic Markdown adapter reports total byte cap skips" {
  source="$TEST_TEMP_DIR/markdown-bytes"
  output_path="$TEST_TEMP_DIR/markdown-bytes-ir.json"
  mkdir -p "$source"
  for number in $(seq 1 9); do
    dd if=/dev/zero of="$source/plan-$number.md" bs=1000000 count=1 2>/dev/null
  done

  run bash "$SCRIPT" normalize --adapter markdown --source "$source" --output "$output_path"

  [ "$status" -eq 0 ]
  jq -e '(.source.skipped_files | any(.reason == "total-byte-cap")) and (.warnings | any(contains("total-byte-cap")))' "$output_path" >/dev/null
}

@test "staging validates a complete tree and leaves canonical files unchanged" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf '%s\n' '# Existing canonical project' > "$project/.lbwc-planning/PROJECT.md"
  before=$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id import-one

  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/import-one"
  [ -f "$stage/ir.json" ]
  [ -f "$stage/preview.json" ]
  [ -f "$stage/tree/.lbwc-planning/PROJECT.md" ]
  run bash "$SCRIPT" validate-stage --project-root "$project" --stage "$stage"
  [ "$status" -eq 0 ]
  after=$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "unchanged source re-import is reported as idempotent" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id first-import
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" reimport --source "$GSD_SOURCE" --project-root "$project"

  [ "$status" -eq 0 ]
  jq -e '.status == "unchanged" and .previous_import_id == "first-import"' <<< "$output" >/dev/null
}

@test "promotion requires explicit artifacts and rollback restores every destination" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf '%s\n' '# Old project' > "$project/.lbwc-planning/PROJECT.md"
  printf '%s\n' '# Old roadmap' > "$project/.lbwc-planning/ROADMAP.md"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id rollback-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/rollback-import"

  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage"
  [ "$status" -ne 0 ]
  grep -Fqx '# Old project' "$project/.lbwc-planning/PROJECT.md"

  run env LBWC_IMPORT_FAIL_AFTER=1 bash "$SCRIPT" promote --project-root "$project" --stage "$stage" \
    --artifact .lbwc-planning/PROJECT.md --artifact .lbwc-planning/ROADMAP.md
  [ "$status" -ne 0 ]
  grep -Fqx '# Old project' "$project/.lbwc-planning/PROJECT.md"
  grep -Fqx '# Old roadmap' "$project/.lbwc-planning/ROADMAP.md"
}
