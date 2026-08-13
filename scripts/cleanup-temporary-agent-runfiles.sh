#!/usr/bin/env bash
set -euo pipefail

RETENTION_SECONDS=259200
ACTION="${1:-scan}"
[ "$ACTION" = scan ] || [ "$ACTION" = cleanup ] || {
  printf 'Usage: cleanup-temporary-agent-runfiles.sh {scan|cleanup} --project-root PATH\n' >&2
  exit 2
}
shift

PROJECT_ROOT_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || { printf 'cleanup-temporary-agent-runfiles: --project-root requires a path\n' >&2; exit 1; }
      PROJECT_ROOT_ARG="$2"
      shift 2
      ;;
    *)
      printf 'cleanup-temporary-agent-runfiles: unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PROJECT_ROOT_ARG" ]; then
  PROJECT_ROOT_ARG=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
[ -n "$PROJECT_ROOT_ARG" ] || { printf 'cleanup-temporary-agent-runfiles: repository root is required\n' >&2; exit 1; }
[ -d "$PROJECT_ROOT_ARG" ] && [ ! -L "$PROJECT_ROOT_ARG" ] || {
  printf 'cleanup-temporary-agent-runfiles: invalid project root: %s\n' "$PROJECT_ROOT_ARG" >&2
  exit 1
}
PROJECT_ROOT=$(cd -P "$PROJECT_ROOT_ARG" && pwd -P)
RUNS_ROOT="$PROJECT_ROOT/.temporary-agent-runfiles/runs"
[ -d "$RUNS_ROOT" ] || exit 0
[ ! -L "$RUNS_ROOT" ] || { printf 'cleanup-temporary-agent-runfiles: runs root is a symbolic link\n' >&2; exit 1; }

file_mtime() {
  if [[ "$OSTYPE" == darwin* ]]; then
    stat -f %m "$1"
  else
    stat -c %Y "$1"
  fi
}

iso_epoch() {
  local value="$1"
  if [[ "$OSTYPE" == darwin* ]]; then
    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$value" +%s 2>/dev/null
  else
    date -u -d "$value" +%s 2>/dev/null
  fi
}

is_terminal() {
  case "$1" in
    completed|failed|cancelled|terminal) return 0 ;;
    *) return 1 ;;
  esac
}

is_active() {
  case "$1" in
    proposed|planned|confirmed|dispatched|running|awaiting-review) return 0 ;;
    *) return 1 ;;
  esac
}

inspect_run() {
  local run_dir="$1" run_id run_file status timestamp epoch now age
  run_id=$(basename "$run_dir")
  run_file="$run_dir/run.json"
  if [ ! -f "$run_file" ] || [ -L "$run_file" ]; then
    printf 'temporary_run_unreadable|%s|missing or linked run.json\n' "$run_id"
    return 0
  fi
  if ! jq -e 'type == "object"' "$run_file" >/dev/null 2>&1; then
    printf 'temporary_run_unreadable|%s|invalid run.json\n' "$run_id"
    return 0
  fi
  status=$(jq -r '.status // empty' "$run_file")
  if is_active "$status"; then
    printf 'temporary_run_active|%s|status: %s\n' "$run_id" "$status"
    return 0
  fi
  if ! is_terminal "$status"; then
    printf 'temporary_run_unreadable|%s|unknown status: %s\n' "$run_id" "${status:-empty}"
    return 0
  fi
  timestamp=$(jq -r '.updated_at // .finished_at // .created_at // empty' "$run_file")
  epoch=$(iso_epoch "$timestamp" 2>/dev/null || true)
  [ -n "$epoch" ] || epoch=$(file_mtime "$run_file")
  now=$(date +%s)
  age=$((now - epoch))
  if [ "$age" -ge "$RETENTION_SECONDS" ]; then
    printf 'temporary_run_terminal|%s|status: %s, age_seconds: %s\n' "$run_id" "$status" "$age"
  fi
}

for run_dir in "$RUNS_ROOT"/*; do
  [ -d "$run_dir" ] || continue
  [ ! -L "$run_dir" ] || {
    printf 'temporary_run_unreadable|%s|symbolic link run directory\n' "$(basename "$run_dir")"
    continue
  }
  finding=$(inspect_run "$run_dir")
  [ -n "$finding" ] || continue
  if [ "$ACTION" = scan ]; then
    printf '%s\n' "$finding"
    continue
  fi
  category=${finding%%|*}
  if [ "$category" = temporary_run_terminal ]; then
    rm -rf -- "$run_dir"
    printf 'temporary_run_removed|%s|%s\n' "$(basename "$run_dir")" "${finding#*|*|}"
  else
    printf '%s\n' "$finding"
  fi
done
