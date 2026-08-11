#!/usr/bin/env bash
set -u


PRINT_ADDED=false
if [ "${1:-}" = "--print-added" ]; then
  PRINT_ADDED=true
  shift
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq not found; cannot migrate config." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_FILE="$SCRIPT_DIR/../config/settings.json"
CONFIG_FILE="${1:-.lbwc-planning/config.json}"

if [ ! -f "$DEFAULTS_FILE" ]; then
  echo "ERROR: defaults.json not found: $DEFAULTS_FILE" >&2
  exit 1
fi

if ! jq empty "$DEFAULTS_FILE" >/dev/null 2>&1; then
  echo "ERROR: defaults.json is malformed: $DEFAULTS_FILE" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  if [ "$PRINT_ADDED" = true ]; then
    echo "0"
  fi
  exit 0
fi

if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ERROR: Config migration failed (malformed JSON): $CONFIG_FILE" >&2
  exit 1
fi

missing_defaults_count() {
  jq -s '.[0] as $d | .[1] as $c | [$d | keys[] | select($c[.] == null)] | length' "$DEFAULTS_FILE" "$CONFIG_FILE" 2>/dev/null
}

MISSING_BEFORE=$(missing_defaults_count)

apply_update() {
  local filter="$1"
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$CONFIG_FILE" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$CONFIG_FILE"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

normalize_uat_round_cap_json() {
  local raw="$1"
  local normalized

  normalized=$(bash "$SCRIPT_DIR/resolve-uat-remediation-round-limit.sh" --normalize-json "$raw" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$normalized" ]; then
    echo "ERROR: Config migration failed while normalizing UAT remediation round cap." >&2
    exit 1
  fi

  echo "$normalized"
}

read_uat_round_cap_raw() {
  local key="$1"

  bash "$SCRIPT_DIR/resolve-uat-remediation-round-limit.sh" --read-top-level-literal "$CONFIG_FILE" "$key" 2>/dev/null
}

if jq -e 'has("agent_teams") and (has("prefer_teams") | not)' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: (if .agent_teams == true then "always" else "auto" end)} | del(.agent_teams)'; then
    echo "ERROR: Config migration failed while renaming agent_teams." >&2
    exit 1
  fi
elif jq -e 'has("agent_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update 'del(.agent_teams)'; then
    echo "ERROR: Config migration failed while removing stale agent_teams." >&2
    exit 1
  fi
fi

if ! jq -e 'has("model_profile")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_profile: "quality"}'; then
    echo "ERROR: Config migration failed while adding model_profile." >&2
    exit 1
  fi
fi

if ! jq -e 'has("model_overrides")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {model_overrides: {}}'; then
    echo "ERROR: Config migration failed while adding model_overrides." >&2
    exit 1
  fi
fi

if ! jq -e 'has("prefer_teams")' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '. + {prefer_teams: "auto"}'; then
    echo "ERROR: Config migration failed while adding prefer_teams." >&2
    exit 1
  fi
fi

if jq -e 'has("prefer_teams") and ((.prefer_teams == "when_parallel") or (.prefer_teams == "") or (.prefer_teams == null) or ((.prefer_teams | type) == "boolean"))' "$CONFIG_FILE" >/dev/null 2>&1; then
  if ! apply_update '.prefer_teams = (if .prefer_teams == true then "always" else "auto" end)'; then
    echo "ERROR: Config migration failed while canonicalizing prefer_teams." >&2
    exit 1
  fi
fi


GRADUATED_KEYS='del(
  .v2_hard_contracts, .v2_hard_gates, .v2_typed_protocol, .v2_role_isolation,
  .v3_event_log, .v3_delta_context, .v3_context_cache,
  .v3_plan_research_persist, .v3_schema_validation,
  .v3_contract_lite, .v3_lock_lite,
  .subagent_skill_xml_mode
)'
if ! apply_update "$GRADUATED_KEYS"; then
  echo "ERROR: Config migration failed while removing graduated flags." >&2
  exit 1
fi

rename_flag() {
  local old_name="$1" new_name="$2"
  if jq -e "has(\"$old_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
    if ! jq -e "has(\"$new_name\")" "$CONFIG_FILE" >/dev/null 2>&1; then
      if ! apply_update ". + {\"$new_name\": .$old_name} | del(.$old_name)"; then
        echo "ERROR: Config migration failed while renaming $old_name to $new_name." >&2
        exit 1
      fi
    else
      if ! apply_update "del(.$old_name)"; then
        echo "ERROR: Config migration failed while removing stale $old_name." >&2
        exit 1
      fi
    fi
  fi
}

rename_flag v2_token_budgets token_budgets
rename_flag v2_two_phase_completion two_phase_completion
rename_flag v3_metrics metrics
rename_flag v3_smart_routing smart_routing
rename_flag v3_validation_gates validation_gates
rename_flag v3_snapshot_resume snapshot_resume
rename_flag v3_lease_locks lease_locks
rename_flag v3_event_recovery event_recovery
rename_flag v3_monorepo_routing monorepo_routing
rename_flag v3_rolling_summary rolling_summary

if jq -e 'has("max_uat_remediation_rounds")' "$CONFIG_FILE" >/dev/null 2>&1; then
  UAT_CAP_RAW=$(read_uat_round_cap_raw "max_uat_remediation_rounds" || echo "null")
  UAT_CAP_CANONICAL=$(normalize_uat_round_cap_json "$UAT_CAP_RAW")
  if jq -e 'has("max_remediation_rounds")' "$CONFIG_FILE" >/dev/null 2>&1; then
    if ! apply_update ".max_uat_remediation_rounds = ${UAT_CAP_CANONICAL} | del(.max_remediation_rounds)"; then
      echo "ERROR: Config migration failed while removing stale max_remediation_rounds." >&2
      exit 1
    fi
  elif ! apply_update ".max_uat_remediation_rounds = ${UAT_CAP_CANONICAL}"; then
    echo "ERROR: Config migration failed while canonicalizing max_uat_remediation_rounds." >&2
    exit 1
  fi
elif jq -e 'has("max_remediation_rounds")' "$CONFIG_FILE" >/dev/null 2>&1; then
  UAT_CAP_RAW=$(read_uat_round_cap_raw "max_remediation_rounds" || echo "null")
  UAT_CAP_CANONICAL=$(normalize_uat_round_cap_json "$UAT_CAP_RAW")
  if ! apply_update ". + {max_uat_remediation_rounds: ${UAT_CAP_CANONICAL}} | del(.max_remediation_rounds)"; then
    echo "ERROR: Config migration failed while renaming max_remediation_rounds." >&2
    exit 1
  fi
fi

TMP=$(mktemp)
if jq --slurpfile defaults "$DEFAULTS_FILE" '$defaults[0] + .' "$CONFIG_FILE" > "$TMP" 2>/dev/null; then
  mv "$TMP" "$CONFIG_FILE"
else
  rm -f "$TMP"
  echo "ERROR: Config migration failed while merging defaults.json." >&2
  exit 1
fi

MISSING_AFTER=$(missing_defaults_count)
ADDED_COUNT=$((MISSING_BEFORE - MISSING_AFTER))
if [ "$ADDED_COUNT" -lt 0 ]; then
  ADDED_COUNT=0
fi

if [ "$PRINT_ADDED" = true ]; then
  echo "$ADDED_COUNT"
fi

exit 0