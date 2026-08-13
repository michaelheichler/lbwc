#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: resolve-agent-settings.sh <role> <project-config-path> <plugin-root> [--model V] [--effort V] [--reasoning V] [--max-turns V]\n' >&2
  printf '       resolve-agent-settings.sh <role> --routing <config-path> <plugin-root> [--model V] [--effort V] [--reasoning V] [--max-turns V]\n' >&2
}

fail() { printf '%s\n' "$1" >&2; exit 1; }
fail_unknown_model() { printf '%s\n' "$1" >&2; exit 3; }

[ "$#" -ge 3 ] || { usage; exit 1; }
ROLE="$1"
CONFIG_PATH="$2"
PLUGIN_ROOT="$3"
shift 3

TEMPORARY_ROUTING_MODE=false
if [ "$CONFIG_PATH" = "--routing" ]; then
  # Explicit routing authority: the config path must exist and is never replaced
  # by a fallback. Used for temporary control roots outside .lbwc-planning.
  CONFIG_PATH="$PLUGIN_ROOT"
  PLUGIN_ROOT="${1:-}"
  [ -n "$PLUGIN_ROOT" ] || { usage; exit 1; }
  shift
  [ -f "$CONFIG_PATH" ] || fail "routing configuration is not readable: $CONFIG_PATH"
  PLANNING_DIR=$(cd "$(dirname "$CONFIG_PATH")" && pwd -P) || fail "could not resolve routing configuration directory: $CONFIG_PATH"
  TEMPORARY_ROUTING_MODE=true
else
  PLANNING_DIR=$(cd "$(dirname "$CONFIG_PATH")" 2>/dev/null && pwd -P) || fail "could not resolve project configuration directory: $CONFIG_PATH"
fi

CLI_MODEL=""
CLI_WORKFLOW_EFFORT=""
CLI_REASONING=""
CLI_MAX_TURNS=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) CLI_MODEL="${2:-}"; shift 2 ;;
    --effort) CLI_WORKFLOW_EFFORT="${2:-}"; shift 2 ;;
    --reasoning) CLI_REASONING="${2:-}"; shift 2 ;;
    --max-turns) CLI_MAX_TURNS="${2:-}"; shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

TEMPLATE_DEFAULTS="$PLUGIN_ROOT/templates/agent-roles/defaults.json"
SETTINGS_LIB="$PLUGIN_ROOT/scripts/lib/lbwc-settings.sh"
ROUTING_SCRIPT="${LBWC_ROUTING_SCRIPT:-$PLUGIN_ROOT/scripts/lbwc-routing.sh}"

[ -f "$TEMPLATE_DEFAULTS" ] || fail "role defaults not found: $TEMPLATE_DEFAULTS"
[ -f "$SETTINGS_LIB" ] || fail "settings lib not found: $SETTINGS_LIB"
[ -f "$ROUTING_SCRIPT" ] || fail "routing resolver not found: $ROUTING_SCRIPT"
# shellcheck source=/dev/null
. "$SETTINGS_LIB"
. "$PLUGIN_ROOT/scripts/lib/agent-fields.sh"

VALID_ROLES=$(jq -r 'keys[]' "$TEMPLATE_DEFAULTS")
is_valid_role() { jq -e --arg role "$1" 'has($role)' "$TEMPLATE_DEFAULTS" >/dev/null 2>&1; }
is_valid_role "$ROLE" || fail "invalid role '$ROLE'. Valid: $(tr '\n' ' ' <<< "$VALID_ROLES")"

[ ! -f "$CONFIG_PATH" ] || jq empty "$CONFIG_PATH" >/dev/null 2>&1 || fail "project config is not valid JSON: $CONFIG_PATH"
PROJECT_CONFIG='{}'
[ -f "$CONFIG_PATH" ] && PROJECT_CONFIG=$(cat "$CONFIG_PATH")

normalize_workflow_effort() {
  local raw
  raw=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$raw" in
    thorough|balanced|fast|turbo) printf '%s' "$raw" ;;
    high) printf 'thorough' ;;
    medium) printf 'balanced' ;;
    low) printf 'turbo' ;;
    "") printf '' ;;
    *) return 1 ;;
  esac
}

multiplier_for_effort() {
  case "$1" in
    thorough) echo "3 2" ;;
    balanced) echo "1 1" ;;
    fast) echo "4 5" ;;
    turbo) echo "3 5" ;;
  esac
}

normalize_turn_value() {
  local value="$1"
  case "$value" in
    false|FALSE|False|null|"") printf '\n'; return 0 ;;
  esac
  [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
  [ "$value" -gt 0 ] || { printf '\n'; return 0; }
  printf '%s\n' "$value"
}

if [ "$TEMPORARY_ROUTING_MODE" = true ]; then
  if [ -n "$CLI_MODEL" ] || [ -n "$CLI_REASONING" ]; then
    fail '--model and --reasoning require saved routing state; temporary control roots have none'
  fi
  ROUTE_CELL=$(jq -c --arg role "$ROLE" '.routing.profiles.balanced.roles[$role] // null' "$CONFIG_PATH" 2>/dev/null) \
    || fail "routing configuration is not valid JSON: $CONFIG_PATH"
  if [ "$ROUTE_CELL" != "null" ]; then
    AGENT_MODEL=$(jq -r '.model // empty' <<< "$ROUTE_CELL")
    [ -n "$AGENT_MODEL" ] || fail "seeded routing cell for '$ROLE' has no explicit model: $CONFIG_PATH"
    EFFORT=$(jq -r 'if .reasoning == null then "" else .reasoning end' <<< "$ROUTE_CELL")
  else
    AGENT_MODEL="inherit"
    EFFORT=""
  fi
  if [ -n "$CLI_MAX_TURNS" ]; then
    case "$CLI_MAX_TURNS" in
      false|FALSE|False|null|"") RESOLVED_MAX_TURNS="" ;;
      *[!0-9]*|-*) fail "invalid --max-turns value '$CLI_MAX_TURNS'" ;;
      *)
        [ "$CLI_MAX_TURNS" -gt 0 ] || fail "invalid --max-turns value '$CLI_MAX_TURNS'"
        RESOLVED_MAX_TURNS="$CLI_MAX_TURNS"
        ;;
    esac
  else
    WORKFLOW_EFFORT=""
    if [ -n "$CLI_WORKFLOW_EFFORT" ]; then
      WORKFLOW_EFFORT=$(normalize_workflow_effort "$CLI_WORKFLOW_EFFORT") || fail "invalid --effort value '$CLI_WORKFLOW_EFFORT'"
    fi
    if [ -z "$WORKFLOW_EFFORT" ]; then
      MERGED_SETTINGS=$(lbwc_merged_config "$CONFIG_PATH")
      WORKFLOW_EFFORT=$(normalize_workflow_effort "$(jq -r '.effort // "balanced"' <<< "$MERGED_SETTINGS")" 2>/dev/null || printf 'balanced')
    fi
    read -r NUM DEN <<< "$(multiplier_for_effort "$WORKFLOW_EFFORT")"
    BASE_TURNS=$(jq -r --arg r "$ROLE" '.[$r].maxTurns // empty' "$TEMPLATE_DEFAULTS")
    case "$BASE_TURNS" in
      ''|*[!0-9]*) fail "no maxTurns default for role '$ROLE' in $TEMPLATE_DEFAULTS" ;;
    esac
    RESOLVED_MAX_TURNS=$(( (BASE_TURNS * NUM + DEN / 2) / DEN ))
    [ "$RESOLVED_MAX_TURNS" -ge 1 ] || RESOLVED_MAX_TURNS=1
  fi
  emit() {
    local name="$1" value="$2" quoted
    quoted=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
    printf "%s='%s'\n" "$name" "$quoted"
  }
  emit RESOLVED_AGENT "$ROLE"
  emit RESOLVED_AGENT_MODEL "$AGENT_MODEL"
  emit RESOLVED_MODEL "$AGENT_MODEL"
  emit RESOLVED_MAX_TURNS "$RESOLVED_MAX_TURNS"
  emit RESOLVED_EFFORT "$EFFORT"
  emit RESOLVED_REASONING "$EFFORT"
  emit RESOLVED_REASONING_JSON "null"
  exit 0
fi

ROUTE_JSON=$(bash "$ROUTING_SCRIPT" resolve "$PLANNING_DIR" "$ROLE") || fail "route resolution failed for '$ROLE': $ROUTE_JSON"
MODEL=$(jq -r '.model' <<< "$ROUTE_JSON")
REASONING_JSON=$(jq -c '.reasoning' <<< "$ROUTE_JSON")

if [ -n "$CLI_MODEL" ]; then
  MODEL="$CLI_MODEL"
fi
if [ -n "$CLI_REASONING" ]; then
  REASONING_JSON=$(jq -Rn --arg value "$CLI_REASONING" '$value')
fi

ROUTE_CHECK=""
if ! ROUTE_CHECK=$(bash "$ROUTING_SCRIPT" check "$PLANNING_DIR" "$MODEL" "$REASONING_JSON" 2>&1); then
  if [[ "$ROUTE_CHECK" == *"model selector is not present"* ]]; then
    fail_unknown_model "$ROUTE_CHECK"
  fi
  fail "$ROUTE_CHECK"
fi
AGENT_MODEL="$MODEL"
EFFORT=$(jq -r 'if . == null then "" else . end' <<< "$REASONING_JSON")

normalize_turn_value() {
  local value="$1"
  case "$value" in
    false|FALSE|False|null|"") printf '\n'; return 0 ;;
  esac
  [[ "$value" =~ ^-?[0-9]+$ ]] || return 1
  [ "$value" -gt 0 ] || { printf '\n'; return 0; }
  printf '%s\n' "$value"
}

if [ -n "$CLI_MAX_TURNS" ]; then
  MAX_TURNS=$(normalize_turn_value "$CLI_MAX_TURNS") || fail "invalid --max-turns value '$CLI_MAX_TURNS'"
else
  WORKFLOW_EFFORT=""
  if [ -n "$CLI_WORKFLOW_EFFORT" ]; then
    WORKFLOW_EFFORT=$(normalize_workflow_effort "$CLI_WORKFLOW_EFFORT" 2>/dev/null || true)
  fi
  if [ -z "$WORKFLOW_EFFORT" ]; then
    MERGED_SETTINGS=$(lbwc_merged_config "$CONFIG_PATH")
    CFG_EFFORT=$(jq -r '.effort // "balanced"' <<< "$MERGED_SETTINGS")
    WORKFLOW_EFFORT=$(normalize_workflow_effort "$CFG_EFFORT" 2>/dev/null || echo "balanced")
  fi

  ROLE_MAXTURNS_OVERRIDE=$(jq -r --arg r "$ROLE" '.roles[$r].max_turns // empty' <<< "$PROJECT_CONFIG")
  if [ -n "$ROLE_MAXTURNS_OVERRIDE" ]; then
    BASE=$(normalize_turn_value "$ROLE_MAXTURNS_OVERRIDE") || BASE=""
  else
    BASE=$(jq -r --arg r "$ROLE" '.[$r].maxTurns // empty' "$TEMPLATE_DEFAULTS")
    [ -n "$BASE" ] && BASE=$(normalize_turn_value "$BASE" || true)
  fi
  [ -n "$BASE" ] || fail "no max_turns resolved for role '$ROLE': set roles.$ROLE.max_turns in project config or $ROLE.maxTurns in $TEMPLATE_DEFAULTS"

  read -r NUM DEN <<< "$(multiplier_for_effort "$WORKFLOW_EFFORT")"
  MAX_TURNS=$(( (BASE * NUM + DEN / 2) / DEN ))
  [ "$MAX_TURNS" -ge 1 ] || MAX_TURNS=1
fi

emit() {
  local name="$1" value="$2" quoted
  quoted=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
  printf "%s='%s'\n" "$name" "$quoted"
}
emit RESOLVED_AGENT "$ROLE"
emit RESOLVED_AGENT_MODEL "$AGENT_MODEL"
emit RESOLVED_MODEL "$MODEL"
emit RESOLVED_MAX_TURNS "$MAX_TURNS"
emit RESOLVED_EFFORT "$EFFORT"
emit RESOLVED_REASONING "$EFFORT"
emit RESOLVED_REASONING_JSON "$REASONING_JSON"
