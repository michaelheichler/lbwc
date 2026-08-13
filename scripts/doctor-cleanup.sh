#!/bin/bash
set -euo pipefail

ACTION="${1:-scan}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
LOG_FILE="$PLANNING_DIR/.hook-errors.log"

if [ -f "$SCRIPT_DIR/resolve-claude-dir.sh" ]; then
  . "$SCRIPT_DIR/resolve-claude-dir.sh"
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_DIR="$CLAUDE_CONFIG_DIR"
elif [ -d "$HOME/.config/claude-code" ]; then
  CLAUDE_DIR="$HOME/.config/claude-code"
else
  CLAUDE_DIR="$HOME/.claude"
fi

TEAMS_DIR="$CLAUDE_DIR/teams"
TASKS_DIR="$CLAUDE_DIR/tasks"
STALE_THRESHOLD_SECONDS=7200  # 2 hours

get_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    stat -c %Y "$file" 2>/dev/null || echo "0"
  fi
}

log_action() {
  local msg="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] Doctor cleanup: $msg" >> "$LOG_FILE" 2>/dev/null || true
}

_team_inbox_latest_mtime() {
  local inbox_dir="$1" inbox_mtime=0 inbox_file file_mtime
  for inbox_file in "$inbox_dir"/*; do
    [ ! -e "$inbox_file" ] && continue
    file_mtime=$(get_mtime "$inbox_file")
    [ "$file_mtime" -gt "$inbox_mtime" ] && inbox_mtime=$file_mtime
  done
  printf '%s\n' "$inbox_mtime"
}

_scan_team_dir() {
  local team_dir="$1" now="$2" team_name inbox_dir inbox_mtime age hours minutes

  team_name=$(basename "$team_dir")

  if [ ! -f "$team_dir/config.json" ]; then
    case "$team_name" in lbwc-*)
      echo "orphaned_team|$team_name|no config.json (ghost team residual)"
      [ -d "$TASKS_DIR/$team_name" ] && echo "orphaned_tasks|$team_name|paired tasks dir (will be removed with team)"
    ;; esac
    return 0
  fi

  case "$team_name" in lbwc-*) ;; *) return 0 ;; esac

  inbox_dir="$team_dir/inboxes"
  [ ! -d "$inbox_dir" ] && return 0

  inbox_mtime=$(_team_inbox_latest_mtime "$inbox_dir")
  age=$((now - inbox_mtime))
  [ "$age" -lt "$STALE_THRESHOLD_SECONDS" ] && return 0

  hours=$((age / 3600))
  minutes=$(((age % 3600) / 60))
  echo "stale_team|$team_name|age: ${hours}h ${minutes}m"
  [ -d "$TASKS_DIR/$team_name" ] && echo "stale_tasks|$team_name|paired tasks dir (will be removed with team)"
}

scan_stale_teams() {
  [ ! -d "$TEAMS_DIR" ] && return 0

  local now team_dir
  now=$(date +%s)

  for team_dir in "$TEAMS_DIR"/*; do
    [ ! -d "$team_dir" ] && continue
    _scan_team_dir "$team_dir" "$now"
  done
}

scan_process_records() {
  local pid_file="$PLANNING_DIR/.agent-pids" record
  [ -f "$pid_file" ] || return 0

  while IFS= read -r record; do
    [ -n "$record" ] && echo "process_record|$record|scan-only"
  done < "$pid_file"

  return 0
}

pid_is_running() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac

  ps -p "$1" -o pid= 2>/dev/null | tr -d '[:space:]' | grep -qx "$1"
}

_scan_watchdog_marker() {
  local watchdog_pid_file="$PLANNING_DIR/.watchdog-pid" watchdog_pid
  [ -f "$watchdog_pid_file" ] || return 0
  watchdog_pid=$(cat "$watchdog_pid_file" 2>/dev/null)
  if [ -n "$watchdog_pid" ] && ! pid_is_running "$watchdog_pid"; then
    echo "stale_marker|.watchdog-pid|dead process"
  fi
}

_scan_compaction_marker() {
  local compaction_marker="$PLANNING_DIR/.compaction-marker" marker_mtime now age
  [ -f "$compaction_marker" ] || return 0
  marker_mtime=$(get_mtime "$compaction_marker")
  now=$(date +%s)
  age=$((now - marker_mtime))
  [ "$age" -gt 60 ] && echo "stale_marker|.compaction-marker|age: ${age}s"
  return 0
}

_scan_active_agent_marker() {
  local active_agent_file="$PLANNING_DIR/.active-agent"
  if [ -f "$active_agent_file" ] && [ ! -d "$PLANNING_DIR/.active-agents" ]; then
    echo "stale_marker|.active-agent|potentially stale"
  fi
}

scan_stale_markers() {
  _scan_watchdog_marker
  _scan_compaction_marker
  _scan_active_agent_marker
}

scan_stale_worktrees() {
  local worktrees_dir
  worktrees_dir="$(pwd)/.lbwc-worktrees"
  [ ! -d "$worktrees_dir" ] && return 0

  local now
  now=$(date +%s)

  for wt_dir in "$worktrees_dir"/*/; do
    [ ! -d "$wt_dir" ] && continue
    local wt_name
    wt_name=$(basename "$wt_dir")
    local wt_mtime
    wt_mtime=$(get_mtime "$wt_dir")
    local age=$((now - wt_mtime))
    if [ "$age" -gt "$STALE_THRESHOLD_SECONDS" ]; then
      local hours=$((age / 3600))
      local minutes=$(((age % 3600) / 60))
      echo "stale_worktree|$wt_name|age: ${hours}h ${minutes}m"
    fi
  done
}

scan_temporary_runs() {
  local project_root
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  [ -f "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" ] || return 0
  bash "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" scan --project-root "$project_root"
}

cleanup_stale_teams() {
  if [ ! -f "$SCRIPT_DIR/clean-stale-teams.sh" ]; then
    log_action "skipped stale teams cleanup: helper unavailable"
    return 0
  fi

  bash "$SCRIPT_DIR/clean-stale-teams.sh" 2>&1 | while IFS= read -r line; do
    log_action "$line"
  done
  log_action "stale teams cleanup completed"
}

report_process_records() {
  local _category record _detail
  scan_process_records | while IFS='|' read -r _category record _detail; do
    log_action "scan-only process record: $record"
  done
}

_cleanup_marker_is_stale() {
  local marker="$1" marker_file="$2" watchdog_pid marker_mtime now age
  case "$marker" in
    .watchdog-pid)
      watchdog_pid=$(cat "$marker_file" 2>/dev/null)
      [ -n "$watchdog_pid" ] && ! pid_is_running "$watchdog_pid"
      ;;
    .compaction-marker)
      marker_mtime=$(get_mtime "$marker_file")
      now=$(date +%s)
      age=$((now - marker_mtime))
      [ "$age" -gt 60 ]
      ;;
    .active-agent)
      [ ! -d "$PLANNING_DIR/.active-agents" ]
      ;;
    *)
      return 1
      ;;
  esac
}

_cleanup_stale_markers_pass() {
  local markers=(".watchdog-pid" ".compaction-marker" ".active-agent") marker marker_file removed=0

  for marker in "${markers[@]}"; do
    marker_file="$PLANNING_DIR/$marker"
    [ -f "$marker_file" ] || continue
    if _cleanup_marker_is_stale "$marker" "$marker_file"; then
      rm -f "$marker_file" 2>/dev/null && {
        log_action "removed stale marker: $marker"
        removed=$((removed + 1))
      }
    fi
  done

  printf '%s\n' "$removed"
}

cleanup_stale_markers() {
  local removed
  removed=$(_cleanup_stale_markers_pass)

  log_action "stale markers cleanup completed: $removed removed"
}

cleanup_stale_worktrees() {
  local worktrees_dir
  worktrees_dir="$(pwd)/.lbwc-worktrees"
  [ ! -d "$worktrees_dir" ] && return 0

  local stale
  stale=$(scan_stale_worktrees)
  [ -z "$stale" ] && return 0

  local _category _wt_name _detail cleanup_output
  echo "$stale" | while IFS='|' read -r _category _wt_name _detail; do
    [ -z "$_wt_name" ] && continue
    local wt_phase wt_plan
    case "$_wt_name" in
      [0-9][0-9]-[0-9][0-9]) ;;
      *)
        log_action "scan-only stale worktree: invalid cleanup target $_wt_name"
        continue
        ;;
    esac
    wt_phase="${_wt_name%-*}"
    wt_plan="${_wt_name#*-}"
    if cleanup_output=$(LBWC_AUTOMATIC_CLEANUP=1 bash "$SCRIPT_DIR/worktree-cleanup.sh" "$wt_phase" "$wt_plan" 2>&1); then
      case "$cleanup_output" in
        scan_only\|*) log_action "scan-only stale worktree: $cleanup_output" ;;
        *) log_action "cleaned stale worktree: $_wt_name ($_detail)" ;;
      esac
    else
      log_action "failed to clean worktree: $_wt_name (fail-silent)"
    fi
  done

  log_action "stale worktrees cleanup completed"
}

case "$ACTION" in
  scan)
    scan_stale_teams
    scan_process_records
    scan_stale_markers
    scan_stale_worktrees
    scan_temporary_runs
    ;;
  cleanup)
    log_action "cleanup started"

    teams_count=$(scan_stale_teams | wc -l | tr -d ' ')
    process_count=$(scan_process_records | wc -l | tr -d ' ')
    marker_count=$(scan_stale_markers | wc -l | tr -d ' ')
    worktree_count=$(scan_stale_worktrees | wc -l | tr -d ' ')
    temporary_run_count=$(scan_temporary_runs | wc -l | tr -d ' ')

    cleanup_stale_teams
    report_process_records
    cleanup_stale_markers
    cleanup_stale_worktrees
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
    bash "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" cleanup --project-root "$project_root" 2>&1 | while IFS= read -r line; do log_action "$line"; done

    log_action "cleanup complete: teams=$teams_count, process_records=$process_count, markers=$marker_count, worktrees=$worktree_count, temporary_runs=$temporary_run_count"
    ;;
  *)
    echo "Usage: $0 {scan|cleanup}" >&2
    exit 1
    ;;
esac

exit 0
