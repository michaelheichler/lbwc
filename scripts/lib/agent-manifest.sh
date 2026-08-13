#!/usr/bin/env bash
set -u

AGENT_MANIFEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$AGENT_MANIFEST_SCRIPT_DIR/lbwc-control-root.sh" 2>/dev/null || return 1

agent_manifest_control_root() {
  local requested="${1:-.lbwc-planning}" resolved
  resolved=$(lbwc_control_root_validate "$requested" 1 2>/dev/null) || return 1
  printf '%s\n' "$resolved"
}

agent_manifest_path() {
  lbwc_control_root_manifest_path "${1:-.lbwc-planning}"
}

agent_manifest_lock_path() {
  lbwc_control_root_lock_path "${1:-.lbwc-planning}"
}

agent_manifest_lock_mtime() {
  local lock_dir="$1" mtime
  mtime=$(stat -c %Y "$lock_dir" 2>/dev/null) || mtime=$(stat -f %m "$lock_dir" 2>/dev/null) || return 1
  case "$mtime" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$mtime"
}

agent_manifest_lock_owner_alive() {
  local lock_dir="$1" owner
  owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
  case "$owner" in
    ''|*[!0-9]*|0) return 1 ;;
  esac
  kill -0 "$owner" 2>/dev/null
}

agent_manifest_reclaim_stale_lock() {
  local lock_dir="$1" stale_dir="${1}.stale.${BASHPID:-$$}"
  agent_manifest_lock_owner_alive "$lock_dir" && return 0
  if mv "$lock_dir" "$stale_dir" 2>/dev/null; then
    rm -f "$stale_dir/pid" 2>/dev/null || true
    rmdir "$stale_dir" 2>/dev/null || true
  fi
}

agent_manifest_lock_is_stale() {
  local lock_dir="$1" now="$2" stale_seconds="$3" mtime age
  mtime=$(agent_manifest_lock_mtime "$lock_dir" 2>/dev/null || printf '0')
  case "$mtime" in
    ''|*[!0-9]*|0) return 0 ;;
  esac
  age=$((now - mtime))
  [ "$age" -gt "$stale_seconds" ] && agent_manifest_reclaim_stale_lock "$lock_dir"
}

agent_manifest_record_lock_owner() {
  local lock_dir="$1"
  if printf '%s\n' "${BASHPID:-$$}" > "$lock_dir/pid" 2>/dev/null; then
    return 0
  fi
  rmdir "$lock_dir" 2>/dev/null || true
  return 1
}

agent_manifest_acquire_lock() {
  local planning_dir="${1:-.lbwc-planning}" lock_dir started now elapsed stale_seconds timeout control_root
  control_root=$(agent_manifest_control_root "$planning_dir") || return 1
  lock_dir=$(agent_manifest_lock_path "$control_root")
  timeout="${LBWC_AGENT_MANIFEST_LOCK_TIMEOUT:-10}"
  stale_seconds="${LBWC_AGENT_MANIFEST_LOCK_STALE_SECONDS:-30}"
  case "$timeout" in ''|*[!0-9]*) timeout=10 ;; esac
  case "$stale_seconds" in ''|*[!0-9]*) stale_seconds=30 ;; esac
  mkdir -p "$control_root" 2>/dev/null || return 1
  started=$(date +%s 2>/dev/null || printf '0')
  while ! mkdir "$lock_dir" 2>/dev/null; do
    now=$(date +%s 2>/dev/null || printf '0')
    elapsed=$((now - started))
    [ "$elapsed" -lt "$timeout" ] || return 1
    agent_manifest_lock_is_stale "$lock_dir" "$now" "$stale_seconds"
    sleep 0.01
  done
  agent_manifest_record_lock_owner "$lock_dir"
}

agent_manifest_release_lock() {
  local lock_dir control_root
  control_root=$(agent_manifest_control_root "${1:-.lbwc-planning}") || return 1
  lock_dir=$(agent_manifest_lock_path "$control_root")
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

agent_manifest_with_lock() {
  local planning_dir="${1:-.lbwc-planning}" callback="${2:-}" status
  shift 2 || return 1
  [ -n "$callback" ] || return 1
  agent_manifest_acquire_lock "$planning_dir" || return 1
  if "$callback" "$@"; then
    status=0
  else
    status=$?
  fi
  agent_manifest_release_lock "$planning_dir"
  return "$status"
}

agent_manifest_read() {
  local planning_dir="${1:-.lbwc-planning}" path control_root
  control_root=$(agent_manifest_control_root "$planning_dir") || return 1
  path=$(agent_manifest_path "$control_root")
  if [ ! -f "$path" ]; then
    printf '%s\n' '{"agents":{}}'
    return 0
  fi
  jq -ce '
    if type != "object" then error("manifest must be an object")
    elif has("agents") and (.agents | type) != "object" then error("manifest agents must be an object")
    elif has("agents") then .
    else {agents: .}
    end
  ' "$path"
}

agent_manifest_write() {
  local planning_dir="$1" manifest="$2" path tmp control_root
  control_root=$(agent_manifest_control_root "$planning_dir") || return 1
  path=$(agent_manifest_path "$control_root")
  mkdir -p "$control_root" 2>/dev/null || return 1
  tmp="${path}.tmp.${BASHPID:-$$}"
  if ! printf '%s\n' "$manifest" | jq -ce 'select(type == "object" and (.agents | type) == "object")' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if mv -f "$tmp" "$path" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

agent_manifest_safe_name() {
  case "${1:-}" in
    ''|.|..|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;;
  esac
}

agent_manifest_definition_path() {
  local planning_dir="$1" name="$2" project_root control_root
  agent_manifest_safe_name "$name" || return 1
  control_root=$(agent_manifest_control_root "$planning_dir") || return 1
  project_root=$(lbwc_control_root_project_root "$control_root") || return 1
  printf '%s/.claude/agents/%s.md\n' "$project_root" "$name"
}

manifest_new_pair_id() {
  local ts rand
  ts=$(date +%s%N 2>/dev/null || date +%s)
  rand=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  [ -n "$rand" ] || rand="$RANDOM$RANDOM"
  printf 'pair-%s-%s\n' "$ts" "$rand"
}

manifest_find_open_pair() {
  local planning_dir="${1:-.lbwc-planning}" manifest
  manifest=$(agent_manifest_read "$planning_dir") || return 1
  jq -r '
    [.agents[] | select(.pair_id != null and (.state == "registered" or .state == "running"))]
    | group_by(.pair_id)
    | map(select(length == 1))
    | (.[0].[0].pair_id // empty)
  ' <<< "$manifest"
}

manifest_pair_partner_state() {
  local planning_dir="${1:-.lbwc-planning}" pair_id="${2:-}" exclude_name="${3:-}" manifest
  [ -n "$pair_id" ] || { printf 'none\n'; return 0; }
  manifest=$(agent_manifest_read "$planning_dir") || return 1
  jq -r --arg pid "$pair_id" --arg exclude "$exclude_name" '
    [.agents[] | select(.pair_id == $pid and .name != $exclude)]
    | (.[0].state // "none")
  ' <<< "$manifest"
}
