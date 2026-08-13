#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: team-run-state.sh resolve-scopes --project-root PATH [--scope PATH ...]' \
    '       team-run-state.sh create --project-root PATH --run-id ID [--scope PATH ...]' \
    '       team-run-state.sh record --run-root PATH --kind KIND --id ID --status STATUS' \
    '       team-run-state.sh update --run-root PATH --status STATUS [--event TEXT]' \
    '       team-run-state.sh summary --run-root PATH'
}

fail() {
  printf 'team-run-state: %s\n' "$1" >&2
  exit 1
}

ACTION="${1:-}"
[ -n "$ACTION" ] || { usage >&2; exit 2; }
shift

PROJECT_ROOT_ARG=""
RUN_ROOT_ARG=""
RUN_ID=""
EVENT_KIND=""
EVENT_ID=""
EVENT_STATUS=""
EVENT_TEXT=""
SCOPES=()

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
    --run-id)
      [ "$#" -ge 2 ] || fail '--run-id requires an id'
      RUN_ID="$2"
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || fail '--scope requires a path'
      SCOPES+=("$2")
      shift 2
      ;;
    --kind)
      [ "$#" -ge 2 ] || fail '--kind requires a value'
      EVENT_KIND="$2"
      shift 2
      ;;
    --id)
      [ "$#" -ge 2 ] || fail '--id requires a value'
      EVENT_ID="$2"
      shift 2
      ;;
    --status)
      [ "$#" -ge 2 ] || fail '--status requires a value'
      EVENT_STATUS="$2"
      shift 2
      ;;
    --event)
      [ "$#" -ge 2 ] || fail '--event requires text'
      EVENT_TEXT="$2"
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

canonical_project_root() {
  local candidate="$1"
  [ -d "$candidate" ] || fail "project root does not exist: $candidate"
  [ ! -L "$candidate" ] || fail 'project root must not be a symbolic link'
  (cd -P "$candidate" && pwd -P) || fail "project root is not readable: $candidate"
}

PROJECT_ROOT=""
if [ -n "$PROJECT_ROOT_ARG" ]; then
  PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
fi

run_id_is_safe() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

scope_path() {
  local requested="$1" candidate canonical relative
  [ -n "$requested" ] || fail 'scope must not be empty'
  if [ "$requested" = "." ]; then
    canonical="$PROJECT_ROOT"
  else
    case "$requested" in
      /*) candidate="$requested" ;;
      *) candidate="$PROJECT_ROOT/$requested" ;;
    esac
    [ -d "$candidate" ] || fail "scope directory does not exist: $requested"
    [ ! -L "$candidate" ] || fail "scope must not be a symbolic link: $requested"
    canonical=$(cd -P "$candidate" && pwd -P) || fail "scope is not readable: $requested"
  fi
  case "$canonical" in
    "$PROJECT_ROOT") printf '.\n' ;;
    "$PROJECT_ROOT"/*)
      relative="${canonical#"$PROJECT_ROOT/"}"
      [ -n "$relative" ] || fail 'scope canonicalization failed'
      printf '%s\n' "$relative"
      ;;
    *) fail 'scope must remain inside the project root' ;;
  esac
}

resolve_scopes_json() {
  local requested scope_json='[]' item
  if [ "${#SCOPES[@]}" -eq 0 ]; then
    SCOPES=(.)
  fi
  for requested in "${SCOPES[@]}"; do
    item=$(scope_path "$requested") || return $?
    scope_json=$(jq -c --arg item "$item" 'if index($item) then . else . + [$item] end' <<< "$scope_json")
  done
  printf '%s\n' "$scope_json"
}

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

run_root_is_valid() {
  local root="$1" expected_parent
  [ -d "$root" ] || return 1
  [ ! -L "$root" ] || return 1
  expected_parent="$PROJECT_ROOT/.temporary-agent-runfiles/runs"
  [ "$(dirname "$root")" = "$expected_parent" ] || return 1
  run_id_is_safe "$(basename "$root")"
}

RUN_ROOT=""
if [ -n "$RUN_ROOT_ARG" ]; then
  [ -n "$PROJECT_ROOT" ] || PROJECT_ROOT=$(canonical_project_root "$(dirname "$(dirname "$(dirname "$RUN_ROOT_ARG")")")")
  RUN_ROOT=$(cd -P "$RUN_ROOT_ARG" 2>/dev/null && pwd -P) || fail "run root is not readable: $RUN_ROOT_ARG"
  run_root_is_valid "$RUN_ROOT" || fail 'run root is outside the project temporary run directory'
fi

write_run_json() {
  local path="$1" value="$2" temporary
  temporary="${path}.tmp.${BASHPID:-$$}"
  printf '%s\n' "$value" > "$temporary" || fail "could not write temporary run state: $temporary"
  mv -f "$temporary" "$path" || { rm -f "$temporary"; fail "could not persist run state: $path"; }
}

append_diagnostic() {
  local root="$1" value="$2"
  printf '%s\n' "$value" >> "$root/diagnostics.jsonl" || fail "could not append run diagnostic: $root/diagnostics.jsonl"
}

case "$ACTION" in
  resolve-scopes)
    [ -n "$PROJECT_ROOT" ] || fail '--project-root is required'
    jq -n --arg project_root "$PROJECT_ROOT" --argjson scopes "$(resolve_scopes_json)" \
      '{project_root:$project_root,scopes:$scopes}'
    ;;
  create)
    [ -n "$PROJECT_ROOT" ] || fail '--project-root is required'
    [ -n "$RUN_ID" ] || fail '--run-id is required'
    run_id_is_safe "$RUN_ID" || fail 'run id is invalid'
    TEMP_ROOT="$PROJECT_ROOT/.temporary-agent-runfiles"
    RUNS_ROOT="$TEMP_ROOT/runs"
    [ ! -e "$TEMP_ROOT" ] || [ ! -L "$TEMP_ROOT" ] || fail 'temporary runfiles root must not be a symbolic link'
    [ ! -e "$RUNS_ROOT" ] || [ ! -L "$RUNS_ROOT" ] || fail 'temporary runs root must not be a symbolic link'
    mkdir -p "$RUNS_ROOT"
    RUN_ROOT="$RUNS_ROOT/$RUN_ID"
    [ ! -e "$RUN_ROOT" ] || fail "run already exists: $RUN_ID"
    mkdir -p "$RUN_ROOT/contracts/tasks" "$RUN_ROOT/generated-agents"
    : > "$RUN_ROOT/diagnostics.jsonl"
    created_at=$(now_utc)
    scopes_json=$(resolve_scopes_json) || exit $?
    run_json=$(jq -n --arg run_id "$RUN_ID" --arg project_root "$PROJECT_ROOT" \
      --arg created_at "$created_at" --arg updated_at "$created_at" --argjson scopes "$scopes_json" \
      '{schema_version:1,run_id:$run_id,project_root:$project_root,status:"planned",scopes:$scopes,created_at:$created_at,updated_at:$updated_at,records:{}}')
    write_run_json "$RUN_ROOT/run.json" "$run_json"
    printf '%s\n' "$RUN_ROOT"
    ;;
  record)
    [ -n "$RUN_ROOT" ] || fail '--run-root is required'
    [ -f "$RUN_ROOT/run.json" ] || fail "run state is missing: $RUN_ROOT/run.json"
    [ -n "$EVENT_KIND" ] && [ -n "$EVENT_ID" ] && [ -n "$EVENT_STATUS" ] || fail 'record requires --kind, --id, and --status'
    run_json=$(jq -e 'type == "object"' "$RUN_ROOT/run.json") || fail 'run state is unreadable'
    updated_at=$(now_utc)
    key="$EVENT_KIND:$EVENT_ID"
    updated=$(jq -c --arg key "$key" --arg kind "$EVENT_KIND" --arg id "$EVENT_ID" \
      --arg status "$EVENT_STATUS" --arg updated_at "$updated_at" \
      '.records = (.records // {}) | .records[$key] = {kind:$kind,id:$id,status:$status,updated_at:$updated_at} | .updated_at = $updated_at' \
      "$RUN_ROOT/run.json") || fail 'run state is unreadable'
    write_run_json "$RUN_ROOT/run.json" "$updated"
    append_diagnostic "$RUN_ROOT" "$(jq -cn --arg kind "$EVENT_KIND" --arg id "$EVENT_ID" --arg status "$EVENT_STATUS" --arg at "$updated_at" '{event:"record",kind:$kind,id:$id,status:$status,at:$at}')"
    printf '%s\n' "$updated"
    ;;
  update)
    [ -n "$RUN_ROOT" ] || fail '--run-root is required'
    [ -f "$RUN_ROOT/run.json" ] || fail "run state is missing: $RUN_ROOT/run.json"
    [ -n "$EVENT_STATUS" ] || fail 'update requires --status'
    updated_at=$(now_utc)
    updated=$(jq -c --arg status "$EVENT_STATUS" --arg updated_at "$updated_at" --arg event "$EVENT_TEXT" \
      '.status = $status | .updated_at = $updated_at | if $event == "" then . else .events = ((.events // []) + [{at:$updated_at,text:$event}]) end' \
      "$RUN_ROOT/run.json") || fail 'run state is unreadable'
    write_run_json "$RUN_ROOT/run.json" "$updated"
    append_diagnostic "$RUN_ROOT" "$(jq -cn --arg status "$EVENT_STATUS" --arg event "$EVENT_TEXT" --arg at "$updated_at" '{event:"update",status:$status,text:$event,at:$at}')"
    printf '%s\n' "$updated"
    ;;
  summary)
    [ -n "$RUN_ROOT" ] || fail '--run-root is required'
    [ -f "$RUN_ROOT/run.json" ] || fail "run state is missing: $RUN_ROOT/run.json"
    jq -e 'type == "object"' "$RUN_ROOT/run.json" >/dev/null || fail 'run state is unreadable'
    jq -r '
      "run_id: \(.run_id)",
      "status: \(.status)",
      "project_root: \(.project_root)",
      ("scope: " + ((.scopes // []) | join(", "))),
      ("records: " + (((.records // {}) | to_entries | map("\(.value.id)=\(.value.status)") | join(", ")) // "none"))
    ' "$RUN_ROOT/run.json"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
