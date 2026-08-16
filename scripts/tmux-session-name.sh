#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf '%s\n' 'Usage: tmux-session-name.sh --project-root PATH --main-id ID [--prefix PREFIX]' >&2
}

fail() {
  printf 'tmux session name error: %s\n' "$1" >&2
  exit 2
}

safe_component() {
  local value="$1" limit="$2"
  value=$(printf '%s' "$value" | LC_ALL=C tr -cs 'A-Za-z0-9._-' '-' | tr -s '-')
  while [[ "$value" == -* ]]; do value="${value#-}"; done
  while [[ "$value" == *- ]]; do value="${value%-}"; done
  value="${value:0:limit}"
  while [[ "$value" == *- ]]; do value="${value%-}"; done
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

project_root=""
main_id=""
prefix="lbwc"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || fail '--project-root requires a path'
      project_root="$2"
      shift 2
      ;;
    --main-id)
      [ "$#" -ge 2 ] || fail '--main-id requires an identifier'
      main_id="$2"
      shift 2
      ;;
    --prefix)
      [ "$#" -ge 2 ] || fail '--prefix requires a value'
      prefix="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[ -n "$project_root" ] || fail '--project-root is required'
[ -n "$main_id" ] || fail '--main-id is required'
[ -d "$project_root" ] || fail "project root does not exist: $project_root"
command -v shasum >/dev/null 2>&1 || fail 'shasum is unavailable; cannot derive a collision-resistant session name'

project_root=$(cd "$project_root" && pwd -P)
prefix=$(safe_component "$prefix" 24) || fail 'prefix has no safe characters'
project_slug=$(safe_component "$(basename "$project_root")" 40) || fail 'project root name has no safe characters'
main_short=$(safe_component "$main_id" 8) || fail 'main ID has no safe characters'
session_hash=$(printf '%s\0%s' "$project_root" "$main_id" | shasum -a 256) || fail 'cannot derive session name digest'
session_hash="${session_hash%% *}"
session_hash="${session_hash:0:16}"

printf '%s-%s-%s-%s\n' "$prefix" "$project_slug" "$main_short" "$session_hash"
