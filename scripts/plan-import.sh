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
FAIL_VALIDATION="${LBWC_IMPORT_FAIL_VALIDATION:-0}"
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
  if [ "$path" = - ]; then
    if command -v shasum >/dev/null 2>&1; then
      digest=$(shasum -a 256 | awk '{print $1}')
    else
      digest=$(sha256sum | awk '{print $1}')
    fi
  elif command -v shasum >/dev/null 2>&1; then
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
  done < <(
    if [ -d "$source" ]; then
      find "$source" -type f -print0 2>/dev/null
    else
      printf '%s\0' "$source"
    fi | LC_ALL=C sort -z
  )
  SOURCE_DIGEST="sha256:$(import_sha256 "$digest_input")"
  rm -f "$digest_input"
  export SOURCE SOURCE_DIGEST SOURCE_FILE_COUNT SOURCE_TOTAL_BYTES
}

validate_ir() {
  local path="$1"
  jq -e -f "$SCRIPT_DIR/../config/import-ir-validator.jq" "$path" >/dev/null \
    || import_fail "normalized import IR is invalid: $path"
}

canonical_source() {
  local source="$1"
  [ ! -L "$source" ] || die "source must not be a symbolic link: $source"
  if [ -d "$source" ]; then
    canonical_directory "$source"
  elif [ -f "$source" ]; then
    canonical_file "$source"
  else
    die "source does not exist: $source"
  fi
}

source_adapter() {
  case "$1" in
    gsd)
      . "$SCRIPT_DIR/import-adapters/lib.sh"
      . "$SCRIPT_DIR/import-adapters/gsd.sh"
      ;;
    markdown)
      . "$SCRIPT_DIR/import-adapters/lib.sh"
      . "$SCRIPT_DIR/import-adapters/markdown.sh"
      ;;
    *)
      import_fail "unsupported import adapter: $1"
      ;;
  esac
}

normalize_source() {
  local adapter="$1" source="$2" output="$3"
  source=$(canonical_source "$source")
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

import_project_name() {
  jq -r '.project.name // "Imported project"' "$1"
}

render_config() {
  local output="$1" defaults validated
  defaults=$("$SCRIPT_DIR/lbwc-config.sh" default-config 2>/dev/null) \
    || import_fail 'could not build canonical configuration defaults'
  validated=$("$SCRIPT_DIR/lbwc-config.sh" validate-config-json <<< "$defaults" 2>/dev/null) \
    || import_fail 'canonical configuration defaults failed repository validation'
  write_text "$output/config.json" "$validated"
}

render_project() {
  local ir="$1" output="$2" name description
  name=$(import_project_name "$ir")
  description=$(jq -r '.project.description // "Imported from an external plan source. See .lbwc-planning/imports/ for provenance."' "$ir")
  write_text "$output/PROJECT.md" "# $name

$description

**Core value:** Unknown; set during the first /lbwc:vibe session.

## Requirements

### Validated
_None yet._

### Active
- [ ] Review imported requirements in REQUIREMENTS.md.

### Out of Scope
- None recorded during import.

## Constraints
- **Imported state**: canonical artifacts below were staged from an external source and promoted explicitly.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Imported external plan | Source digest recorded under .lbwc-planning/imports/ | Pending review |"
}

render_requirements() {
  local ir="$1" output="$2" name lines='' requirement mark id text
  name=$(import_project_name "$ir")
  while IFS= read -r requirement; do
    if [ "$(jq -r '.status // empty' <<< "$requirement")" = complete ]; then mark=x; else mark=' '; fi
    id=$(jq -r '.id' <<< "$requirement")
    text=$(jq -r '.text' <<< "$requirement")
    lines+="- [$mark] **$id**: $text"$'\n'
  done < <(jq -c '.requirements[]' "$ir")
  [ -n "$lines" ] || lines='- [ ] **REQ-00**: No requirements were present in the imported source.'
  write_text "$output/REQUIREMENTS.md" "# $name Requirements

Defined: $(date -u +%Y-%m-%d) | Core value: unknown until the first /lbwc:vibe session

## v1 Requirements

### Imported
${lines%$'\n'}

## Out of Scope

- None recorded during import"
}

render_roadmap() {
  local ir="$1" output="$2" name lines='' phase number slug status goal heading
  name=$(import_project_name "$ir")
  while IFS= read -r phase; do
    slug=$(jq -r '.slug' <<< "$phase")
    status=$(jq -r '.status // "pending"' <<< "$phase")
    goal=$(jq -r 'if (.plans | length) > 0 then .plans[0].title // "Imported phase" else "Imported phase" end' <<< "$phase")
    if [ "$(jq -r '.phase_present' <<< "$phase")" = true ]; then
      number=$(jq -r '.number' <<< "$phase")
      heading="### Phase $number: $slug"
      lines+="$heading"$'\n'
      lines+="**Goal:** $goal"$'\n'
      lines+="**Deps:** none recorded during import"$'\n'
      lines+='**Reqs:** see REQUIREMENTS.md'$'\n'
      lines+="**Success:** unknown; imported status: $status"$'\n\n'
    else
      lines+="## Milestone: $slug"$'\n\n'
    fi
  done < <(jq -c '.phases[] | . + {phase_present:(.number != null)}' "$ir")
  [ -n "$lines" ] || lines='## Phases

- [ ] No phases were present in the imported source.'
  write_text "$output/ROADMAP.md" "# $name Roadmap

Imported from an external plan source; see .lbwc-planning/imports/ for provenance.

${lines%$'\n\n'}"
}

render_state() {
  local ir="$1" output="$2" name decision_rows='' decision total phase_name current plans_total plans_done progress current_phase
  name=$(import_project_name "$ir")
  while IFS= read -r decision; do
    decision_rows+="| $(jq -r '.text | gsub("\\|"; "\\|")' <<< "$decision") | $(date -u +%Y-%m-%d) | imported |"$'\n'
  done < <(jq -c '.decisions[]' "$ir")
  [ -n "$decision_rows" ] || decision_rows='| _(No decisions yet)_ | | |'
  total=$(jq -r '[.phases[] | select(.number != null)] | length' "$ir")
  current_phase=$(jq -r '[.phases[] | select(.number != null)] | sort_by(.number) | .[0].number // 1' "$ir")
  phase_name=$(jq -r --argjson current "$current_phase" '[.phases[] | select(.number == $current)][0].slug // "none"' "$ir")
  plans_total=$(jq -r --argjson current "$current_phase" '[.phases[] | select(.number == $current)][0].plans | if . == null then 0 else length end' "$ir")
  plans_done=$(jq -r --argjson current "$current_phase" '[.phases[] | select(.number == $current)][0].plans | if . == null then 0 else ([.[] | select(.summary_present == true)] | length) end' "$ir")
  if [ "$plans_total" -gt 0 ]; then progress=$((plans_done * 100 / plans_total)); else progress=0; fi
  write_text "$output/STATE.md" "# State

**Project:** $name

## Current Phase
Phase: $current_phase of $total ($phase_name)
Plans: $plans_done/$plans_total
Progress: $progress%
Status: ready

## Key Decisions

| Decision | Date | Rationale |
|----------|------|-----------|
${decision_rows%$'\n'}

## Todos
_(None)_

## Blockers
_(None)_

## Activity Log
- $(date -u +%Y-%m-%d): Imported external plan source"
}

render_plan_document() {
  local ir="$1" plan_json="$2" number title source_path status warning='' content heading
  number=$(jq -r 'if .number == null then 1 else .number end' <<< "$plan_json")
  title=$(jq -r '.title // "Imported plan"' <<< "$plan_json")
  source_path=$(jq -r '.source_path' <<< "$plan_json")
  status=$(jq -r '.status // "unknown"' <<< "$plan_json")
  if [ "$(jq -r '.source.system' "$ir")" = markdown ]; then
    warning=$'\n'"WARNING: unverified generic Markdown import; status and dependencies are unknown."$'\n'
  fi
  content=$(jq -r '.content // ""' <<< "$plan_json")
  heading=$(import_adapter_read_heading - <<< "$content" || true)
  if [ -n "$content" ] && [ "$heading" != "$title" ]; then
    content=$'# '"$title"$'\n\n'"$content"
  fi
  [ -n "$content" ] || content="# $title"
  write_text "$3" "---
phase: $(jq -r 'if .phase == null then 1 else .phase end' <<< "$plan_json")
plan: $number
title: $title
type: execute
wave: 1

depends_on: []
cross_phase_deps: []

autonomous: true
effort_override: balanced

strategy_rationale: \"Imported plan; review before execution.\"
validation:
  riskiest_assumption: \"\"
  mvp_slice: \"\"
  metric: \"\"
  decision_rule: \"\"

skills_used: []
files_modified: []
files_touched: []
forbidden_commands: []

must_haves:
  truths: [\"Imported plan content stays reviewable before execution\"]
  artifacts: []
  key_links: []
---
<objective>
Imported plan from $source_path. Review before execution.
</objective>
<context>
Source status: $status$warning
</context>
<tasks>
<task type=\"auto\">
  <name>review-imported-plan</name>
  <files>
    $source_path
  </files>
  <strategy>spike</strategy>
  <estimate>1-2h</estimate>
  <depends_on>[]</depends_on>
  <action>
Review the imported plan content below and reconcile it with the project roadmap before executing any work.
  </action>
  <verify>
The imported content matches the source artifact and the reviewer has accepted or rewritten it.
  </verify>
  <done>
Imported content is reviewed and either accepted or replaced.
  </done>
</task>
</tasks>
<verification>
1. Imported content matches the source artifact.
</verification>
<success_criteria>
- Imported plan reviewed
</success_criteria>
<output>
${number}-SUMMARY.md
</output>

## Imported content

$content"
}

render_plans() {
  local ir="$1" output="$2" plan destination phase_dir_name source_path base phase_slug
  while IFS= read -r plan; do
    source_path=$(jq -r '.source_path' <<< "$plan")
    if [ "$(jq -r '.phase != null' <<< "$plan")" = true ]; then
      phase_slug=$(jq -r --argjson n "$(jq -r '.phase' <<< "$plan")" \
        '[.phases[] | select(.number == $n)][0].slug // "imported"' "$ir")
      phase_dir_name=$(printf '%02d-%s' "$(jq -r '.phase' <<< "$plan")" "$phase_slug")
      destination="$output/phases/$phase_dir_name/$(printf '%02d-%02d-PLAN.md' "$(jq -r '.phase' <<< "$plan")" "$(jq -r 'if .number == null then 1 else .number end' <<< "$plan")")"
      if [ "$(jq -r '.summary_present // false' <<< "$plan")" = true ]; then
        summary_destination="${destination%-PLAN.md}-SUMMARY.md"
        write_text "$summary_destination" "# $(jq -r '.title // "Imported plan"' <<< "$plan") Summary

Result: complete (imported; source summary presence detected by the verified adapter)

Source: $source_path"
      fi
    else
      base=$(basename "$source_path" .md)
      destination="$output/imported-markdown/$(printf '%s' "$base" | tr '/ ' '__').md"
    fi
    render_plan_document "$ir" "$plan" "$destination"
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
  render_config "$tree/.lbwc-planning"
  render_plans "$ir" "$tree/.lbwc-planning"
}

semantic_conflicts() {
  local ir="$1" tree="$2" project_root="$3" conflicts='[]' path relative source_digest destination_digest status_detail
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    relative="${path#"$tree/"}"
    [ -f "$project_root/$relative" ] || continue
    source_digest=$(import_sha256 "$path") || import_fail "could not digest staged artifact: $relative"
    destination_digest=$(import_sha256 "$project_root/$relative") || import_fail "could not digest canonical artifact: $relative"
    [ "$source_digest" = "$destination_digest" ] && continue
    status_detail=''
    case "$relative" in
      .lbwc-planning/REQUIREMENTS.md)
        status_detail=$(jq -c -R -s '
          [split("\n")[] | select(test("^- \\[[xX ]\\] \\*\\*")) | (match("^- \\[(?<mark>[xX ])\\] \\*\\*(?<id>[^*]+)\\*\\*").captures | map({key: .name, value: .string}) | from_entries) | {key: .id, value: {id: .id, status: (if .mark == "x" or .mark == "X" then "complete" else "pending" end)}}] | from_entries | [.[]]' "$project_root/$relative" 2>/dev/null || printf '[]')
        status_detail=$(jq -c --argjson existing "${status_detail:-[]}" '
          [.requirements[] | {id, status: (.status // "pending")}] as $imported
          | {removed_ids: ([$existing[] | .id] - [$imported[] | .id]),
             changed_statuses: [$imported[] | . as $p | ($existing[] | select(.id == $p.id)) as $e | select($e != null and $e.status != $p.status) | {id: $p.id, status: $p.status}]}' "$ir" 2>/dev/null || printf '{}')
        ;;
      .lbwc-planning/ROADMAP.md)
        status_detail=$(jq -c '{imported_phases: [.phases[] | select(.number != null) | .number]}' "$ir" 2>/dev/null || printf '{}')
        ;;
    esac
    conflicts=$(jq -c --arg artifact "$relative" --arg source_digest "$source_digest" --arg destination_digest "$destination_digest" --argjson detail "${status_detail:-{\}}" \
      '. + [{artifact:$artifact, source_digest:$source_digest, destination_digest:$destination_digest, detail:$detail}]' <<< "$conflicts")
  done < <(find "$tree" -type f -print 2>/dev/null | LC_ALL=C sort)
  printf '%s\n' "$conflicts"
}

preview_json() {
  local ir="$1" project_root="$2" import_id="$3" tree="$4" existing='[]' additions='[]' path destination conflicts
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    destination="${path#"$tree/"}"
    if [ -e "$project_root/$destination" ]; then
      existing=$(jq -c --arg path "$destination" '. + [$path]' <<< "$existing")
    else
      additions=$(jq -c --arg path "$destination" '. + [$path]' <<< "$additions")
    fi
  done < <(find "$tree" -type f -print 2>/dev/null | LC_ALL=C sort)
  conflicts=$(semantic_conflicts "$ir" "$tree" "$project_root")
  jq -n --argjson source "$(cat "$ir")" --arg id "$import_id" --arg tree "$tree" \
    --argjson additions "$additions" --argjson overlaps "$existing" --argjson conflicts "$conflicts" \
    '{schema_version:1,import_id:$id,source:$source.source,proposed_destination:".lbwc-planning/",additions:$additions,overlaps:$overlaps,conflicts:$conflicts,unknowns:($source.warnings + [($source.plans[] | select(.status == null) | .source_path)]),skipped:($source.source.skipped_files // []),staged_tree:$tree}'
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
    --arg source_path "$source" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:1,import_id:$id,adapter:$adapter,source_digest:$digest,source:{source_path:$source_path},created_at:$created_at,status:"staged"}')
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
  for expected in PROJECT.md REQUIREMENTS.md ROADMAP.md STATE.md config.json; do
    [ -f "$tree/.lbwc-planning/$expected" ] || import_fail "staged canonical artifact is missing: $expected"
  done
  "$SCRIPT_DIR/lbwc-config.sh" validate-config-json < "$tree/.lbwc-planning/config.json" >/dev/null \
    || import_fail 'staged canonical configuration is invalid'
  while IFS= read -r path; do
    [ ! -L "$path" ] || import_fail "staged tree contains a symbolic link: $path"
  done < <(find "$tree" -print 2>/dev/null)
  jq -n --arg stage "$stage" --argjson additions "$(jq '.additions' "$stage/preview.json")" \
    --argjson overlaps "$(jq '.overlaps' "$stage/preview.json")" \
    --argjson conflicts "$(jq '.conflicts // []' "$stage/preview.json")" \
    --argjson unknowns "$(jq '.unknowns' "$stage/preview.json")" \
    --argjson skipped "$(jq '.skipped' "$stage/preview.json")" \
    '{status:"valid",stage:$stage,complete:true,additions:$additions,overlaps:$overlaps,conflicts:$conflicts,unknowns:$unknowns,skipped:$skipped}'
}

reimport_status() {
  local source="$1" project_root="$2" digest stage manifest found=''
  project_root=$(canonical_directory "$project_root")
  source=$(canonical_source "$source")
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
  [[ "$artifact" != /* && "$artifact" != ../* && "$artifact" != */../* && "$artifact" != */.. && "$artifact" != *"//"* ]] || return 1
  case "$artifact" in
    .lbwc-planning/config.json)
      return 0
      ;;
  esac
  [[ "$artifact" == *.md ]] || return 1
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
    [ ! -e "$current" ] && continue
    [ ! -L "$current" ] || import_fail "canonical destination contains a symbolic link: $artifact"
  done
}

promote_import() {
  local project_root="$1" stage="$2" ir tree artifact source destination backup_root destination_tmp count=0 manifest_dir provenance_tmp
  project_root=$(canonical_directory "$project_root")
  stage=$(canonical_directory "$stage")
  validate_stage "$project_root" "$stage" >/dev/null
  tree="$stage/tree"
  ir="$stage/ir.json"
  [ "${#ARTIFACTS[@]}" -gt 0 ] || import_fail 'promotion requires explicit --artifact input'

  local staged_source_path staged_digest
  staged_source_path=$(jq -r '.source.source_path // empty' "$stage/manifest.json" 2>/dev/null || true)
  staged_digest=$(jq -r '.source.digest' "$ir")
  if [ -n "$staged_source_path" ]; then
    import_source_metadata "$(canonical_source "$staged_source_path")"
    [ "$SOURCE_DIGEST" = "$staged_digest" ] || import_fail "source changed after staging; cancel and re-stage"
  fi

  local imports_parent="$project_root/.lbwc-planning/imports" planning_dir="$project_root/.lbwc-planning"
  local imports_parent_existed=false planning_existed=false
  [ -d "$imports_parent" ] && imports_parent_existed=true
  [ -d "$planning_dir" ] && planning_existed=true

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
      rm -f "$(dirname "$rollback_destination")/.$(basename "$rollback_destination").import.$$"
      if [ "$(cat "$backup_root/$rollback_key.state")" = present ]; then
        cp -p "$backup_root/$rollback_key" "$rollback_destination"
      else
        rm -f "$rollback_destination"
      fi
    done
    rm -rf "$manifest_dir"
    # Invariant: remove a directory only if this transaction created it and it is empty.
    if [ "$imports_parent_existed" = false ]; then
      rmdir "$imports_parent" 2>/dev/null || true
    fi
    if [ "$planning_existed" = false ]; then
      rmdir "$planning_dir" 2>/dev/null || true
    fi
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
  manifest_dir="$imports_parent/$(basename "$stage")"
  provenance_tmp="$stage/.provenance-tmp.$$"
  rm -rf "$provenance_tmp"
  if ! mkdir -p "$provenance_tmp" \
    || ! cp -p "$ir" "$provenance_tmp/ir.json" \
    || ! cp -p "$stage/preview.json" "$provenance_tmp/preview.json" \
    || ! jq --arg status promoted '.status = $status' "$stage/manifest.json" > "$provenance_tmp/manifest.json"; then
    rm -rf "$provenance_tmp"
    rollback_promote
    import_fail "promotion provenance preparation failed; rollback restored canonical artifacts"
  fi
  mkdir -p "$imports_parent"
  rm -rf "$manifest_dir"
  if ! mv "$provenance_tmp" "$manifest_dir"; then
    rm -rf "$provenance_tmp"
    rollback_promote
    import_fail "promotion provenance persistence failed; rollback restored canonical artifacts"
  fi

  local validation_output validation_failed=''
  if [ "$FAIL_VALIDATION" = 1 ]; then
    validation_failed="post-promotion validation failed: forced validation failure"
  elif ! printf '%s\n' "${ARTIFACTS[@]}" | grep -qx '.lbwc-planning/config.json'; then
    validation_failed="post-promotion validation failed: canonical artifact .lbwc-planning/config.json was not selected for promotion"
  else
    validation_output=$(LBWC_PLANNING_DIR="$planning_dir" "$SCRIPT_DIR/lbwc-config.sh" validate-config-json < "$planning_dir/config.json" 2>&1) \
      || validation_failed="post-promotion validation failed: lbwc-config.sh validate-config-json: $validation_output"
    if [ -z "$validation_failed" ]; then
      validation_output=$(cd "$project_root" && LBWC_PLANNING_DIR="$planning_dir" bash "$SCRIPT_DIR/verify-state-consistency.sh" 2>&1) \
        || validation_failed="post-promotion validation failed: verify-state-consistency.sh: $validation_output"
    fi
  fi
  if [ -n "$validation_failed" ]; then
    rollback_promote
    import_fail "$validation_failed; rollback restored canonical artifacts and removed provenance"
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
    SOURCE=$(canonical_source "$SOURCE")
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
