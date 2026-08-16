#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(pwd -P)"
REQUIRE_GITNEXUS=false

usage() {
  printf '%s\n' "Usage: $0 [--project-root PATH] [--require-gitnexus]" >&2
}

while (($# > 0)); do
  case "$1" in
    --project-root)
      (($# >= 2)) || { usage; exit 2; }
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --require-gitnexus)
      REQUIRE_GITNEXUS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)" || {
  printf '%s\n' "Indexer sync: project root is not accessible" >&2
  exit 2
}

if ! command -v jq >/dev/null 2>&1 || ! jq -n 'true' >/dev/null 2>&1; then
  printf '%s\n' "Indexer sync: jq is required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CONTROL_ROOT_SCRIPT="$SCRIPT_DIR/lib/lbwc-control-root.sh"
PLANNING_DIR=""
RUNTIME_DIR=""
SYNC_FILE=""

if [[ ! -f "$CONTROL_ROOT_SCRIPT" ]]; then
  printf '%s\n' "Indexer sync: planning root helper is unavailable: $CONTROL_ROOT_SCRIPT" >&2
  exit 2
fi

# The control-root contract only accepts an initialized planning directory.
if PLANNING_DIR="$(cd "$PROJECT_ROOT" && . "$CONTROL_ROOT_SCRIPT" && lbwc_resolve_control_root "" "$PROJECT_ROOT" "$PROJECT_ROOT" 2>/dev/null)" &&
   [[ "$(basename "$PLANNING_DIR")" == ".lbwc-planning" ]] &&
   [[ -f "$PLANNING_DIR/config.json" ]]; then
  RUNTIME_DIR="$PLANNING_DIR/.runtime"
  SYNC_FILE="$RUNTIME_DIR/indexer-sync.json"
else
  PLANNING_DIR=""
fi

write_sync_record() {
  local route="$1" gitnexus_state="$2" indexed_commit="$3" capability_gap="${4:-}"
  local indexed_at
  [[ -n "$SYNC_FILE" ]] || return 0
  mkdir -p "$RUNTIME_DIR"
  indexed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  jq -n \
    --arg indexed_at "$indexed_at" \
    --arg gitnexus "$gitnexus_state" \
    --arg map_route "$route" \
    --arg indexed_commit "$indexed_commit" \
    --arg capability_gap "$capability_gap" \
    '{indexed_at:$indexed_at, gitnexus:$gitnexus, map_route:$map_route, indexed_commit:(if $indexed_commit == "" then null else $indexed_commit end), capability_gap:(if $capability_gap == "" then null else {status:"unsupported", code:$capability_gap, route:$map_route} end)}' \
    > "$SYNC_FILE"
}

PROBE_RAW=''
if [[ ! -f "$SCRIPT_DIR/probe-map-tools.sh" ]]; then
  write_sync_record "unknown" "probe-missing" ""
  printf '%s\n' "Indexer sync: required map-tools probe is unavailable: $SCRIPT_DIR/probe-map-tools.sh" >&2
  exit 2
fi

if [[ -n "$PLANNING_DIR" ]]; then
  PROBE_RAW="$(cd "$PROJECT_ROOT" && LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT_DIR/probe-map-tools.sh" 2>/dev/null)" || {
    write_sync_record "unknown" "probe-failed" ""
    printf '%s\n' "Indexer sync: map-tools probe failed" >&2
    exit 2
  }
else
  PROBE_RAW="$(cd "$PROJECT_ROOT" && LBWC_PLANNING_DIR="$PROJECT_ROOT/.lbwc-planning/.probe-disabled" bash "$SCRIPT_DIR/probe-map-tools.sh" 2>/dev/null)" || {
    write_sync_record "unknown" "probe-failed" ""
    printf '%s\n' "Indexer sync: map-tools probe failed" >&2
    exit 2
  }
fi

MAP_ROUTE="grep-only"
GITNEXUS_AVAILABLE=false
if [[ -n "$PROBE_RAW" ]]; then
  MAP_ROUTE="$(printf '%s\n' "$PROBE_RAW" | jq -r '
    .hookSpecificOutput.additionalContext as $context
    | if ($context | type) == "string" then ($context | fromjson? | .recommended_route // empty)
      else ($context.recommended_route // empty)
      end
  ')"
  GITNEXUS_AVAILABLE="$(printf '%s\n' "$PROBE_RAW" | jq -r '
    .hookSpecificOutput.additionalContext as $context
    | if ($context | type) == "string" then ($context | fromjson? | .gitnexus.available // false)
      else ($context.gitnexus.available // false)
      end
  ')"
  [[ -n "$MAP_ROUTE" ]] || MAP_ROUTE="grep-only"
fi

if [[ "$REQUIRE_GITNEXUS" == true && "$MAP_ROUTE" != "gitnexus" ]]; then
  write_sync_record "$MAP_ROUTE" "required" ""
  printf '%s\n' "Indexer sync: GitNexus index is required" >&2
  exit 1
fi

if [[ "$MAP_ROUTE" != "gitnexus" ]]; then
  case "$MAP_ROUTE" in
    grep-only)
      GITNEXUS_STATE="not-selected"
      [[ "$GITNEXUS_AVAILABLE" != true ]] && GITNEXUS_STATE="unavailable"
      write_sync_record "$MAP_ROUTE" "$GITNEXUS_STATE" ""
      exit 0
      ;;
    serena|lsp)
      CAPABILITY_GAP="${MAP_ROUTE}-refresh-unsupported"
      ROUTE_LABEL="Serena"
      [[ "$MAP_ROUTE" == "lsp" ]] && ROUTE_LABEL="LSP"
      write_sync_record "$MAP_ROUTE" "not-selected" "" "$CAPABILITY_GAP"
      printf '%s\n' "Indexer sync: $ROUTE_LABEL route selected; refresh is not supported by this helper (capability gap: $CAPABILITY_GAP)" >&2
      exit 0
      ;;
    *)
      write_sync_record "$MAP_ROUTE" "unsupported-route" "" "unknown-map-route"
      printf '%s\n' "Indexer sync: unsupported map route: $MAP_ROUTE" >&2
      exit 1
      ;;
  esac
fi

if [[ "$GITNEXUS_AVAILABLE" != true || ! -f "$PROJECT_ROOT/.gitnexus/run.cjs" ]]; then
  if [[ "$REQUIRE_GITNEXUS" == true ]]; then
    write_sync_record "$MAP_ROUTE" "required" ""
    printf '%s\n' "Indexer sync: GitNexus index is required" >&2
  else
    write_sync_record "$MAP_ROUTE" "missing" ""
    printf '%s\n' "Indexer sync: GitNexus index is missing" >&2
  fi
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  write_sync_record "$MAP_ROUTE" "node-missing" ""
  printf '%s\n' "Indexer sync: node is required for GitNexus" >&2
  exit 2
fi

if ! (cd "$PROJECT_ROOT" && node .gitnexus/run.cjs analyze); then
  write_sync_record "$MAP_ROUTE" "analyze-failed" ""
  printf '%s\n' "Indexer sync: GitNexus analyze failed" >&2
  exit 1
fi

STATUS_OUTPUT="$(cd "$PROJECT_ROOT" && node .gitnexus/run.cjs status)" || {
  write_sync_record "$MAP_ROUTE" "status-failed" ""
  printf '%s\n' "Indexer sync: GitNexus status failed" >&2
  exit 1
}
INDEXED_COMMIT="$(printf '%s\n' "$STATUS_OUTPUT" | awk -F': ' '$1 == "Indexed commit" {print $2; exit}')"
STATUS_VALUE="$(printf '%s\n' "$STATUS_OUTPUT" | awk -F': ' '$1 == "Status" {print $2; exit}')"
case "$STATUS_VALUE" in
  *up-to-date*) STATUS_VALUE="up-to-date" ;;
esac
CURRENT_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null)" || {
  write_sync_record "$MAP_ROUTE" "git-unavailable" "$INDEXED_COMMIT"
  printf '%s\n' "Indexer sync: project Git commit cannot be resolved" >&2
  exit 2
}

if [[ "$STATUS_VALUE" != "up-to-date" || "$INDEXED_COMMIT" != "$CURRENT_COMMIT" ]]; then
  write_sync_record "$MAP_ROUTE" "${STATUS_VALUE:-stale}" "$INDEXED_COMMIT"
  printf '%s\n' "Indexer sync: GitNexus index is stale" >&2
  exit 1
fi

write_sync_record "$MAP_ROUTE" "$STATUS_VALUE" "$INDEXED_COMMIT"
exit 0
