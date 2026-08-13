#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_ROOT=""
SOURCE=""
OUTPUT=""
ADAPTER=""
IMPORT_ID=""
STAGE=""
FAIL_AFTER="${LBWC_IMPORT_FAIL_AFTER:-0}"
ARTIFACTS=()

die() {
  printf 'plan-import: %s\n' "$1" >&2
  exit 1
}

import_fail() {
  die "$1"
}

usage() {
  printf '%s\n' \
    'Usage: plan-import.sh <normalize|digest|stage|validate-stage|reimport|promote> [options]' \
    '  normalize --adapter gsd|markdown --source PATH --output PATH' \
    '  digest --source PATH --output PATH' \
    '  stage --adapter gsd|markdown --source PATH --project-root PATH --import-id ID' \
    '  validate-stage --project-root PATH --stage PATH' \
    '  reimport --source PATH --project-root PATH' \
    '  promote --project-root PATH --stage PATH --artifact PATH [--artifact PATH ...]'
}

valid_import_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

canonical_directory() {
  local path="$1"
  [ -d "$path" ] || die "directory does not exist: $path"
  [ ! -L "$path" ] || die "directory must not be a symbolic link: $path"
  (cd -P "$path" && pwd -P)
}

canonical_file() {
  local path="$1"
  [ -f "$path" ] || die "file does not exist: $path"
  [ ! -L "$path" ] || die "file must not be a symbolic link: $path"
  (cd -P "$(dirname "$path")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")")
}

import_file_size() {
  local path="$1" size
  size=$(stat -f '%z' "$path" 2>/dev/null || true)
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size=$(stat -c '%s' "$path" 2>/dev/null || true)
  fi
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$size"
}

import_sha256() {
  local path="$1" digest
  if command -v shasum >/dev/null 2>&1; then
    digest=$(shasum -a 256 "$path" | awk '{print $1}')
  else
    digest=$(sha256sum "$path" | awk '{print $1}')
  fi
  [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

import_source_metadata() {
  local source="$1" path relative file_digest digest_input
  SOURCE="$source"
  SOURCE_FILE_COUNT=0
  SOURCE_TOTAL_BYTES=0
  digest_input=$(mktemp "${TMPDIR:-/tmp}/lbwc-import-digest.XXXXXX") || import_fail 'could not create source digest workspace'
  if find "$source" -type l -print -quit 2>/dev/null | grep -q .; then
    rm -f "$digest_input"
    import_fail "source contains a symbolic link"
  fi
  while IFS= read -r -d '' path; do
    [ ! -L "$path" ] || { rm -f "$digest_input"; import_fail "source contains a symbolic link: $path"; }
    relative=${path#"$source"/}
    file_digest=$(import_sha256 "$path") || { rm -f "$digest_input"; import_fail "could not digest source file: $path"; }
    printf '%s\t%s\n' "$relative" "$file_digest" >> "$digest_input"
    SOURCE_FILE_COUNT=$((SOURCE_FILE_COUNT + 1))
    SOURCE_TOTAL_BYTES=$((SOURCE_TOTAL_BYTES + $(import_file_size "$path")))
  done < <(find "$source" -type f -print0 2>/dev/null | LC_ALL=C sort -z)
  SOURCE_DIGEST="sha256:$(import_sha256 "$digest_input")"
  rm -f "$digest_input"
  export SOURCE SOURCE_DIGEST SOURCE_FILE_COUNT SOURCE_TOTAL_BYTES
}

validate_ir() {
  local path="$1"
  jq -e -f "$SCRIPT_DIR/../config/import-ir-validator.jq" "$path" >/dev/null \
    || import_fail "normalized import IR is invalid: $path"
}

source_adapter() {
  case "$1" in
    gsd)
      . "$SCRIPT_DIR/import-adapters/gsd.sh"
      ;;
    markdown)
      . "$SCRIPT_DIR/import-adapters/markdown.sh"
      ;;
    *)
      import_fail "unsupported import adapter: $1"
      ;;
  esac
}

normalize_source() {
  local adapter="$1" source="$2" output="$3"
  source=$(canonical_directory "$source")
  mkdir -p "$(dirname "$output")"
  output="$(cd -P "$(dirname "$output")" && pwd -P)/$(basename "$output")"
  source_adapter "$adapter"
  import_source_metadata "$source"
  case "$adapter" in
    gsd) import_adapter_gsd_normalize "$source" "$output" ;;
    markdown) import_adapter_markdown_normalize "$source" "$output" ;;
  esac
  validate_ir "$output"
}

write_text() {
  local path="$1" value="$2" temporary
  mkdir -p "$(dirname "$path")"
  temporary="$(dirname "$path")/.$(basename "$path").tmp.$$"
  printf '%s\n' "$value" > "$temporary"
  mv -f "$temporary" "$path"
}

render_project() {
  local ir="$1" output="$2" name description
  name=$(jq -r '.project.name // "Unknown project"' "$ir")
  description=$(jq -r '.project.description // "Unknown"' "$ir")
  write_text "$output/PROJECT.md" "# $name

$description"
}

render_requirements() {
  local ir="$1" output="$2" lines=''
  while IFS= read -r requirement; do
    lines+="- [?] $(jq -r '.id + ": " + .text' <<< "$requirement")"$'\n'
  done < <(jq -c '.requirements[]' "$ir")
  [ -n "$lines" ] || lines='Unknown requirements.'
  write_text "$output/REQUIREMENTS.md" "# Requirements

${lines%$'\n'}"
}

render_roadmap() {
  local ir="$1" output="$2" lines='# Roadmap' milestone phase
  while IFS= read -r milestone; do
    lines+=$'\n\n## '
    lines+="$(jq -r '.name' <<< "$milestone")"
  done < <(jq -c '.milestones[]' "$ir")
  while IFS= read -r phase; do
    lines+=$'\n\n### '
    lines+="$(jq -r 'if .number == null then .slug else ((.number|tostring) + ": " + .slug) end' <<< "$phase")"
    lines+=$'\nStatus: '
    lines+="$(jq -r '.status // "Unknown"' <<< "$phase")"
  done < <(jq -c '.phases[]' "$ir")
  write_text "$output/ROADMAP.md" "$lines"
}

render_state() {
  local ir="$1" output="$2" lines='# State

## Key Decisions' decision
  while IFS= read -r decision; do
    lines+=$'\n\n- '
    lines+="$(jq -r '.text' <<< "$decision")"
  done < <(jq -c '.decisions[]' "$ir")
  [ "$lines" != '# State

## Key Decisions' ] || lines+=$'\n\nUnknown.'
  write_text "$output/STATE.md" "$lines"
}

render_plans() {
  local ir="$1" output="$2" plan destination title status source_path
  while IFS= read -r plan; do
    source_path=$(jq -r '.source_path' <<< "$plan")
    title=$(jq -r '.title // "Unknown plan"' <<< "$plan")
    status=$(jq -r '.status // "Unknown"' <<< "$plan")
    if [ "$(jq -r '.phase // empty' <<< "$plan")" != "" ]; then
      destination="$output/phases/$(jq -r 'if .phase == null then "unknown" else ((.phase|tostring) + "-imported") end' <<< "$plan")/$(jq -r 'if .number == null then "PLAN" else ((.phase|tostring) + "-" + (.number|tostring)) end' <<< "$plan")-PLAN.md"
    else
      destination="$output/imported-markdown/$(printf '%s' "$source_path" | tr '/ ' '__')"
      destination="${destination%.md}.md"
    fi
    write_text "$destination" "# $title

Status: $status

Source: $source_path"
  done < <(jq -c '.plans[]' "$ir")
}

render_tree() {
  local ir="$1" tree="$2"
  rm -rf "$tree"
  mkdir -p "$tree/.lbwc-planning"
  render_project "$ir" "$tree/.lbwc-planning"
  render_requirements "$ir" "$tree/.lbwc-planning"
  render_roadmap "$ir" "$tree/.lbwc-planning"
  render_state "$ir" "$tree/.lbwc-planning"
  render_plans "$ir" "$tree/.lbwc-planning"
}

preview_json() {
  local ir="$1" project_root="$2" import_id="$3" tree="$4" existing='[]' additions='[]' path destination
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    destination="${path#"$tree/"}"
    if [ -e "$project_root/$destination" ]; then
      existing=$(jq -c --arg path "$destination" '. + [$path]' <<< "$existing")
    else
      additions=$(jq -c --arg path "$destination" '. + [$path]' <<< "$additions")
    fi
  done < <(find "$tree" -type f -print 2>/dev/null | LC_ALL=C sort)
  jq -n --argjson source "$(cat "$ir")" --arg id "$import_id" --arg tree "$tree" \
    --argjson additions "$additions" --argjson overlaps "$existing" \
    '{schema_version:1,import_id:$id,source:$source.source,proposed_destination:".lbwc-planning/",additions:$additions,overlaps:$overlaps,unknowns:($source.warnings + [($source.plans[] | select(.status == null) | .source_path)]),skipped:($source.source.skipped_files // []),staged_tree:$tree}'
}

stage_import() {
  local adapter="$1" source="$2" project_root="$3" import_id="$4" run_root ir tree preview manifest
  project_root=$(canonical_directory "$project_root")
  valid_import_id "$import_id" || import_fail "invalid import id: $import_id"
  run_root="$project_root/.temporary-agent-runfiles/imports/$import_id"
  [ ! -e "$run_root" ] || import_fail "import staging directory already exists: $run_root"
  mkdir -p "$run_root"
  ir="$run_root/ir.json"
  tree="$run_root/tree"
  normalize_source "$adapter" "$source" "$ir"
  render_tree "$ir" "$tree"
  preview=$(preview_json "$ir" "$project_root" "$import_id" "$tree")
  printf '%s\n' "$preview" > "$run_root/preview.json"
  manifest=$(jq -n --arg id "$import_id" --arg digest "$(jq -r '.source.digest' "$ir")" --arg adapter "$adapter" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:1,import_id:$id,adapter:$adapter,source_digest:$digest,created_at:$created_at,status:"staged"}')
  printf '%s\n' "$manifest" > "$run_root/manifest.json"
  jq -n --arg stage "$run_root" --argjson preview "$preview" '{stage:$stage,preview:$preview}'
}

validate_stage() {
  local project_root="$1" stage="$2" ir tree expected path
  project_root=$(canonical_directory "$project_root")
  stage=$(canonical_directory "$stage")
  tree="$stage/tree"
  ir="$stage/ir.json"
  [ "$stage" = "$project_root/.temporary-agent-runfiles/imports/$(basename "$stage")" ] || import_fail 'stage is outside the project import staging directory'
  [ -f "$ir" ] || import_fail 'staged IR is missing'
  [ -d "$tree/.lbwc-planning" ] || import_fail 'staged canonical tree is missing'
  validate_ir "$ir"
  for expected in PROJECT.md REQUIREMENTS.md ROADMAP.md STATE.md; do
    [ -f "$tree/.lbwc-planning/$expected" ] || import_fail "staged canonical artifact is missing: $expected"
  done
  while IFS= read -r path; do
    [ ! -L "$path" ] || import_fail "staged tree contains a symbolic link: $path"
  done < <(find "$tree" -print 2>/dev/null)
  jq -n --arg stage "$stage" --arg digest "$(jq -r '.source.digest' "$ir")" \
    '{status:"valid",stage:$stage,source_digest:$digest,complete:true}'
}

reimport_status() {
  local source="$1" project_root="$2" digest stage manifest found=''
  project_root=$(canonical_directory "$project_root")
  source=$(canonical_directory "$source")
  import_source_metadata "$source"
  if [ -d "$project_root/.lbwc-planning/imports" ]; then
    while IFS= read -r manifest; do
      [ -n "$manifest" ] || continue
      if [ "$(jq -r '.source_digest // empty' "$manifest" 2>/dev/null || true)" = "$SOURCE_DIGEST" ]; then
        found="$manifest"
        break
      fi
    done < <(find "$project_root/.lbwc-planning/imports" -type f -name manifest.json -print 2>/dev/null | LC_ALL=C sort)
  fi
  if [ -z "$found" ] && [ -d "$project_root/.temporary-agent-runfiles/imports" ]; then
    while IFS= read -r manifest; do
      [ -n "$manifest" ] || continue
      if [ "$(jq -r '.source_digest // empty' "$manifest" 2>/dev/null || true)" = "$SOURCE_DIGEST" ]; then
        found="$manifest"
        break
      fi
    done < <(find "$project_root/.temporary-agent-runfiles/imports" -type f -name manifest.json -print 2>/dev/null | LC_ALL=C sort)
  fi
  if [ -n "$found" ]; then
    jq -n --arg digest "$SOURCE_DIGEST" --arg id "$(jq -r '.import_id' "$found")" '{status:"unchanged",source_digest:$digest,previous_import_id:$id}'
  else
    jq -n --arg digest "$SOURCE_DIGEST" '{status:"changed-or-new",source_digest:$digest,previous_import_id:null}'
  fi
}

safe_artifact() {
  local artifact="$1"
  [[ "$artifact" == *.md ]] || return 1
  [[ "$artifact" != /* && "$artifact" != ../* && "$artifact" != */../* && "$artifact" != */.. && "$artifact" != *"//"* ]] || return 1
  case "$artifact" in
    .lbwc-planning/PROJECT.md|.lbwc-planning/REQUIREMENTS.md|.lbwc-planning/ROADMAP.md|.lbwc-planning/STATE.md|.lbwc-planning/phases/*.md|.lbwc-planning/phases/*/*.md|.lbwc-planning/imported-markdown/*.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_no_symlink_components() {
  local project_root="$1" artifact="$2" current="$project_root" component
  IFS='/' read -r -a components <<< "$artifact"
  for component in "${components[@]}"; do
    current="$current/$component"
    [ ! -L "$current" ] || import_fail "canonical destination contains a symbolic link: $artifact"
  done
}

promote_import() {
  local project_root="$1" stage="$2" ir tree artifact source destination backup_root backup destination_tmp count=0 committed=0 manifest_dir
  project_root=$(canonical_directory "$project_root")
  stage=$(canonical_directory "$stage")
  validate_stage "$project_root" "$stage" >/dev/null
  tree="$stage/tree"
  ir="$stage/ir.json"
  [ "${#ARTIFACTS[@]}" -gt 0 ] || import_fail 'promotion requires explicit --artifact input'
  backup_root="$stage/rollback"
  rm -rf "$backup_root"
  mkdir -p "$backup_root"
  for artifact in "${ARTIFACTS[@]}"; do
    safe_artifact "$artifact" || import_fail "invalid promotion artifact: $artifact"
    source="$tree/$artifact"
    destination="$project_root/$artifact"
    [ -f "$source" ] || import_fail "staged artifact is missing: $artifact"
    assert_no_symlink_components "$project_root" "$artifact"
    mkdir -p "$(dirname "$destination")"
    if [ -e "$destination" ]; then
      [ ! -L "$destination" ] || import_fail "canonical destination is a symbolic link: $artifact"
      cp -p "$destination" "$backup_root/$(printf '%s' "$artifact" | tr '/' '__')"
      printf '%s\n' present > "$backup_root/$(printf '%s' "$artifact" | tr '/' '__').state"
    else
      printf '%s\n' absent > "$backup_root/$(printf '%s' "$artifact" | tr '/' '__').state"
    fi
  done
  rollback_promote() {
    local rollback_artifact rollback_destination rollback_key
    for rollback_artifact in "${ARTIFACTS[@]}"; do
      rollback_destination="$project_root/$rollback_artifact"
      rollback_key=$(printf '%s' "$rollback_artifact" | tr '/' '__')
      if [ "$(cat "$backup_root/$rollback_key.state")" = present ]; then
        cp -p "$backup_root/$rollback_key" "$rollback_destination"
      else
        rm -f "$rollback_destination"
      fi
    done
  }
  for artifact in "${ARTIFACTS[@]}"; do
    source="$tree/$artifact"
    destination="$project_root/$artifact"
    destination_tmp="$(dirname "$destination")/.$(basename "$destination").import.$$"
    if ! cp -p "$source" "$destination_tmp" || ! mv -f "$destination_tmp" "$destination"; then
      rm -f "$destination_tmp"
      rollback_promote
      import_fail "promotion failed at artifact $artifact; rollback restored canonical artifacts"
    fi
    count=$((count + 1))
    if [ "$FAIL_AFTER" -gt 0 ] && [ "$count" -ge "$FAIL_AFTER" ]; then
      rollback_promote
      import_fail "promotion failed after artifact $artifact; rollback restored canonical artifacts"
    fi
  done
  manifest_dir="$project_root/.lbwc-planning/imports/$(basename "$stage")"
  if ! mkdir -p "$manifest_dir" \
    || ! cp -p "$ir" "$manifest_dir/ir.json" \
    || ! cp -p "$stage/preview.json" "$manifest_dir/preview.json" \
    || ! jq --arg status promoted '.status = $status' "$stage/manifest.json" > "$manifest_dir/manifest.json"; then
    rm -rf "$manifest_dir"
    rollback_promote
    import_fail "promotion provenance persistence failed; rollback restored canonical artifacts"
  fi
  jq -n --arg status promoted --argjson artifacts "$(printf '%s\n' "${ARTIFACTS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    '{status:$status,artifacts:$artifacts}'
}

COMMAND="${1:-}"
[ -n "$COMMAND" ] || { usage >&2; exit 2; }
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --adapter) [ "$#" -ge 2 ] || die '--adapter requires a value'; ADAPTER="$2"; shift 2 ;;
    --source) [ "$#" -ge 2 ] || die '--source requires a path'; SOURCE="$2"; shift 2 ;;
    --output) [ "$#" -ge 2 ] || die '--output requires a path'; OUTPUT="$2"; shift 2 ;;
    --project-root) [ "$#" -ge 2 ] || die '--project-root requires a path'; PROJECT_ROOT="$2"; shift 2 ;;
    --import-id) [ "$#" -ge 2 ] || die '--import-id requires a value'; IMPORT_ID="$2"; shift 2 ;;
    --stage) [ "$#" -ge 2 ] || die '--stage requires a path'; STAGE="$2"; shift 2 ;;
    --artifact) [ "$#" -ge 2 ] || die '--artifact requires a path'; ARTIFACTS+=("$2"); shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "$COMMAND" in
  normalize)
    [ -n "$ADAPTER" ] && [ -n "$SOURCE" ] && [ -n "$OUTPUT" ] || die 'normalize requires --adapter, --source, and --output'
    normalize_source "$ADAPTER" "$SOURCE" "$OUTPUT"
    ;;
  digest)
    [ -n "$SOURCE" ] && [ -n "$OUTPUT" ] || die 'digest requires --source and --output'
    SOURCE=$(canonical_directory "$SOURCE")
    import_source_metadata "$SOURCE"
    mkdir -p "$(dirname "$OUTPUT")"
    jq -n --arg digest "$SOURCE_DIGEST" --argjson file_count "$SOURCE_FILE_COUNT" --argjson total_bytes "$SOURCE_TOTAL_BYTES" \
      '{schema_version:1,digest:$digest,file_count:$file_count,total_bytes:$total_bytes}' > "$OUTPUT"
    ;;
  stage)
    [ -n "$ADAPTER" ] && [ -n "$SOURCE" ] && [ -n "$PROJECT_ROOT" ] && [ -n "$IMPORT_ID" ] || die 'stage requires --adapter, --source, --project-root, and --import-id'
    stage_import "$ADAPTER" "$SOURCE" "$PROJECT_ROOT" "$IMPORT_ID"
    ;;
  validate-stage)
    [ -n "$PROJECT_ROOT" ] && [ -n "$STAGE" ] || die 'validate-stage requires --project-root and --stage'
    validate_stage "$PROJECT_ROOT" "$STAGE"
    ;;
  reimport)
    [ -n "$SOURCE" ] && [ -n "$PROJECT_ROOT" ] || die 'reimport requires --source and --project-root'
    reimport_status "$SOURCE" "$PROJECT_ROOT"
    ;;
  promote)
    [ -n "$PROJECT_ROOT" ] && [ -n "$STAGE" ] || die 'promote requires --project-root and --stage'
    promote_import "$PROJECT_ROOT" "$STAGE"
    ;;
  *) usage >&2; exit 2 ;;
esac
