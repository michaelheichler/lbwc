#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/lib/plan-source-adapters.sh"

GENERIC_CAP=64
CLAUDE_CAP=16
DISPLAY_CAP=3
MAX_FILE_BYTES=1048576
GENERIC_MAX_TOTAL_BYTES=8388608
CLAUDE_MAX_TOTAL_BYTES=4194304
PROJECT_ROOT_ARG=""
RUN_ROOT_ARG=""
PLAN_ARG=""
INSTRUCTION=""
INSTRUCTION_SET=false
SETTINGS_ARG=""

usage() {
  printf '%s\n' \
    'Usage: team-context-index.sh --project-root PATH --run-root PATH [options]' \
    '  --plan PATH' \
    '  --instruction TEXT' \
    '  --settings PATH'
}

fail() {
  printf 'team-context-index: %s\n' "$1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || fail '--project-root requires a path'
      PROJECT_ROOT_ARG="$2"
      shift 2
      ;;
    --run-root)
      [ "$#" -ge 2 ] || fail '--run-root requires a path'
      RUN_ROOT_ARG="$2"
      shift 2
      ;;
    --plan)
      [ "$#" -ge 2 ] || fail '--plan requires a path'
      PLAN_ARG="$2"
      shift 2
      ;;
    --instruction)
      [ "$#" -ge 2 ] || fail '--instruction requires text'
      INSTRUCTION="$2"
      INSTRUCTION_SET=true
      shift 2
      ;;
    --settings)
      [ "$#" -ge 2 ] || fail '--settings requires a path'
      SETTINGS_ARG="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
done

[ -n "$PROJECT_ROOT_ARG" ] || fail '--project-root is required'
[ -n "$RUN_ROOT_ARG" ] || fail '--run-root is required'
[ -d "$PROJECT_ROOT_ARG" ] || fail "project root does not exist: $PROJECT_ROOT_ARG"
[ -d "$RUN_ROOT_ARG" ] || fail "run root does not exist: $RUN_ROOT_ARG"
[ ! -L "$RUN_ROOT_ARG" ] || fail 'run root must not be a symbolic link'

PROJECT_ROOT=$(cd "$PROJECT_ROOT_ARG" && pwd -P)
RUN_ROOT=$(cd "$RUN_ROOT_ARG" && pwd -P)
RUN_PARENT=$(dirname "$RUN_ROOT")
RUN_PARENT_PARENT=$(dirname "$RUN_PARENT")
[ "$RUN_PARENT" = "$PROJECT_ROOT/.temporary-agent-runfiles/runs" ] || fail 'run root is outside the project temporary run directory'
[ "$RUN_PARENT_PARENT" = "$PROJECT_ROOT/.temporary-agent-runfiles" ] || fail 'run root is outside the project temporary run directory'

if [ -n "$SETTINGS_ARG" ]; then
  [ -f "$SETTINGS_ARG" ] || fail "settings file does not exist: $SETTINGS_ARG"
  SETTINGS_PATH=$(cd "$(dirname "$SETTINGS_ARG")" && pwd -P)/$(basename "$SETTINGS_ARG")
else
  SETTINGS_PATH="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
fi

if [ -n "$PLAN_ARG" ]; then
  [ -f "$PLAN_ARG" ] || fail "explicit plan does not exist: $PLAN_ARG"
  EXPLICIT_PLAN=$(plan_source_canonical_file "$PLAN_ARG") || fail 'explicit plan is not a readable regular file'
else
  EXPLICIT_PLAN=""
fi

claude_plans_dir() {
  local configured
  configured=$(jq -r '.plansDirectory // empty' "$SETTINGS_PATH" 2>/dev/null || true)
  if [ -n "$configured" ]; then
    if [[ "$configured" == \~/* ]]; then
      printf '%s/%s\n' "$HOME" "${configured#\~/}"
    elif [[ "$configured" == /* ]]; then
      printf '%s\n' "$configured"
    else
      printf '%s/%s\n' "$(dirname "$SETTINGS_PATH")" "$configured"
    fi
    return 0
  fi
  printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans"
}

CLAUDE_PLANS_DIR=$(claude_plans_dir)
if [ -d "$CLAUDE_PLANS_DIR" ]; then
  CLAUDE_PLANS_DIR=$(cd "$CLAUDE_PLANS_DIR" && pwd -P)
fi

add_candidate() {
  local source_system="$1" trust_tier="$2" precedence_tier="$3" path="$4" evidence="$5"
  local canonical epoch modified title digest status_hints related detection candidate
  canonical=$(plan_source_canonical_file "$path") || return 0
  epoch=$(plan_source_mtime_epoch "$canonical") || return 0
  modified=$(plan_source_modified_at "$epoch") || return 0
  title=$(plan_source_title "$canonical")
  digest=$(plan_source_digest "$canonical") || return 0
  status_hints=$(plan_source_status_hints "$canonical")
  related=$(plan_source_related_artifacts "$canonical")
  detection=$(plan_source_detection_evidence "$evidence")
  candidate=$(jq -n \
    --arg system "$source_system" \
    --arg trust "$trust_tier" \
    --argjson tier "$precedence_tier" \
    --arg path "$canonical" \
    --arg modified "$modified" \
    --argjson epoch "$epoch" \
    --arg title "$title" \
    --arg digest "$digest" \
    --argjson status "$status_hints" \
    --argjson related "$related" \
    --argjson detection "$detection" \
    '{source_system:$system,trust_tier:$trust,precedence_tier:$tier,canonical_path:$path,
      modification_time:$modified,modified_epoch:$epoch,title:$title,status_hints:$status,
      related_artifacts:$related,digest:$digest,detection_evidence:$detection}')
  CANDIDATES=$(jq -c --argjson candidate "$candidate" '. + [$candidate]' <<< "$CANDIDATES")
}

CANDIDATES='[]'

if [ -n "$EXPLICIT_PLAN" ]; then
  add_candidate 'explicit' 'unverified-markdown' 1 "$EXPLICIT_PLAN" 'explicit --plan path'
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  add_candidate 'lbwc' 'verified-local' 2 "$path" 'project-local .lbwc-planning plan'
done < <(plan_source_collect_lbwc "$PROJECT_ROOT")

while IFS= read -r path; do
  [ -n "$path" ] || continue
  add_candidate 'gsd' 'verified-adapter' 3 "$path" 'recognized GSD phase plan'
done < <(plan_source_collect_gsd "$PROJECT_ROOT")

while IFS= read -r path; do
  [ -n "$path" ] || continue
  add_candidate 'markdown' 'unverified-markdown' 4 "$path" 'capped generic Markdown scan'
done < <(plan_source_collect_generic_markdown "$PROJECT_ROOT" "$GENERIC_CAP" "$CLAUDE_PLANS_DIR" "$MAX_FILE_BYTES" "$GENERIC_MAX_TOTAL_BYTES")

if [ -d "$CLAUDE_PLANS_DIR" ]; then
  if [ -n "$(jq -r '.plansDirectory // empty' "$SETTINGS_PATH" 2>/dev/null || true)" ]; then
    CLAUDE_EVIDENCE='configured Claude Code plansDirectory'
  else
    CLAUDE_EVIDENCE='default Claude Code plans directory'
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    add_candidate 'claude-code' 'unverified-markdown' 5 "$path" "$CLAUDE_EVIDENCE"
  done < <(plan_source_collect_claude "$CLAUDE_PLANS_DIR" "$CLAUDE_CAP" "$MAX_FILE_BYTES" "$CLAUDE_MAX_TOTAL_BYTES")
fi

SORTED_CANDIDATES=$(jq -c '
  sort_by([.canonical_path, .precedence_tier]) |
  group_by(.canonical_path) |
  map(min_by(.precedence_tier)) |
  sort_by([-.modified_epoch, .canonical_path])
' <<< "$CANDIDATES")
DISPLAY_CANDIDATES=$(jq -c --argjson cap "$DISPLAY_CAP" '.[0:$cap]' <<< "$SORTED_CANDIDATES")

SELECTED_PLAN='null'
SELECTION_STATUS='plain-instruction-needed'
SELECTION_AUTHORITY='none'
if [ -n "$EXPLICIT_PLAN" ]; then
  SELECTED_PLAN=$(jq -c --arg path "$EXPLICIT_PLAN" 'map(select(.canonical_path == $path)) | .[0]' <<< "$SORTED_CANDIDATES")
  SELECTION_STATUS='explicit'
  SELECTION_AUTHORITY='explicit-plan-and-instruction'
elif [ "$INSTRUCTION_SET" = true ]; then
  SELECTION_STATUS='explicit-instruction'
  SELECTION_AUTHORITY='explicit-plan-and-instruction'
elif [ "$(jq 'length' <<< "$SORTED_CANDIDATES")" -gt 0 ]; then
  SELECTION_STATUS='needs-user-selection'
  SELECTION_AUTHORITY='discovery-candidates'
fi

PLAN_INDEX=$(jq -n \
  --arg project "$PROJECT_ROOT" \
  --argjson candidates "$SORTED_CANDIDATES" \
  --argjson display "$DISPLAY_CANDIDATES" \
  --arg status "$SELECTION_STATUS" \
  --arg authority "$SELECTION_AUTHORITY" \
  --argjson selected "$SELECTED_PLAN" \
  --argjson instruction_set "$INSTRUCTION_SET" \
  --arg instruction "$INSTRUCTION" \
  --argjson generic_cap "$GENERIC_CAP" \
  --argjson claude_cap "$CLAUDE_CAP" \
  --argjson display_cap "$DISPLAY_CAP" \
  --argjson max_file_bytes "$MAX_FILE_BYTES" \
  --argjson generic_max_bytes "$GENERIC_MAX_TOTAL_BYTES" \
  --argjson claude_max_bytes "$CLAUDE_MAX_TOTAL_BYTES" \
  '{schema_version:1,mode:"authoritative",project_root:$project,
    precedence:[
      {tier:1,name:"explicit-plan-and-instruction"},
      {tier:2,name:"active-lbwc"},
      {tier:3,name:"recognized-project-adapter"},
      {tier:4,name:"generic-markdown"},
      {tier:5,name:"claude-code-plans"},
      {tier:6,name:"plain-instruction-and-codebase-context"}],
    caps:{generic_max_files:$generic_cap,claude_max_files:$claude_cap,display_candidates:$display_cap,
      max_file_bytes:$max_file_bytes,generic_max_total_bytes:$generic_max_bytes,claude_max_total_bytes:$claude_max_bytes},
    request:{instruction_supplied:$instruction_set,instruction:$instruction},
    selection:{status:$status,authority:$authority,selected_plan:$selected,display_candidates:$display},
    candidates:$candidates}')

write_json() {
  local path="$1" content="$2" temporary
  temporary="$RUN_ROOT/.$(basename "$path").tmp.$$"
  printf '%s\n' "$content" > "$temporary"
  mv -f "$temporary" "$path"
}

write_json "$RUN_ROOT/plan-index.json" "$PLAN_INDEX"

MAP_ARTIFACTS='[]'
add_map_artifact() {
  local system="$1" trust="$2" path="$3" freshness="$4" canonical epoch modified digest artifact
  canonical=$(plan_source_canonical_file "$path") || return 0
  epoch=$(plan_source_mtime_epoch "$canonical") || return 0
  modified=$(plan_source_modified_at "$epoch") || return 0
  digest=$(plan_source_digest "$canonical") || return 0
  artifact=$(jq -n --arg system "$system" --arg trust "$trust" --arg path "$canonical" \
    --arg freshness "$freshness" --arg modified "$modified" --argjson epoch "$epoch" --arg digest "$digest" \
    '{source_system:$system,trust_tier:$trust,kind:"codebase-map-artifact",canonical_path:$path,
      modification_time:$modified,modified_epoch:$epoch,digest:$digest,freshness:$freshness}')
  MAP_ARTIFACTS=$(jq -c --argjson artifact "$artifact" '. + [$artifact]' <<< "$MAP_ARTIFACTS")
}

map_freshness() {
  local meta="$1" root="$2" saved_hash current_hash file_count
  saved_hash=$(awk '$1 == "git_hash:" {print $2; exit}' "$meta" 2>/dev/null || true)
  file_count=$(awk '$1 == "file_count:" {print $2; exit}' "$meta" 2>/dev/null || true)
  current_hash=$(git -C "$root" rev-parse HEAD 2>/dev/null || true)
  if [ -n "$current_hash" ] && [ "$saved_hash" = "$current_hash" ] && [[ "$file_count" =~ ^[1-9][0-9]*$ ]]; then
    printf 'fresh\n'
  else
    printf 'stale\n'
  fi
}

if [ -d "$PROJECT_ROOT/.lbwc-planning/codebase" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ "$(basename "$path")" = 'META.md' ]; then
      freshness=$(map_freshness "$path" "$PROJECT_ROOT")
    else
      freshness='unknown'
    fi
    add_map_artifact 'lbwc' 'verified-local' "$path" "$freshness"
  done < <(find "$PROJECT_ROOT/.lbwc-planning/codebase" -type f -print 2>/dev/null | LC_ALL=C sort)
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  add_map_artifact 'gsd' 'verified-adapter' "$path" 'unknown'
done < <(plan_source_collect_external_codebase "$PROJECT_ROOT")

PROBE_RAW=''
PROBE_ROUTE=''
PROBE_STATUS='unknown'
if [ -x "$SCRIPT_DIR/probe-map-tools.sh" ] || [ -f "$SCRIPT_DIR/probe-map-tools.sh" ]; then
  PROBE_RAW=$(cd "$PROJECT_ROOT" && LBWC_PLANNING_DIR="$PROJECT_ROOT/.lbwc-planning" bash "$SCRIPT_DIR/probe-map-tools.sh" 2>/dev/null || true)
  PROBE_ROUTE=$(printf '%s' "$PROBE_RAW" | jq -r '.hookSpecificOutput.additionalContext | fromjson? | .recommended_route // empty' 2>/dev/null || true)
  [ -n "$PROBE_ROUTE" ] && PROBE_STATUS='detected'
fi

if [ -n "$PROBE_ROUTE" ]; then
  ROUTES=$(jq -n --arg route "$PROBE_ROUTE" --arg status "$PROBE_STATUS" \
    '[{route:$route,status:$status,source:"probe-map-tools.sh"}]')
else
  ROUTES='[{"route":"unknown","status":"unknown","source":"probe-map-tools.sh"}]'
fi

CODEBASE_INDEX=$(jq -n \
  --arg project "$PROJECT_ROOT" \
  --argjson artifacts "$MAP_ARTIFACTS" \
  --argjson routes "$ROUTES" \
  '{schema_version:1,mode:"authoritative",project_root:$project,artifacts:$artifacts,
    semantic_navigation_routes:$routes}')
write_json "$RUN_ROOT/codebase-index.json" "$CODEBASE_INDEX"

jq -n --arg plan "$RUN_ROOT/plan-index.json" --arg codebase "$RUN_ROOT/codebase-index.json" \
  '{status:"ok",mode:"authoritative",plan_index:$plan,codebase_index:$codebase}'
