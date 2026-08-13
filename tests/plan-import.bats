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

@test "single Markdown file source stages as an unverified imported plan" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"
  printf '# Solo Plan\n\nBody text.\n' > "$TEST_TEMP_DIR/solo.md"

  run bash "$SCRIPT" stage --adapter markdown --source "$TEST_TEMP_DIR/solo.md" --project-root "$project" --import-id md-file
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/md-file"
  jq -e '
    .source.trust_tier == "unverified-markdown" and
    (.additions | index(".lbwc-planning/imported-markdown/solo.md") != null) and
    (.unknowns | any(. == "solo.md"))
  ' "$stage/preview.json" >/dev/null
  [ -f "$stage/tree/.lbwc-planning/imported-markdown/solo.md" ]
  grep -F 'unverified generic Markdown import' "$stage/tree/.lbwc-planning/imported-markdown/solo.md" >/dev/null
  grep -F 'Body text.' "$stage/tree/.lbwc-planning/imported-markdown/solo.md" >/dev/null
}

@test "preview paths are repository-relative and conflicts carry semantic detail" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf -- '- [x] **REQ-01**: Import the project without changing the source\n- [ ] **REQ-02**: Preserve source provenance\n- [ ] **REQ-99**: Existing only\n' > "$project/.lbwc-planning/REQUIREMENTS.md"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id semantic
  [ "$status" -eq 0 ]
  preview="$project/.temporary-agent-runfiles/imports/semantic/preview.json"
  jq -e '
    ([.additions[], .overlaps[], .conflicts[].artifact, .unknowns[], .skipped[].path] | all(startswith("/") | not)) and
    (.conflicts | length == 1) and
    (.conflicts[0].artifact == ".lbwc-planning/REQUIREMENTS.md") and
    (.conflicts[0].detail.removed_ids == ["REQ-99"]) and
    (.conflicts[0].detail.changed_statuses | length == 2) and
    (.conflicts[0].source_digest | test("^[0-9a-f]{64}$")) and
    (.conflicts[0].destination_digest | test("^[0-9a-f]{64}$"))
  ' "$preview" >/dev/null
}

@test "promotion writes template-valid canonical artifacts and provenance" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id full-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/full-import"
  artifacts=$(jq -r '.additions[]' "$stage/preview.json")

  promote_args=(--project-root "$project" --stage "$stage")
  while IFS= read -r artifact; do
    promote_args+=(--artifact "$artifact")
  done <<< "$artifacts"
  run bash "$SCRIPT" promote "${promote_args[@]}"
  [ "$status" -eq 0 ]

  promoted_planning="$project/.lbwc-planning"
  grep -Fx '# Fixture Project' "$promoted_planning/PROJECT.md" >/dev/null
  grep -F '**Core value:**' "$promoted_planning/PROJECT.md" >/dev/null
  grep -F '## Current Phase' "$promoted_planning/STATE.md" >/dev/null
  grep -F '## Key Decisions' "$promoted_planning/STATE.md" >/dev/null
  grep -F '### Phase 1: foundation' "$promoted_planning/ROADMAP.md" >/dev/null
  grep -F -- '- [x] **REQ-02**' "$promoted_planning/REQUIREMENTS.md" >/dev/null
  grep -Fx 'phase: 1' "$promoted_planning/phases/01-foundation/01-01-PLAN.md" >/dev/null
  grep -F '<objective>' "$promoted_planning/phases/01-foundation/01-01-PLAN.md" >/dev/null
  grep -F 'Implement the import boundary.' "$promoted_planning/phases/01-foundation/01-01-PLAN.md" >/dev/null

  provenance="$promoted_planning/imports/full-import"
  [ -f "$provenance/manifest.json" ]
  [ -f "$provenance/ir.json" ]
  [ -f "$provenance/preview.json" ]
  jq -e '.status == "promoted"' "$provenance/manifest.json" >/dev/null

  consistency_output=$(cd "$project" && LBWC_PLANNING_DIR="$promoted_planning" bash "$SCRIPTS_DIR/verify-state-consistency.sh") || {
    printf 'verify-state-consistency failed: %s\n' "$consistency_output" >&2
    false
  }
  [[ "$consistency_output" == *'state_consistency=ok'* ]]
}

@test "fresh successful import is a complete initialized LBWC project including config.json" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id init-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/init-import"
  artifacts=$(jq -r '.additions[]' "$stage/preview.json")

  promote_args=(--project-root "$project" --stage "$stage")
  while IFS= read -r artifact; do
    promote_args+=(--artifact "$artifact")
  done <<< "$artifacts"
  run bash "$SCRIPT" promote "${promote_args[@]}"
  [ "$status" -eq 0 ]

  promoted_planning="$project/.lbwc-planning"
  # Complete initialized tree: all canonical artifacts plus config.json.
  for expected in PROJECT.md REQUIREMENTS.md ROADMAP.md STATE.md config.json; do
    [ -f "$promoted_planning/$expected" ]
  done

  # config.json is valid per the repository validator and matches init defaults.
  run bash "$SCRIPTS_DIR/lbwc-config.sh" validate-config-json < "$promoted_planning/config.json"
  [ "$status" -eq 0 ]
  expected_config=$(bash "$SCRIPTS_DIR/lbwc-config.sh" default-config)
  [ "$(jq -S . "$promoted_planning/config.json")" = "$(jq -S . <<< "$expected_config")" ]
  jq -e '.schema_version == 1 and (.routing.profiles | keys | sort == ["balanced","quality","turbo"])' "$promoted_planning/config.json" >/dev/null

  # Planning directory passes repository config and state validation.
  config_validate_output=$(bash "$SCRIPTS_DIR/lbwc-config.sh" validate "$promoted_planning") || {
    printf 'lbwc-config validate failed: %s\n' "$config_validate_output" >&2
    false
  }
  consistency_output=$(cd "$project" && LBWC_PLANNING_DIR="$promoted_planning" bash "$SCRIPTS_DIR/verify-state-consistency.sh") || {
    printf 'verify-state-consistency failed: %s\n' "$consistency_output" >&2
    false
  }
  [[ "$consistency_output" == *'state_consistency=ok'* ]]
}

@test "promotion rejects a source that changed after staging" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id drift-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/drift-import"
  original_hidden=$(<"$GSD_SOURCE/.source-marker")
  printf '%s\n' 'mutated after staging' > "$GSD_SOURCE/.source-marker"

  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact .lbwc-planning/PROJECT.md
  [ "$status" -ne 0 ]
  [[ "$output" == *'source changed after staging'* ]]
  [ ! -e "$project/.lbwc-planning/PROJECT.md" ]
  [ ! -e "$project/.lbwc-planning/imports/drift-import/manifest.json" ]
  printf '%s\n' "$original_hidden" > "$GSD_SOURCE/.source-marker"
}

@test "failed promotion restores canonical digests and removes provenance" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf '%s\n' '# Canonical project' > "$project/.lbwc-planning/PROJECT.md"
  printf '%s\n' '# Canonical state' > "$project/.lbwc-planning/STATE.md"
  before_project=$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')
  before_state=$(shasum -a 256 "$project/.lbwc-planning/STATE.md" | awk '{print $1}')

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id fail-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/fail-import"

  run env LBWC_IMPORT_FAIL_AFTER=2 bash "$SCRIPT" promote --project-root "$project" --stage "$stage" \
    --artifact .lbwc-planning/PROJECT.md \
    --artifact .lbwc-planning/STATE.md \
    --artifact .lbwc-planning/REQUIREMENTS.md
  [ "$status" -ne 0 ]
  [ "$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')" = "$before_project" ]
  [ "$(shasum -a 256 "$project/.lbwc-planning/STATE.md" | awk '{print $1}')" = "$before_state" ]
  [ ! -e "$project/.lbwc-planning/REQUIREMENTS.md" ]
  [ ! -e "$project/.lbwc-planning/imports/fail-import/manifest.json" ]
}

@test "cancel-equivalent staged import leaves canonical digests unchanged" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf '%s\n' '# Untouched' > "$project/.lbwc-planning/PROJECT.md"
  before=$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id cancel-import
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" validate-stage --project-root "$project" --stage "$project/.temporary-agent-runfiles/imports/cancel-import"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')" = "$before" ]
  [ ! -e "$project/.lbwc-planning/imports/cancel-import/manifest.json" ]
}

@test "reimport after promotion is unchanged and restaging a fresh preview works" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id re-one
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/re-one"
  # A partial promote without config.json fails post-promotion validation and rolls back.
  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact .lbwc-planning/PROJECT.md
  [ "$status" -ne 0 ]
  [[ "$output" == *'post-promotion validation failed'* ]]
  [ ! -e "$project/.lbwc-planning/imports/re-one/manifest.json" ]
  # The failed first import leaves no newly created empty planning directory.
  [ ! -e "$project/.lbwc-planning" ]

  # A complete promote including config.json succeeds.
  artifacts=$(jq -r '.additions[]' "$stage/preview.json")
  promote_args=(--project-root "$project" --stage "$stage")
  while IFS= read -r artifact; do
    promote_args+=(--artifact "$artifact")
  done <<< "$artifacts"
  run bash "$SCRIPT" promote "${promote_args[@]}"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" reimport --source "$GSD_SOURCE" --project-root "$project"
  [ "$status" -eq 0 ]
  jq -e '.status == "unchanged" and .previous_import_id == "re-one"' <<< "$output" >/dev/null

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id re-two
  [ "$status" -eq 0 ]
}

@test "staging fails closed on an invalid adapter output" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"
  bad_source="$TEST_TEMP_DIR/not-gsd"
  mkdir -p "$bad_source"

  run bash "$SCRIPT" stage --adapter gsd --source "$bad_source" --project-root "$project" --import-id bad-import
  [ "$status" -ne 0 ]
  [ ! -e "$project/.lbwc-planning" ]
}

@test "promotion rejects artifacts outside the staged tree allowlist" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project"

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id guard-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/guard-import"

  # config.json is allowlisted, but only as that exact artifact; a traversal or
  # absolute path is still rejected.
  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact '.lbwc-planning/../config.json'
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact '../outside.md'
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact '/absolute.md'
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" promote --project-root "$project" --stage "$stage" --artifact '.lbwc-planning/config.json.md'
  [ "$status" -ne 0 ]
  [ ! -e "$project/.lbwc-planning/config.json" ]
}

@test "failed post-promotion validation rolls back existing and absent files plus provenance" {
  project="$TEST_TEMP_DIR/project"
  mkdir -p "$project/.lbwc-planning"
  printf '%s\n' '# Canonical project' > "$project/.lbwc-planning/PROJECT.md"
  printf '%s\n' '# Canonical state' > "$project/.lbwc-planning/STATE.md"
  before_project=$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')
  before_state=$(shasum -a 256 "$project/.lbwc-planning/STATE.md" | awk '{print $1}')

  run bash "$SCRIPT" stage --adapter gsd --source "$GSD_SOURCE" --project-root "$project" --import-id validate-fail-import
  [ "$status" -eq 0 ]
  stage="$project/.temporary-agent-runfiles/imports/validate-fail-import"

  # Promote existing (PROJECT.md, STATE.md) and absent (REQUIREMENTS.md) artifacts
  # while forcing post-promotion canonical validation to fail.
  run env LBWC_IMPORT_FAIL_VALIDATION=1 bash "$SCRIPT" promote --project-root "$project" --stage "$stage" \
    --artifact .lbwc-planning/PROJECT.md \
    --artifact .lbwc-planning/STATE.md \
    --artifact .lbwc-planning/REQUIREMENTS.md \
    --artifact .lbwc-planning/config.json
  [ "$status" -ne 0 ]
  [[ "$output" == *'post-promotion validation failed'* ]]

  # Existing files restored to their exact prior digests.
  [ "$(shasum -a 256 "$project/.lbwc-planning/PROJECT.md" | awk '{print $1}')" = "$before_project" ]
  [ "$(shasum -a 256 "$project/.lbwc-planning/STATE.md" | awk '{print $1}')" = "$before_state" ]
  # Absent files removed.
  [ ! -e "$project/.lbwc-planning/REQUIREMENTS.md" ]
  [ ! -e "$project/.lbwc-planning/config.json" ]
  # New provenance removed.
  [ ! -e "$project/.lbwc-planning/imports/validate-fail-import/manifest.json" ]
}
