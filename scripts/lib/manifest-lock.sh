#!/usr/bin/env bash
set -u

manifest_lock_mtime() {
  local lock_dir="$1" mtime
  mtime=$(stat -c %Y "$lock_dir" 2>/dev/null) || mtime=$(stat -f %m "$lock_dir" 2>/dev/null) || return 1
  case "$mtime" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$mtime"
}

manifest_lock_owner_alive() {
  local lock_dir="$1" owner
  owner=$(cat "$lock_dir/pid" 2>/dev/null || true)
  case "$owner" in
    ''|*[!0-9]*|0) return 1 ;;
  esac
  kill -0 "$owner" 2>/dev/null
}

manifest_lock_reclaim_stale() {
  local lock_dir="$1" stale_dir="${1}.stale.${BASHPID:-$$}"
  manifest_lock_owner_alive "$lock_dir" && return 0
  if mv "$lock_dir" "$stale_dir" 2>/dev/null; then
    rm -f "$stale_dir/pid" 2>/dev/null || true
    rmdir "$stale_dir" 2>/dev/null || true
  fi
}

manifest_lock_is_stale() {
  local lock_dir="$1" now="$2" stale_seconds="$3" mtime age
  mtime=$(manifest_lock_mtime "$lock_dir" 2>/dev/null || printf '0')
  case "$mtime" in
    ''|*[!0-9]*|0) return 0 ;;
  esac
  age=$((now - mtime))
  [ "$age" -gt "$stale_seconds" ] && manifest_lock_reclaim_stale "$lock_dir"
}

manifest_lock_record_owner() {
  local lock_dir="$1"
  if printf '%s\n' "${BASHPID:-$$}" > "$lock_dir/pid" 2>/dev/null; then
    return 0
  fi
  rmdir "$lock_dir" 2>/dev/null || true
  return 1
}

manifest_lock_acquire() {
  local lock_dir="$1" env_prefix="$2" timeout_var stale_var
  local started now elapsed stale_seconds timeout
  timeout_var="LBWC_${env_prefix}_LOCK_TIMEOUT"
  stale_var="LBWC_${env_prefix}_LOCK_STALE_SECONDS"
  timeout="${!timeout_var:-10}"
  stale_seconds="${!stale_var:-30}"
  case "$timeout" in ''|*[!0-9]*) timeout=10 ;; esac
  case "$stale_seconds" in ''|*[!0-9]*) stale_seconds=30 ;; esac
  mkdir -p "$(dirname "$lock_dir")" 2>/dev/null || return 1
  started=$(date +%s 2>/dev/null || printf '0')
  while ! mkdir "$lock_dir" 2>/dev/null; do
    now=$(date +%s 2>/dev/null || printf '0')
    elapsed=$((now - started))
    [ "$elapsed" -lt "$timeout" ] || return 1
    manifest_lock_is_stale "$lock_dir" "$now" "$stale_seconds"
    sleep 0.01
  done
  manifest_lock_record_owner "$lock_dir"
}

manifest_lock_release() {
  local lock_dir="$1"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

manifest_lock_with_lock() {
  local lock_dir="$1" env_prefix="$2" callback="${3:-}" status
  shift 3 || return 1
  [ -n "$callback" ] || return 1
  manifest_lock_acquire "$lock_dir" "$env_prefix" || return 1
  if "$callback" "$@"; then
    status=0
  else
    status=$?
  fi
  manifest_lock_release "$lock_dir"
  return "$status"
}

manifest_read() {
  local path="$1" root_key="$2"
  if [ ! -f "$path" ]; then
    jq -nc --arg key "$root_key" '{($key): {}}'
    return 0
  fi
  jq -ce --arg key "$root_key" '
    if type != "object" then error("manifest must be an object")
    elif has($key) and (.[$key] | type) != "object" then error("manifest " + $key + " must be an object")
    elif has($key) then .
    else {($key): .}
    end
  ' "$path"
}

manifest_write() {
  local path="$1" root_key="$2" manifest="$3" tmp
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 1
  tmp="${path}.tmp.${BASHPID:-$$}"
  if ! printf '%s\n' "$manifest" | jq -ce --arg key "$root_key" 'select(type == "object" and (.[$key] | type) == "object")' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if mv -f "$tmp" "$path" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}
