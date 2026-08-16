#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "$SCRIPT_DIR/lib/lbwc-control-root.sh"

usage() {
  printf '%s\n' 'Usage: tmux-preflight.sh --project-root PATH --control-root PATH --main-id ID' >&2
}

fail() {
  printf 'tmux preflight failed: %s\n' "$1" >&2
  exit 1
}

require_option_value() {
  [ "$#" -ge 2 ] || fail "$1 requires a value"
}

tmux_version_is_supported() {
  local version="$1" major minor
  [[ "$version" =~ ^tmux[[:space:]]+([0-9]+)\.([0-9]+) ]] || return 1
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 0 ]; }
}

project_root=""
requested_control_root=""
main_id=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      require_option_value "$@"
      project_root="$2"
      shift 2
      ;;
    --control-root)
      require_option_value "$@"
      requested_control_root="$2"
      shift 2
      ;;
    --main-id)
      require_option_value "$@"
      main_id="$2"
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
[ -n "$requested_control_root" ] || fail '--control-root is required'
[ -n "$main_id" ] || fail '--main-id is required'
[ -d "$project_root" ] || fail "project root does not exist: $project_root"
command -v tmux >/dev/null 2>&1 || fail 'tmux is unavailable; install tmux 3.0 or later'
command -v claude >/dev/null 2>&1 || fail 'claude is unavailable on PATH; install or expose the Claude Code CLI'
command -v jq >/dev/null 2>&1 || fail 'jq is unavailable; install jq to manage the tmux registry'
command -v python3 >/dev/null 2>&1 || fail 'python3 is unavailable; install Python 3 for private tmux runtime verification'

tmux_version=$(tmux -V 2>/dev/null || true)
tmux_version_is_supported "$tmux_version" || fail "tmux 3.0 or later is required; found: ${tmux_version:-unreadable}"

project_root=$(cd "$project_root" && pwd -P)
control_root=$(lbwc_resolve_control_root "$requested_control_root" "$project_root" "$project_root" 2>/dev/null || true)
[ -n "$control_root" ] || fail "control root is invalid: $requested_control_root"
resolved_project_root=$(lbwc_control_root_project_root "$control_root" 2>/dev/null || true)
[ "$resolved_project_root" = "$project_root" ] || fail 'control root does not belong to --project-root'

runtime_dir="$control_root/.runtime"
bus_dir="$runtime_dir/tmux-bus"
if [ -e "$bus_dir" ]; then
  [ -d "$bus_dir" ] && [ ! -L "$bus_dir" ] || fail "tmux bus path is unsafe: $bus_dir"
  python3 "$SCRIPT_DIR/lib/tmux-private-fs.py" probe --root "$bus_dir" || fail "tmux bus directory is not safely writable: $bus_dir"
else
  created_runtime=false
  if [ -e "$runtime_dir" ]; then
    [ -d "$runtime_dir" ] && [ ! -L "$runtime_dir" ] || fail "tmux runtime parent is unsafe: $runtime_dir"
  else
    mkdir "$runtime_dir" 2>/dev/null || fail "tmux runtime parent is not writable: $control_root"
    chmod 700 "$runtime_dir" || { rmdir "$runtime_dir" 2>/dev/null || true; fail "cannot secure tmux runtime parent: $runtime_dir"; }
    created_runtime=true
  fi
  python3 "$SCRIPT_DIR/lib/tmux-private-fs.py" probe --root "$runtime_dir" || { [ "$created_runtime" = true ] && rmdir "$runtime_dir" 2>/dev/null || true; fail "tmux runtime parent is not safely writable: $runtime_dir"; }
  [ "$created_runtime" = false ] || rmdir "$runtime_dir" || fail "cannot remove tmux runtime preflight parent: $runtime_dir"
fi

if [ -n "${TMUX:-}" ]; then
  [ -n "${TMUX_PANE:-}" ] || fail 'TMUX is set but TMUX_PANE is unavailable; cannot identify the attached orchestrator pane'
  attached_session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || true)
  [ -n "$attached_session" ] || fail 'cannot resolve the current tmux pane; run preflight from an active tmux pane or outside tmux'
  [[ "$attached_session" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail 'attached tmux session contains unsupported characters for the private registry'
  jq -n --arg topology 'attached-existing-tmux' --arg session "$attached_session" --arg control_root "$control_root" \
    '{preflight: "passed", topology: $topology, tmux_session: $session, control_root: $control_root}'
  exit 0
fi

session=$(bash "$SCRIPT_DIR/tmux-session-name.sh" --project-root "$project_root" --main-id "$main_id") || fail 'cannot derive a safe tmux session name'
if tmux has-session -t "$session" 2>/dev/null; then
  fail "tmux session already exists for this main ID: $session; inspect or clean up the orphan before retrying"
fi

jq -n --arg topology 'detached-new-session' --arg session "$session" --arg control_root "$control_root" \
  '{preflight: "passed", topology: $topology, tmux_session: $session, control_root: $control_root}'
