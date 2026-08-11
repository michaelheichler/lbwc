#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"
P="/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"
PTMP="${P}.tmp.$$"
LOCK="/tmp/.lbwc-phase-detect-live-${SESSION_KEY}.lock"
LOCK_STALE_SECONDS=5
LOCKED=false
phase_detect_start_ts=$(date +%s 2>/dev/null || echo 0)

refresh_phase_detect_link() {
  bash "$SCRIPT_DIR/resolve-plugin-root.sh" --require-script phase-detect.sh >/dev/null 2>&1 || return 1
  [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]
}

phase_detect_lock_mtime() {
  stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0
}

phase_detect_lock_is_stale() {
  local owner_pid="" lock_mtime=0 now_ts=0 lock_age=0

  owner_pid=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]]; then
    if kill -0 "$owner_pid" 2>/dev/null; then
      return 1
    fi
    return 0
  fi

  lock_mtime=$(phase_detect_lock_mtime)
  now_ts=$(date +%s 2>/dev/null || echo 0)
  [[ "$lock_mtime" =~ ^[0-9]+$ && "$now_ts" =~ ^[0-9]+$ ]] || return 1
  lock_age=$((now_ts - lock_mtime))
  [ "$lock_age" -ge "$LOCK_STALE_SECONDS" ]
}

release_phase_detect_lock() {
  local owner_pid=""

  [ "$LOCKED" = true ] || return 0
  owner_pid=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -z "$owner_pid" ] || [ "$owner_pid" = "$$" ]; then
    rm -f "$LOCK/pid" 2>/dev/null || true
    rmdir "$LOCK" 2>/dev/null || true
  fi
  LOCKED=false
}

acquire_phase_detect_lock() {
  local lock_retry_count=0

  while [ $lock_retry_count -lt 100 ]; do
    if mkdir "$LOCK" 2>/dev/null; then
      LOCKED=true
      if (set -o noclobber; printf '%s\n' "$$" > "$LOCK/pid") 2>/dev/null; then
        return 0
      fi
      release_phase_detect_lock
      return 1
    fi
    if phase_detect_lock_is_stale; then
      rm -f "$LOCK/pid" 2>/dev/null || true
      rmdir "$LOCK" 2>/dev/null || true
    else
      sleep 0.1
    fi
    lock_retry_count=$((lock_retry_count + 1))
  done
  return 1
}

trap release_phase_detect_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

refresh_phase_detect_link || true

if acquire_phase_detect_lock; then
  bash "$L/scripts/phase-detect.sh" > "$PTMP" 2>/dev/null || printf '%s\n' 'phase_detect_error=true' > "$PTMP"
  mv "$PTMP" "$P"
  release_phase_detect_lock
else
  cache_retry_count=0
  while [ $cache_retry_count -lt 100 ]; do
    [ -f "$P" ] && break
    sleep 0.1
    cache_retry_count=$((cache_retry_count + 1))
  done
  if [ ! -f "$P" ]; then
    printf '%s\n' 'phase_detect_error=true' > "$PTMP"
    mv "$PTMP" "$P"
  fi
fi

PD=""

phase_detect_cache_fresh() {
  local modified_at=""
  [ -f "$P" ] || return 1
  modified_at=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
  [ -n "$modified_at" ] || return 1
  [ "$modified_at" -ge "$phase_detect_start_ts" ] 2>/dev/null
}

phase_detect_cache_retryable() {
  [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]
}

freshness_retry_count=0
while [ $freshness_retry_count -lt 100 ]; do
  if phase_detect_cache_fresh; then
    PD=$(cat "$P")
    break
  fi
  sleep 0.1
  freshness_retry_count=$((freshness_retry_count + 1))
done

if phase_detect_cache_retryable; then
  refresh_phase_detect_link || true
fi

if phase_detect_cache_retryable && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
  refresh_retry_count=0
  while [ $refresh_retry_count -lt 100 ]; do
    if phase_detect_cache_fresh; then
      PD=$(cat "$P")
      if ! phase_detect_cache_retryable; then
        break
      fi
    fi
    if acquire_phase_detect_lock; then
      PTMP="${P}.reader.$$.$RANDOM"
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
      if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
        printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
      fi
      release_phase_detect_lock
      break
    fi
    sleep 0.1
    refresh_retry_count=$((refresh_retry_count + 1))
  done
fi

if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && phase_detect_cache_fresh; then
  PD=$(cat "$P")
fi

printf '%s\n' "$L"
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  printf '%s\n' 'phase_detect_error=true'
fi
