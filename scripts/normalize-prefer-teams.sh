#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/lbwc-settings.sh"

read_raw_value() {
  local config_path="$1"

  if ! command -v jq >/dev/null 2>&1; then
    echo "auto"
    return 0
  fi

  jq -r '.prefer_teams // "auto"' <<< "$(lbwc_merged_config "$config_path")" 2>/dev/null || echo "auto"
}

normalize_prefer_teams() {
  case "${1:-auto}" in
    ""|null|false|when_parallel)
      echo "auto"
      ;;
    true)
      echo "always"
      ;;
    always|auto|never)
      echo "$1"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

if [ "${1:-}" = "--value" ]; then
  shift
  normalize_prefer_teams "${1:-auto}"
  exit 0
fi

normalize_prefer_teams "$(read_raw_value "${1:-.lbwc-planning/config.json}")"
