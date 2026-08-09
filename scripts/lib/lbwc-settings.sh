#!/usr/bin/env bash
set -u

lbwc_settings_path() {
  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/settings.json"
}

lbwc_merged_config() {
  local project_config="$1" settings
  settings=$(lbwc_settings_path)
  if command -v jq >/dev/null 2>&1 && [ -f "$settings" ] && [ -f "$project_config" ]; then
    jq -s '.[0] * .[1]' "$settings" "$project_config" 2>/dev/null && return 0
  fi
  if [ -f "$project_config" ]; then
    cat "$project_config"
    return 0
  fi
  if [ -f "$settings" ]; then
    cat "$settings"
    return 0
  fi
  printf '{}\n'
}
