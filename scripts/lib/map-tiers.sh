#!/usr/bin/env bash
# Shared codebase-map detection helpers, sourced by commands (via Bash) and
# exercised directly by tests/map-tiers.bats.
#
# Usage:
#   . scripts/lib/map-tiers.sh
#   MAP_TIER=$(resolve_map_tier <file_count> <prefer_teams> [forced_tier])
#   eval "$(resolve_map_mode <planning_dir> [forced_mode])"   # sets MAPPING_MODE, CHANGED_FILES
#
# resolve_map_mode prints two lines: mode=full|incremental and
# changed_files=<count> (0 when unknown or full).

resolve_map_tier() {
  local file_count="$1" prefer_teams="${2:-auto}" forced="${3:-}"
  case "$forced" in
    solo|duo|quad|"") ;;
    *) echo "map-tiers: unknown tier: $forced" >&2; return 1 ;;
  esac
  if [ "$prefer_teams" = "never" ]; then
    printf 'tier=solo\n'; return 0
  fi
  if [ -n "$forced" ]; then
    printf 'tier=%s\n' "$forced"; return 0
  fi
  if [ "$file_count" -lt 200 ] 2>/dev/null; then
    printf 'tier=solo\n'
  elif [ "$file_count" -le 1000 ] 2>/dev/null; then
    printf 'tier=duo\n'
  else
    printf 'tier=quad\n'
  fi
}

resolve_map_mode() {
  local planning_dir="$1" forced="${2:-}"
  local meta="$planning_dir/codebase/META.md"
  if [ "$forced" = "incremental" ] || [ "$forced" = "full" ]; then
    printf 'mode=%s\nchanged_files=0\n' "$forced"; return 0
  fi
  if [ ! -f "$meta" ] || ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'mode=full\nchanged_files=0\n'; return 0
  fi
  local git_hash file_count changed
  git_hash=$(grep '^git_hash:' "$meta" | awk '{print $2}' || true)
  file_count=$(grep '^file_count:' "$meta" | awk '{print $2}' || true)
  if [ -z "$git_hash" ] || [ "$git_hash" = "no-git" ] || [[ ! "$file_count" =~ ^[1-9][0-9]*$ ]]; then
    printf 'mode=full\nchanged_files=0\n'; return 0
  fi
  if ! git cat-file -e "$git_hash" 2>/dev/null; then
    printf 'mode=full\nchanged_files=0\n'; return 0
  fi
  changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [ $(( changed * 100 / file_count )) -lt 20 ]; then
    printf 'mode=incremental\nchanged_files=%s\n' "$changed"
  else
    printf 'mode=full\nchanged_files=%s\n' "$changed"
  fi
}
