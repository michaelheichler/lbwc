#!/usr/bin/env bash

caveman_used_pct() {
  local usage_file="$1" field_count

  field_count=$(awk -F'|' '{print NF}' "$usage_file" 2>/dev/null)

  if [[ "$field_count" == "3" ]]; then
    awk -F'|' '{print $2}' "$usage_file" 2>/dev/null
  elif [[ "$field_count" == "2" ]]; then
    awk -F'|' '{print $1}' "$usage_file" 2>/dev/null
  fi
}

caveman_level_for_pct() {
  local used_pct="$1"

  if (( used_pct >= 85 )); then
    echo "ultra"
  elif (( used_pct >= 70 )); then
    echo "full"
  elif (( used_pct >= 50 )); then
    echo "lite"
  else
    echo "none"
  fi
}

resolve_caveman_level() {
  local style="${1:-none}"
  local planning_dir="${2:-.lbwc-planning}"

  if [[ "$style" != "auto" ]]; then
    RESOLVED_CAVEMAN_LEVEL="$style"
    return 0
  fi

  local usage_file="${planning_dir}/.context-usage"
  if [[ ! -f "$usage_file" ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  local used_pct
  used_pct=$(caveman_used_pct "$usage_file")
  if [[ -z "$used_pct" ]] || ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  RESOLVED_CAVEMAN_LEVEL=$(caveman_level_for_pct "$used_pct")
  return 0
}

: "${RESOLVED_CAVEMAN_LEVEL-}"
