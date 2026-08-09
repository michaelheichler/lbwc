#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
READ_JSON_LITERAL_AWK="$SCRIPT_DIR/lib/resolve-uat-round-limit-read-json.awk"

usage() {
  echo "Usage: resolve-uat-remediation-round-limit.sh [config-path] | --normalize-json <json-literal> | --validate-input <value> | --read-top-level-literal <config-path> <key> | --next-round-decision <config-path> <current-round>" >&2
}

canonicalize_decimal_string() {
  local raw="${1:-}"
  local stripped

  stripped=$(printf '%s' "$raw" | sed 's/^0*//')
  if [ -z "$stripped" ]; then
    echo "false"
  else
    echo "$stripped"
  fi
}

normalize_json_literal() {
  local raw="${1:-}"

  case "$raw" in
    ""|null|false|0)
      echo "false"
      return 0
      ;;
    true)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    canonicalize_decimal_string "$raw"
    return 0
  fi

  echo "false"
}

validate_input_value() {
  local raw="${1:-}"
  local normalized

  normalized=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  case "$normalized" in
    false)
      echo "false"
      return 0
      ;;
    0)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$normalized" =~ ^[0-9]+$ ]]; then
    canonicalize_decimal_string "$normalized"
    return 0
  fi

  return 1
}

read_json_literal() {
  local config_path="$1"
  local key="$2"

  awk -v target="$key" -f "$READ_JSON_LITERAL_AWK" "$config_path"
}

decimal_gt() {
  local left="${1:-0}"
  local right="${2:-0}"
  local greater

  left=$(printf '%s' "$left" | sed 's/^0*//')
  right=$(printf '%s' "$right" | sed 's/^0*//')
  [ -z "$left" ] && left="0"
  [ -z "$right" ] && right="0"

  if [ "${#left}" -gt "${#right}" ]; then
    return 0
  fi

  if [ "${#left}" -lt "${#right}" ]; then
    return 1
  fi

  greater=$(printf '%s\n%s\n' "$left" "$right" | LC_ALL=C sort | tail -1)
  [ "$greater" = "$left" ] && [ "$left" != "$right" ]
}

lookup_round_cap_key() {
  local config_path="$1"
  local key="$2"
  local raw canonical

  raw=$(read_json_literal "$config_path" "$key" || true)
  [ -n "$raw" ] || return 1

  canonical=$(normalize_json_literal "$raw")
  [ "$canonical" != "false" ] && printf '%s\n' "$canonical"
  return 0
}

resolve_from_config() {
  local config_path="${1:-.lbwc-planning/config.json}"

  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -f "$config_path" ] || ! jq empty "$config_path" >/dev/null 2>&1; then
    return 0
  fi

  lookup_round_cap_key "$config_path" "max_uat_remediation_rounds" && return 0
  lookup_round_cap_key "$config_path" "max_remediation_rounds" && return 0
  return 0
}

next_round_decision() {
  local config_path="$1"
  local current_round_raw="$2"
  local current_round next_round max_rounds cap_reached="false"

  if ! [[ "$current_round_raw" =~ ^[0-9]+$ ]]; then
    echo "Error: current round must be a numeric value" >&2
    return 1
  fi

  current_round=$(printf '%02d' "$((10#$current_round_raw))")
  next_round=$(printf '%02d' "$((10#$current_round_raw + 1))")
  max_rounds=$(resolve_from_config "$config_path")

  if [ -n "$max_rounds" ] && decimal_gt "$next_round" "$max_rounds"; then
    cap_reached="true"
  fi

  printf 'current_round=%s\n' "$current_round"
  printf 'next_round=%s\n' "$next_round"
  printf 'max_rounds=%s\n' "$max_rounds"
  printf 'cap_reached=%s\n' "$cap_reached"
  if [ -n "$max_rounds" ]; then
    echo "unlimited=false"
  else
    echo "unlimited=true"
  fi
}

case "${1:-}" in
  --normalize-json)
    shift
    normalize_json_literal "${1:-}"
    ;;
  --validate-input)
    shift
    validate_input_value "${1:-}" || exit 1
    ;;
  --read-top-level-literal)
    shift
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    read_json_literal "$1" "$2"
    ;;
  --next-round-decision)
    shift
    if [ "$#" -ne 2 ]; then
      usage
      exit 1
    fi
    next_round_decision "$1" "$2" || exit 1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    resolve_from_config "${1:-.lbwc-planning/config.json}"
    ;;
esac
