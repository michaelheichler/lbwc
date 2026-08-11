#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/resolve-claude-dir.sh"

TEAMS_DIR="$CLAUDE_DIR/teams"
TASKS_DIR="$CLAUDE_DIR/tasks"
PLANNING_DIR="${LBWC_PLANNING_DIR:-$(pwd -P)/.lbwc-planning}"
STALE_SECONDS="${LBWC_STALE_TEAM_SECONDS:-7200}"
LOG_FILE="$PLANNING_DIR/.hook-errors.log"

case "$STALE_SECONDS" in
  ''|*[!0-9]*) printf '%s\n' 'LBWC: invalid stale team threshold' >&2; exit 1 ;;
esac

teams_cleaned=0
tasks_cleaned=0

file_mtime() {
  local path="$1"
  stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null || printf '0\n'
}

log_cleanup() {
  local message="$1" timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date +'%Y-%m-%dT%H:%M:%SZ')
  mkdir -p "$PLANNING_DIR" 2>/dev/null || return 0
  printf '[%s] %s\n' "$timestamp" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

move_owned_path() {
  local path="$1" destination="$2"
  [ -e "$path" ] || return 0
  mv "$path" "$destination" 2>/dev/null
}

[ -d "$TEAMS_DIR" ] || {
  printf 'teams_cleaned=0\ntasks_cleaned=0\n'
  exit 0
}

cleanup_dir=$(mktemp -d "${TMPDIR:-/tmp}/lbwc-stale-teams.XXXXXX")
trap 'rm -rf "$cleanup_dir"' EXIT HUP INT TERM
now=$(date +%s)

for team_dir in "$TEAMS_DIR"/lbwc-*; do
  [ -d "$team_dir" ] || continue
  [ ! -L "$team_dir" ] || continue
  team_name=$(basename "$team_dir")
  remove_team=false

  if [ ! -f "$team_dir/config.json" ]; then
    remove_team=true
  elif [ -d "$team_dir/inboxes" ]; then
    newest=0
    for inbox_file in "$team_dir/inboxes"/*; do
      [ -e "$inbox_file" ] || continue
      mtime=$(file_mtime "$inbox_file")
      [ "$mtime" -le "$newest" ] || newest="$mtime"
    done
    [ $((now - newest)) -lt "$STALE_SECONDS" ] || remove_team=true
  fi

  [ "$remove_team" = true ] || continue
  if move_owned_path "$team_dir" "$cleanup_dir/$team_name"; then
    teams_cleaned=$((teams_cleaned + 1))
    log_cleanup "Removed stale team: $team_name"
  fi
  if move_owned_path "$TASKS_DIR/$team_name" "$cleanup_dir/${team_name}-tasks"; then
    tasks_cleaned=$((tasks_cleaned + 1))
  fi
done

printf 'teams_cleaned=%s\ntasks_cleaned=%s\n' "$teams_cleaned" "$tasks_cleaned"
