#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

usage() {
  printf '%s\n' 'Usage: runtime-snapshot.sh <freeze|validate|cancel|cleanup> --planning-dir PATH --phase-dir PATH [--requested-backend in_process|tmux|workflow --resolved-backend in_process|tmux|workflow]' >&2
}

fail() {
  printf 'runtime snapshot: %s\n' "$1" >&2
  exit 1
}

require_tools() {
  local tool
  for tool in jq mktemp mv shasum; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
  done
}

canonicalize_paths() {
  local planning_input="$1" phase_input="$2" phase_name
  [ -d "$planning_input" ] && [ ! -L "$planning_input" ] || fail "planning directory is unavailable: $planning_input"
  PLANNING_DIR=$(cd -P -- "$planning_input" && pwd -P) || fail "cannot resolve planning directory: $planning_input"
  [ "${PLANNING_DIR##*/}" = '.lbwc-planning' ] || fail "planning directory must end with .lbwc-planning: $planning_input"
  [ -d "$phase_input" ] && [ ! -L "$phase_input" ] || fail "phase directory is unavailable: $phase_input"
  PHASE_DIR=$(cd -P -- "$phase_input" && pwd -P) || fail "cannot resolve phase directory: $phase_input"
  case "$PHASE_DIR" in
    "$PLANNING_DIR/phases/"*) ;;
    *) fail "phase directory must be under $PLANNING_DIR/phases: $phase_input" ;;
  esac
  phase_name=${PHASE_DIR##*/}
  [[ "$phase_name" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]] || fail "phase directory is not canonical: $phase_input"
  PHASE="phases/$phase_name"
  CONFIG_PATH="$PLANNING_DIR/config.json"
  SNAPSHOT_PATH="$PHASE_DIR/.runtime-snapshot.json"
  CANCEL_PATH="$PHASE_DIR/.runtime-cancelled.json"
  [ ! -e "$SNAPSHOT_PATH" ] || [ -f "$SNAPSHOT_PATH" -a ! -L "$SNAPSHOT_PATH" ] || fail "runtime snapshot path is unsafe: $SNAPSHOT_PATH"
  [ ! -e "$CANCEL_PATH" ] || [ -f "$CANCEL_PATH" -a ! -L "$CANCEL_PATH" ] || fail "runtime cancel marker path is unsafe: $CANCEL_PATH"
}

read_config() {
  local routing_roles
  [ -f "$CONFIG_PATH" ] && [ ! -L "$CONFIG_PATH" ] || fail "configuration is unavailable: $CONFIG_PATH"
  jq empty "$CONFIG_PATH" >/dev/null 2>&1 || fail "configuration is not valid JSON: $CONFIG_PATH"
  jq -e '
    type == "object"
    and (.effort | type == "string" and IN("thorough", "balanced", "fast", "turbo"))
    and (.agent_execution_mode | type == "string" and IN("in_process", "tmux", "workflow", "ask"))
    and (.tmux_execution | type == "object")
    and (.tmux_execution.enabled | type == "boolean")
    and (.tmux_execution.comms_fallback | type == "string" and IN("bus_only", "fall_back_to_in_process"))
    and (.tmux_execution.restrictions | type == "object")
    and (.tmux_execution.restrictions.allow_nested_spawn | type == "boolean")
    and (.tmux_execution.restrictions.allow_agent_git | type == "boolean")
    and (.tmux_execution.restrictions.allow_agent_ask_user | type == "boolean")
    and (.tmux_execution.restrictions.require_orchestrator_attach | type == "boolean")
    and (.workflow_execution | type == "object")
    and (.workflow_execution.enabled | type == "boolean")
    and (.routing | type == "object")
    and (.routing.active_profile | type == "string")
    and (.routing.profiles[.routing.active_profile].roles | type == "object")
    and ([.routing.profiles[.routing.active_profile].roles[] | type == "object"
      and (.model | type == "string" and length > 0)
      and ((.reasoning == null) or (.reasoning | type == "string"))
      and (.status == "resolved")] | all)
  ' "$CONFIG_PATH" >/dev/null || fail "configuration cannot produce a runtime snapshot: $CONFIG_PATH"
  routing_roles=$(jq -cS '.routing.profiles[.routing.active_profile].roles' "$CONFIG_PATH") || fail 'cannot read active routing roles'
  [ "$routing_roles" != '{}' ] || fail 'active routing profile has no resolved roles'
  CONFIG_DIGEST=$(jq -cS '.' "$CONFIG_PATH" | shasum -a 256 | awk '{print $1}') || fail 'cannot digest configuration'
  [[ "$CONFIG_DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail 'configuration digest is invalid'
  CONFIG_EFFORT=$(jq -r '.effort' "$CONFIG_PATH") || fail 'cannot read configuration effort'
  CONFIG_MODE=$(jq -r '.agent_execution_mode' "$CONFIG_PATH") || fail 'cannot read execution mode'
  CONFIG_PROFILE=$(jq -r '.routing.active_profile' "$CONFIG_PATH") || fail 'cannot read routing profile'
  CONFIG_TMUX=$(jq -cS '.tmux_execution' "$CONFIG_PATH") || fail 'cannot read tmux execution settings'
  CONFIG_WORKFLOW=$(jq -cS '.workflow_execution' "$CONFIG_PATH") || fail 'cannot read workflow execution settings'
  CONFIG_ROUTING_ROLES="$routing_roles"
}

assert_workflow_capability() {
  local catalog_path reasons
  [ -z "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ] || fail 'workflow backend is unavailable: CLAUDE_CODE_DISABLE_WORKFLOWS is set in this session'
  [ -z "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] || fail 'workflow backend is unavailable: CLAUDE_CODE_SUBAGENT_MODEL is set in this session, which overrides both the session model and any model a workflow script routes'
  catalog_path="$PLANNING_DIR/claude-capabilities.json"
  [ -f "$catalog_path" ] && [ ! -L "$catalog_path" ] || fail "workflow backend is unavailable: no capability catalog at $catalog_path, run scripts/claude-capabilities.sh refresh first"
  jq -e '.workflow | type == "object"' "$catalog_path" >/dev/null 2>&1 || fail "workflow backend is unavailable: capability catalog carries no workflow probe: $catalog_path"
  jq -e '.workflow.available == true' "$catalog_path" >/dev/null 2>&1 && return 0
  reasons=$(jq -r '.workflow.unavailable_reasons | join(" ")' "$catalog_path" 2>/dev/null)
  fail "workflow backend is unavailable: $reasons"
}

validate_backends() {
  local requested="$1" resolved="$2"
  case "$requested" in in_process|tmux|workflow) ;; *) fail "requested backend is invalid: $requested" ;; esac
  case "$resolved" in in_process|tmux|workflow) ;; *) fail "resolved backend is invalid: $resolved" ;; esac
  case "$CONFIG_MODE" in
    in_process)
      [ "$requested" = in_process ] && [ "$resolved" = in_process ] || fail 'backend drift: configuration requires in_process'
      ;;
    tmux)
      [ "$requested" = tmux ] || fail 'backend drift: configuration requires tmux'
      ;;
    workflow)
      [ "$requested" = workflow ] && [ "$resolved" = workflow ] || fail 'backend drift: configuration requires workflow'
      ;;
    ask) ;;
  esac
  if [ "$requested" = tmux ]; then
    jq -e '.enabled == true' <<< "$CONFIG_TMUX" >/dev/null || fail 'tmux backend is disabled in configuration'
    if [ "$resolved" = in_process ]; then
      jq -e '.comms_fallback == "fall_back_to_in_process"' <<< "$CONFIG_TMUX" >/dev/null || fail 'tmux fallback to in_process is not permitted'
    fi
  elif [ "$requested" = workflow ]; then
    [ "$resolved" = workflow ] || fail 'workflow requested backend cannot resolve to another backend'
    jq -e '.enabled == true' <<< "$CONFIG_WORKFLOW" >/dev/null || fail 'workflow backend is disabled in configuration'
    assert_workflow_capability
  else
    [ "$resolved" = in_process ] || fail 'in_process requested backend cannot resolve to tmux'
  fi
}

snapshot_json() {
  local requested="$1" resolved="$2"
  jq -cn \
    --arg phase "$PHASE" \
    --arg requested "$requested" \
    --arg resolved "$resolved" \
    --arg effort "$CONFIG_EFFORT" \
    --arg profile "$CONFIG_PROFILE" \
    --arg digest "$CONFIG_DIGEST" \
    --argjson routing_roles "$CONFIG_ROUTING_ROLES" \
    --argjson tmux_execution "$CONFIG_TMUX" \
    '{schema_version:1,phase:$phase,requested_backend:$requested,resolved_backend:$resolved,effort:$effort,routing_profile:$profile,routing_roles:$routing_roles,tmux_execution:$tmux_execution,source_config_digest:$digest}' \
    | jq -cS '.'
}

validate_snapshot_schema() {
  local snapshot="$1"
  jq -e '
    def route:
      type == "object"
      and (keys | sort == ["model", "reasoning", "status"])
      and (.model | type == "string" and length > 0)
      and ((.reasoning == null) or (.reasoning | type == "string"))
      and .status == "resolved";
    type == "object"
    and (keys | sort == ["effort", "phase", "requested_backend", "resolved_backend", "routing_profile", "routing_roles", "schema_version", "source_config_digest", "tmux_execution"])
    and .schema_version == 1
    and (.phase | type == "string" and test("^phases/[0-9]{2}-[a-z0-9][a-z0-9-]*$"))
    and (.requested_backend | IN("in_process", "tmux", "workflow"))
    and (.resolved_backend | IN("in_process", "tmux", "workflow"))
    and (.effort | type == "string" and IN("thorough", "balanced", "fast", "turbo"))
    and (.routing_profile | type == "string" and length > 0)
    and (.routing_roles | type == "object" and length > 0 and all(.[]; route))
    and (.tmux_execution | type == "object")
    and (.tmux_execution.restrictions | type == "object")
    and (.tmux_execution.restrictions.allow_nested_spawn | type == "boolean")
    and (.tmux_execution.restrictions.allow_agent_git | type == "boolean")
    and (.tmux_execution.restrictions.allow_agent_ask_user | type == "boolean")
    and (.tmux_execution.restrictions.require_orchestrator_attach | type == "boolean")
    and (.source_config_digest | type == "string" and test("^[0-9a-f]{64}$"))
  ' <<< "$snapshot" >/dev/null
}

load_snapshot() {
  [ -f "$SNAPSHOT_PATH" ] || fail "runtime snapshot is missing: $SNAPSHOT_PATH"
  SNAPSHOT_JSON=$(jq -cS '.' "$SNAPSHOT_PATH" 2>/dev/null) || fail "runtime snapshot is malformed: $SNAPSHOT_PATH"
  validate_snapshot_schema "$SNAPSHOT_JSON" || fail "runtime snapshot is malformed: $SNAPSHOT_PATH"
  [ "$(jq -r '.phase' <<< "$SNAPSHOT_JSON")" = "$PHASE" ] || fail "runtime snapshot phase does not match: $SNAPSHOT_PATH"
}

validate_snapshot_against_config() {
  local requested resolved expected
  load_snapshot
  read_config
  requested=$(jq -r '.requested_backend' <<< "$SNAPSHOT_JSON")
  resolved=$(jq -r '.resolved_backend' <<< "$SNAPSHOT_JSON")
  validate_backends "$requested" "$resolved"
  [ "$(jq -r '.source_config_digest' <<< "$SNAPSHOT_JSON")" = "$CONFIG_DIGEST" ] || fail "backend drift: frozen configuration differs from $SNAPSHOT_PATH"
  expected=$(snapshot_json "$requested" "$resolved") || fail 'cannot rebuild runtime snapshot'
  [ "$SNAPSHOT_JSON" = "$expected" ] || fail "backend drift: frozen runtime metadata differs from configuration"
}

emit_result() {
  local status="$1"
  jq -cn --arg status "$status" --arg snapshot_path "$SNAPSHOT_PATH" --argjson snapshot "${SNAPSHOT_JSON:-null}" '{status:$status,snapshot_path:$snapshot_path,snapshot:$snapshot}'
}

freeze_snapshot() {
  local requested="$1" resolved="$2" temporary
  if [ -e "$SNAPSHOT_PATH" ]; then
    validate_snapshot_against_config
    [ "$(jq -r '.requested_backend' <<< "$SNAPSHOT_JSON")" = "$requested" ] || fail 'backend drift: requested backend differs from frozen runtime snapshot'
    [ "$(jq -r '.resolved_backend' <<< "$SNAPSHOT_JSON")" = "$resolved" ] || fail 'backend drift: resolved backend differs from frozen runtime snapshot'
    emit_result matched
    return 0
  fi
  read_config
  validate_backends "$requested" "$resolved"
  SNAPSHOT_JSON=$(snapshot_json "$requested" "$resolved") || fail 'cannot build runtime snapshot'
  temporary=$(mktemp "$PHASE_DIR/.runtime-snapshot.tmp.XXXXXX") || fail "cannot create runtime snapshot temporary file: $PHASE_DIR"
  chmod 600 "$temporary" || { rm -f -- "$temporary"; fail "cannot secure runtime snapshot temporary file: $temporary"; }
  printf '%s\n' "$SNAPSHOT_JSON" > "$temporary" || { rm -f -- "$temporary"; fail "cannot write runtime snapshot temporary file: $temporary"; }
  mv -f "$temporary" "$SNAPSHOT_PATH" || { rm -f -- "$temporary"; fail "cannot atomically write runtime snapshot: $SNAPSHOT_PATH"; }
  emit_result created
}

cleanup_snapshot() {
  load_snapshot
  rm -f -- "$SNAPSHOT_PATH" || fail "cannot remove runtime snapshot: $SNAPSHOT_PATH"
  SNAPSHOT_JSON='null'
  emit_result cleaned
}

cancel_snapshot() {
  local temporary marker
  [ ! -e "$SNAPSHOT_PATH" ] || fail "runtime snapshot already exists: $SNAPSHOT_PATH"
  marker=$(jq -cn --arg phase "$PHASE" '{schema_version:1,phase:$phase,status:"cancelled"}' | jq -cS '.') \
    || fail 'cannot build runtime cancel marker'
  temporary=$(mktemp "$PHASE_DIR/.runtime-cancelled.tmp.XXXXXX") || fail "cannot create runtime cancel marker temporary file: $PHASE_DIR"
  chmod 600 "$temporary" || { rm -f -- "$temporary"; fail "cannot secure runtime cancel marker temporary file: $temporary"; }
  printf '%s\n' "$marker" > "$temporary" || { rm -f -- "$temporary"; fail "cannot write runtime cancel marker temporary file: $temporary"; }
  mv -f "$temporary" "$CANCEL_PATH" || { rm -f -- "$temporary"; fail "cannot atomically write runtime cancel marker: $CANCEL_PATH"; }
  SNAPSHOT_JSON='null'
  emit_result cancelled
}

command="${1:-}"
[ "$#" -ge 1 ] || { usage; exit 1; }
shift
planning_input=''
phase_input=''
requested_backend=''
resolved_backend=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --planning-dir)
      [ "$#" -ge 2 ] || fail '--planning-dir requires a value'
      planning_input="$2"
      shift 2
      ;;
    --phase-dir)
      [ "$#" -ge 2 ] || fail '--phase-dir requires a value'
      phase_input="$2"
      shift 2
      ;;
    --requested-backend)
      [ "$#" -ge 2 ] || fail '--requested-backend requires a value'
      requested_backend="$2"
      shift 2
      ;;
    --resolved-backend)
      [ "$#" -ge 2 ] || fail '--resolved-backend requires a value'
      resolved_backend="$2"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

require_tools
[ -n "$planning_input" ] || fail '--planning-dir is required'
[ -n "$phase_input" ] || fail '--phase-dir is required'
canonicalize_paths "$planning_input" "$phase_input"

case "$command" in
  freeze)
    [ -n "$requested_backend" ] && [ -n "$resolved_backend" ] || fail 'freeze requires requested and resolved backends'
    freeze_snapshot "$requested_backend" "$resolved_backend"
    ;;
  validate)
    [ -z "$requested_backend" ] && [ -z "$resolved_backend" ] || fail 'validate does not accept backend options'
    validate_snapshot_against_config
    emit_result matched
    ;;
  cancel)
    [ -z "$requested_backend" ] && [ -z "$resolved_backend" ] || fail 'cancel does not accept backend options'
    cancel_snapshot
    ;;
  cleanup)
    [ -z "$requested_backend" ] && [ -z "$resolved_backend" ] || fail 'cleanup does not accept backend options'
    cleanup_snapshot
    ;;
  *)
    usage
    exit 1
    ;;
esac
