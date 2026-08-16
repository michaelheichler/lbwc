#!/usr/bin/env bash
set -u

command -v jq >/dev/null 2>&1 || {
  printf 'LBWC status unavailable: jq is required\n'
  exit 0
}

STATUS_INPUT=$(cat 2>/dev/null) || STATUS_INPUT=""
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$STATUS_INPUT"; then
  printf 'LBWC status unavailable: invalid Claude Code input\n'
  exit 0
fi

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
BLUE='\033[34m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

sanitize_label() {
  printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-64
}

format_tokens() {
  local value="${1:-0}"
  case "$value" in ''|*[!0-9]*) value=0 ;; esac
  if [ "$value" -ge 1000000 ]; then
    awk -v value="$value" 'BEGIN { printf "%.1fM", value / 1000000 }'
  elif [ "$value" -ge 1000 ]; then
    awk -v value="$value" 'BEGIN { printf "%.1fK", value / 1000 }'
  else
    printf '%s' "$value"
  fi
}

format_duration() {
  local milliseconds="${1:-0}" seconds
  case "$milliseconds" in ''|*[!0-9]*) milliseconds=0 ;; esac
  seconds=$((milliseconds / 1000))
  if [ "$seconds" -ge 3600 ]; then
    printf '%dh %dm' $((seconds / 3600)) $(((seconds % 3600) / 60))
  elif [ "$seconds" -ge 60 ]; then
    printf '%dm %ds' $((seconds / 60)) $((seconds % 60))
  else
    printf '%ds' "$seconds"
  fi
}

progress_bar() {
  local percent="${1:-0}" filled empty color
  case "$percent" in ''|*[!0-9]*) percent=0 ;; esac
  [ "$percent" -gt 100 ] && percent=100
  filled=$((percent / 10))
  [ "$percent" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  empty=$((10 - filled))
  if [ "$percent" -ge 80 ]; then color="$RED"
  elif [ "$percent" -ge 55 ]; then color="$YELLOW"
  else color="$GREEN"
  fi
  printf '%b' "$color"
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%b' "$DIM"
  printf '%*s' "$empty" '' | tr ' ' '.'
  printf '%b' "$RESET"
}

format_reset() {
  local value="${1:-}"
  [ -n "$value" ] || { printf 'unknown'; return; }
  case "$value" in
    *[!0-9]*) sanitize_label "$value" ;;
    *)
      if [ "$(uname)" = "Darwin" ]; then
        date -r "$value" '+%a %H:%M' 2>/dev/null || printf 'unknown'
      else
        date -d "@$value" '+%a %H:%M' 2>/dev/null || printf 'unknown'
      fi
      ;;
  esac
}

read_frontmatter_value() {
  local path="$1" key="$2"
  [ -f "$path" ] || return 0
  awk -v key="$key" '
    NR == 1 && /^---[[:space:]]*$/ { frontmatter = 1; next }
    frontmatter && /^---[[:space:]]*$/ { exit }
    frontmatter && index($0, key ":") == 1 {
      sub("^[^:]*:[[:space:]]*", "")
      gsub(/["'\''[:space:]]/, "")
      print
      exit
    }
  ' "$path" 2>/dev/null
}

latest_matching_file() {
  local directory="$1" pattern="$2" path latest=""
  [ -d "$directory" ] || return 0
  for path in "$directory"/$pattern; do
    [ -f "$path" ] || continue
    latest="$path"
  done
  [ -n "$latest" ] && printf '%s\n' "$latest"
}

read_native_fields() {
  jq -r '[
    (.model.display_name // .model.id // "Claude"),
    (.effort // .model.effort // .model.reasoning_effort // "default"),
    (.workspace.project_dir // .workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // 0 | floor),
    (.context_window.current_usage.input_tokens // 0 | floor),
    (.context_window.current_usage.output_tokens // 0 | floor),
    (.context_window.current_usage.cache_creation_input_tokens // 0 | floor),
    (.context_window.current_usage.cache_read_input_tokens // 0 | floor),
    (.cost.total_cost_usd // 0),
    (.cost.total_duration_ms // 0 | floor),
    (.cost.total_lines_added // 0 | floor),
    (.cost.total_lines_removed // 0 | floor),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("\u001f")' <<< "$STATUS_INPUT"
}

read_orchestration_state() {
  PHASE="none"
  TASK="none"
  PAIR="none"
  TRIO="none"
  QA_STATE="pending"
  UAT_STATE="pending"
  TELEMETRY_STATE="off"

  [ -d "$PLANNING_DIR" ] || return 0
  local manifest="$PLANNING_DIR/.agent-manifest.json" active phase_dir="" contract_path
  if [ -f "$manifest" ] && active=$(jq -ce '[.agents[] | select(.state == "registered" or .state == "running")]' "$manifest" 2>/dev/null); then
    TASK=$(jq -r 'map(.task_identity // empty) | first // "none"' <<< "$active")
    PAIR=$(jq -r '[group_by(.pair_id)[] | select(.[0].pair_id != null and length == 2)] | if length == 0 then "none" else (length|tostring) + " active (" + (.[0] | map(.role) | join("+")) + ")" end' <<< "$active")
    TRIO=$(jq -r '[group_by(.pair_id)[] | select(.[0].pair_id != null and length == 3)] | if length == 0 then "none" else (length|tostring) + " active (" + (.[0] | map(.role) | join("+")) + ")" end' <<< "$active")
    contract_path=$(jq -r 'map(.contract_path // empty) | first // empty' <<< "$active")
    if [ -f "$contract_path" ]; then
      PHASE=$(jq -r '.phase // "none"' "$contract_path" 2>/dev/null || printf 'none')
    fi
  fi

  if [ "$PHASE" = "none" ] && [ -f "$PLANNING_DIR/STATE.md" ]; then
    PHASE=$(sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PLANNING_DIR/STATE.md" 2>/dev/null | head -1)
    PHASE=${PHASE:-none}
  fi

  case "$PHASE" in
    ''|*[!0-9]*) ;;
    *)
      if [ -d "$PLANNING_DIR/phases" ]; then
        for phase_dir in "$PLANNING_DIR/phases"/"$(printf '%02d' "$((10#$PHASE))")"-*/; do
          [ -d "$phase_dir" ] && break
          phase_dir=""
        done
      fi
      ;;
  esac
  if [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
    local verification uat
    verification=$(latest_matching_file "$phase_dir" '*-VERIFICATION.md')
    uat=$(latest_matching_file "$phase_dir" '*-UAT.md')
    [ -n "$verification" ] && QA_STATE=$(read_frontmatter_value "$verification" result)
    [ -n "$uat" ] && UAT_STATE=$(read_frontmatter_value "$uat" status)
    QA_STATE=${QA_STATE:-pending}
    UAT_STATE=${UAT_STATE:-pending}
  fi

  local telemetry="$PLANNING_DIR/telemetry/session.jsonl" report total outcomes
  if [ -f "$telemetry" ]; then
    report=$(bash "$SCRIPT_DIR/telemetry-report.sh" --root "$PLANNING_DIR" 2>/dev/null) || report=""
    if jq -e 'type == "object"' >/dev/null 2>&1 <<< "$report"; then
      total=$(jq -r '.total // 0' <<< "$report")
      outcomes=$(jq -r '.outcomes | to_entries | map(.key + ":" + (.value|tostring)) | join(",")' <<< "$report")
      TELEMETRY_STATE="$total events${outcomes:+ ($outcomes)}"
    else
      TELEMETRY_STATE="tamper/error"
    fi
  fi
}

read_tmux_runtime_state() {
  TMUX_BACKEND='in_process'
  TMUX_HIDE_AGENT='false'
  TMUX_COLLAPSE_AGENT='false'
  TMUX_SESSION='none'
  TMUX_SESSION_STATUS='unavailable'
  TMUX_PANES='0/0'
  TMUX_AGENT_TOTAL=0
  TMUX_RUNNING=0
  TMUX_IDLE=0
  TMUX_FAILED=0
  TMUX_STALE=0
  TMUX_DIAGNOSTICS=''

  [ -f "$PLANNING_DIR/config.json" ] || return 0
  if ! jq -e '
    type == "object"
    and (if has("agent_execution_mode") then (.agent_execution_mode | type == "string" and (. == "in_process" or . == "tmux" or . == "ask")) else true end)
    and (if has("statusline_hide_agent_in_tmux") then (.statusline_hide_agent_in_tmux | type == "boolean") else true end)
    and (if has("statusline_collapse_agent_in_tmux") then (.statusline_collapse_agent_in_tmux | type == "boolean") else true end)
  ' "$PLANNING_DIR/config.json" >/dev/null 2>&1; then
    TMUX_BACKEND='invalid'
    TMUX_DIAGNOSTICS='configuration drift'
    return 0
  fi
  TMUX_BACKEND=$(jq -r '.agent_execution_mode // "in_process"' "$PLANNING_DIR/config.json" 2>/dev/null) || {
    TMUX_BACKEND='invalid'
    TMUX_DIAGNOSTICS='configuration drift'
    return 0
  }
  TMUX_HIDE_AGENT=$(jq -r '.statusline_hide_agent_in_tmux // false' "$PLANNING_DIR/config.json")
  TMUX_COLLAPSE_AGENT=$(jq -r '.statusline_collapse_agent_in_tmux // false' "$PLANNING_DIR/config.json")
  [ "$TMUX_BACKEND" = tmux ] || return 0

  local runtime="$PLANNING_DIR/.runtime/tmux-bus" registry now lock_now pane_count expected_panes lock owner acquired lease
  registry="$runtime/registry.json"
  [ -f "$registry" ] || {
    TMUX_DIAGNOSTICS='missing registry'
    return 0
  }
  if ! jq -e 'type == "object" and (.tmux | type == "object") and (.agents | type == "array")' "$registry" >/dev/null 2>&1; then
    TMUX_DIAGNOSTICS='malformed registry'
    return 0
  fi

  TMUX_SESSION=$(jq -r '.tmux.session // "none"' "$registry")
  TMUX_AGENT_TOTAL=$(jq '[.agents[]] | length' "$registry")
  TMUX_RUNNING=$(jq '[.agents[] | select(.state == "running")] | length' "$registry")
  TMUX_IDLE=$(jq '[.agents[] | select(.state == "idle")] | length' "$registry")
  TMUX_FAILED=$(jq '[.agents[] | select(.state == "failed")] | length' "$registry")
  now=$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000' 2>/dev/null || printf '0')
  lock_now=$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000' 2>/dev/null || printf '0')
  TMUX_STALE=$(jq --argjson now "$now" --argjson threshold "$(jq -r '.tmux_execution.heartbeat_stale_seconds // 120' "$PLANNING_DIR/config.json" 2>/dev/null || printf 120)000" '[.agents[] | select(.heartbeat_at_ms != null and (.heartbeat_at_ms + $threshold) <= $now)] | length' "$registry" 2>/dev/null || printf 0)

  if command -v tmux >/dev/null 2>&1 && [ "$TMUX_SESSION" != none ] && tmux has-session -t "$TMUX_SESSION" >/dev/null 2>&1; then
    TMUX_SESSION_STATUS='up'
    pane_count=$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_index}' 2>/dev/null | wc -l | tr -d ' ')
    expected_panes=$((TMUX_AGENT_TOTAL + 1))
    TMUX_PANES="${pane_count}/${expected_panes}"
  else
    TMUX_SESSION_STATUS='down'
  fi

  while IFS= read -r lock; do
    [ -d "$lock" ] || continue
    owner="$lock/owner.json"
    [ -f "$owner" ] || { TMUX_DIAGNOSTICS='malformed lock'; break; }
    acquired=$(jq -r '.acquired_at_ms // -1' "$owner" 2>/dev/null || printf -- -1)
    lease=$(jq -r '.lease_ms // -1' "$owner" 2>/dev/null || printf -- -1)
    if [[ "$acquired" =~ ^[0-9]+$ ]] && [[ "$lease" =~ ^[1-9][0-9]*$ ]] && [ "$lock_now" -ge $((acquired + lease)) ]; then
      TMUX_DIAGNOSTICS='stale lock'
      break
    fi
  done < <(find "$runtime/locks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  [ -n "$TMUX_DIAGNOSTICS" ] || [ "$TMUX_FAILED" -eq 0 ] || TMUX_DIAGNOSTICS='failed agent'
}

is_git_worktree() {
  local git_dir common_dir
  git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git_dir=$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  common_dir=$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$git_dir" != "$common_dir" ]
}

IFS=$'\x1f' read -r MODEL EFFORT PROJECT_ROOT CONTEXT_PERCENT INPUT_TOKENS OUTPUT_TOKENS CACHE_CREATE CACHE_READ COST DURATION_MS LINES_ADDED LINES_REMOVED FIVE_PERCENT FIVE_RESET SEVEN_PERCENT SEVEN_RESET <<< "$(read_native_fields)"
PROJECT_ROOT=${PROJECT_ROOT:-$PWD}
[ -d "$PROJECT_ROOT" ] || PROJECT_ROOT="$PWD"
PROJECT_NAME=$(sanitize_label "$(basename "$PROJECT_ROOT")")
MODEL=$(sanitize_label "${MODEL:-Claude}")
EFFORT=$(sanitize_label "${EFFORT:-default}")
BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || printf 'no-git')
BRANCH=$(sanitize_label "${BRANCH:-detached}")
if git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal 2>/dev/null | grep -q .; then
  DIRTY='dirty'
  DIRTY_COLOR="$YELLOW"
else
  DIRTY='clean'
  DIRTY_COLOR="$GREEN"
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
PLANNING_DIR="$PROJECT_ROOT/.lbwc-planning"
read_orchestration_state
IN_TMUX='false'
[ -n "${TMUX:-}" ] && IN_TMUX='true'
[ "$IN_TMUX" = true ] && read_tmux_runtime_state

if [ "$IN_TMUX" = true ] && [ "$TMUX_COLLAPSE_AGENT" = true ] && is_git_worktree; then
  printf '%bLBWC%b %s@%s  %b%s%b  %s  TMUX agents %s running:%s idle:%s failed:%s stale:%s' "$BOLD$CYAN" "$RESET" "$PROJECT_NAME" "$BRANCH" "$DIRTY_COLOR" "$DIRTY" "$RESET" "$(format_duration "$DURATION_MS")" "$TMUX_AGENT_TOTAL" "$TMUX_RUNNING" "$TMUX_IDLE" "$TMUX_FAILED" "$TMUX_STALE"
  [ -z "$TMUX_DIAGNOSTICS" ] || printf '  Diagnostics %s' "$TMUX_DIAGNOSTICS"
  printf '\n'
  exit 0
fi

printf '%bLBWC%b %b%s%b  %b%s%b  %s@%s  %b%s%b  %s\n' "$BOLD$CYAN" "$RESET" "$MAGENTA" "$MODEL" "$RESET" "$BLUE" "$EFFORT" "$RESET" "$PROJECT_NAME" "$BRANCH" "$DIRTY_COLOR" "$DIRTY" "$RESET" "$(format_duration "$DURATION_MS")"
printf '%bContext%b [' "$BOLD" "$RESET"
progress_bar "$CONTEXT_PERCENT"
printf '] %s%%  in %s  out %s  cache %s/%s  cost $%.2f  lines %b+%s%b/%b-%s%b\n' "$CONTEXT_PERCENT" "$(format_tokens "$INPUT_TOKENS")" "$(format_tokens "$OUTPUT_TOKENS")" "$(format_tokens "$CACHE_READ")" "$(format_tokens "$CACHE_CREATE")" "$COST" "$GREEN" "$LINES_ADDED" "$RESET" "$RED" "$LINES_REMOVED" "$RESET"
if [ -n "$FIVE_PERCENT" ] || [ -n "$SEVEN_PERCENT" ]; then
  printf '%bQuota%b ' "$BOLD" "$RESET"
  if [ -n "$FIVE_PERCENT" ]; then
    FIVE_PERCENT=${FIVE_PERCENT%.*}
    printf '5h ['; progress_bar "$FIVE_PERCENT"; printf '] %s%% reset %s' "$FIVE_PERCENT" "$(format_reset "$FIVE_RESET")"
  fi
  if [ -n "$SEVEN_PERCENT" ]; then
    SEVEN_PERCENT=${SEVEN_PERCENT%.*}
    [ -n "$FIVE_PERCENT" ] && printf '  '
    printf '7d ['; progress_bar "$SEVEN_PERCENT"; printf '] %s%% reset %s' "$SEVEN_PERCENT" "$(format_reset "$SEVEN_RESET")"
  fi
  printf '\n'
fi
if [ "$IN_TMUX" != true ] || [ "$TMUX_HIDE_AGENT" != true ]; then
  printf '%bFlow%b phase %s  task %s  pair %s  trio %s\n' "$BOLD" "$RESET" "$(sanitize_label "$PHASE")" "$(sanitize_label "$TASK")" "$(sanitize_label "$PAIR")" "$(sanitize_label "$TRIO")"
fi
printf '%bQuality%b QA %s  UAT %s  %bTelemetry%b %s\n' "$BOLD" "$RESET" "$(sanitize_label "$QA_STATE")" "$(sanitize_label "$UAT_STATE")" "$BOLD" "$RESET" "$(sanitize_label "$TELEMETRY_STATE")"
if [ "$IN_TMUX" = true ]; then
  printf 'Backend %s\n' "$(sanitize_label "$TMUX_BACKEND")"
  if [ "$TMUX_BACKEND" = tmux ]; then
    printf 'TMUX session %s %s  panes %s  agents %s running:%s idle:%s failed:%s  stale %s failed %s\n' "$(sanitize_label "$TMUX_SESSION")" "$TMUX_SESSION_STATUS" "$TMUX_PANES" "$TMUX_AGENT_TOTAL" "$TMUX_RUNNING" "$TMUX_IDLE" "$TMUX_FAILED" "$TMUX_STALE" "$TMUX_FAILED"
  fi
  [ -z "$TMUX_DIAGNOSTICS" ] || printf 'Diagnostics %s\n' "$TMUX_DIAGNOSTICS"
fi
