#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: resolve-agent-settings.sh <role> <project-config-path> <plugin-root> [--model V] [--effort V] [--reasoning V] [--max-turns V]\n' >&2
}

fail() { printf '%s\n' "$1" >&2; exit 1; }
fail_unknown_model() { printf '%s\n' "$1" >&2; exit 3; }

[ "$#" -ge 3 ] || { usage; exit 1; }
ROLE="$1"
CONFIG_PATH="$2"
PLUGIN_ROOT="$3"
shift 3

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

MODEL_PROFILES="$PLUGIN_ROOT/config/model-profiles.json"
REASONING_PROFILES="$PLUGIN_ROOT/config/reasoning-profiles.json"
PRICING_PATH="$PLUGIN_ROOT/config/model-pricing.json"
TEMPLATE_DEFAULTS="$PLUGIN_ROOT/templates/agent-roles/defaults.json"
SETTINGS_LIB="$PLUGIN_ROOT/scripts/lib/lbwc-settings.sh"

[ -f "$MODEL_PROFILES" ] || fail "model profiles not found: $MODEL_PROFILES"
[ -f "$REASONING_PROFILES" ] || fail "reasoning profiles not found: $REASONING_PROFILES"
[ -f "$PRICING_PATH" ] || fail "model pricing catalogue not found: $PRICING_PATH"
[ -f "$TEMPLATE_DEFAULTS" ] || fail "role defaults not found: $TEMPLATE_DEFAULTS"
[ -f "$SETTINGS_LIB" ] || fail "settings lib not found: $SETTINGS_LIB"
. "$SETTINGS_LIB"
. "$PLUGIN_ROOT/scripts/lib/agent-fields.sh"

VALID_ROLES=$(jq -r '[.quality, .balanced, .budget | keys[]] | unique | .[]' "$MODEL_PROFILES")
is_valid_role() { agent_role_is_valid "$1" "$MODEL_PROFILES"; }
is_valid_role "$ROLE" || fail "invalid role '$ROLE'. Valid: $(tr '\n' ' ' <<< "$VALID_ROLES")"

[ ! -f "$CONFIG_PATH" ] || jq empty "$CONFIG_PATH" >/dev/null 2>&1 || fail "project config is not valid JSON: $CONFIG_PATH"
PROJECT_CONFIG='{}'
[ -f "$CONFIG_PATH" ] && PROJECT_CONFIG=$(cat "$CONFIG_PATH")

declare -A RETIRED_REPLACEMENT=(
  [model_matrix]="roles.<role>.model"
  [model_overrides]="roles.<role>.model"
  [reasoning_matrix]="roles.<role>.effort"
  [reasoning_overrides]="roles.<role>.effort"
  [agent_max_turns]="roles.<role>.max_turns"
  [model_catalog]="config/model-pricing.json .models"
  [model_catalog_extra]="config/model-pricing.json .models"
  [custom_profiles]="model_profile, or edit config/model-profiles.json directly"
)
for retired_key in "${!RETIRED_REPLACEMENT[@]}"; do
  jq -e --arg k "$retired_key" 'has($k)' <<< "$PROJECT_CONFIG" >/dev/null 2>&1 \
    && fail "project config key '$retired_key' is retired. Use '${RETIRED_REPLACEMENT[$retired_key]}' instead."
done

MODEL_PROFILE=$(jq -r '.model_profile // "quality"' <<< "$PROJECT_CONFIG")
jq -e --arg p "$MODEL_PROFILE" 'has($p)' "$MODEL_PROFILES" >/dev/null 2>&1 \
  || fail "invalid model_profile '$MODEL_PROFILE'. Valid: quality, balanced, budget"

canonicalize_model() {
  local model="$1"
  if [ "$model" = "inherit" ]; then
    printf 'inherit\n'
    return 0
  fi
  jq -r --arg m "$model" '.aliases[$m] // $m' "$PRICING_PATH"
}

ROLE_MODEL_OVERRIDE=$(jq -r --arg r "$ROLE" '.roles[$r].model // empty' <<< "$PROJECT_CONFIG")
if [ -n "$CLI_MODEL" ]; then
  RAW_MODEL="$CLI_MODEL"
elif [ -n "$ROLE_MODEL_OVERRIDE" ]; then
  RAW_MODEL="$ROLE_MODEL_OVERRIDE"
else
  RAW_MODEL=$(jq -r --arg p "$MODEL_PROFILE" --arg r "$ROLE" '.[$p][$r] // empty' "$MODEL_PROFILES")
fi
[ -n "$RAW_MODEL" ] || fail "no model resolved for role '$ROLE' in profile '$MODEL_PROFILE'"
MODEL=$(canonicalize_model "$RAW_MODEL")
if [ "$MODEL" != "inherit" ] && ! jq -e --arg m "$MODEL" '.models | has($m)' "$PRICING_PATH" >/dev/null 2>&1; then
  fail_unknown_model "unknown model id '$RAW_MODEL' (canonical '$MODEL'): no entry in $PRICING_PATH aliases or models"
fi

ROLE_EFFORT_OVERRIDE=$(jq -r --arg r "$ROLE" '.roles[$r].effort // empty' <<< "$PROJECT_CONFIG")
if [ -n "$CLI_REASONING" ]; then
  EFFORT="$CLI_REASONING"
elif [ -n "$ROLE_EFFORT_OVERRIDE" ]; then
  EFFORT="$ROLE_EFFORT_OVERRIDE"
else
  EFFORT=$(jq -r --arg p "$MODEL_PROFILE" --arg r "$ROLE" '.[$p][$r] // empty' "$REASONING_PROFILES")
fi

if [ "$MODEL" != "inherit" ] && [ -n "$EFFORT" ]; then
  SUPPORTED=$(jq -r --arg m "$MODEL" '(.models[$m].reasoning_efforts // []) | join(" ")' "$PRICING_PATH")
  if [ -z "$SUPPORTED" ]; then
    EFFORT=""
  elif ! grep -qw -- "$EFFORT" <<< "$SUPPORTED"; then
    EFFORT=$(jq -r --arg m "$MODEL" '.models[$m].reasoning_default // ""' "$PRICING_PATH")
    [ "$EFFORT" = "null" ] && EFFORT=""
  fi
fi

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
  # defaults.json is the single source for a role's base max_turns. A role with
  # no value anywhere is a configuration error, not a silent 30.
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
emit RESOLVED_MODEL "$MODEL"
emit RESOLVED_MAX_TURNS "$MAX_TURNS"
emit RESOLVED_EFFORT "$EFFORT"
