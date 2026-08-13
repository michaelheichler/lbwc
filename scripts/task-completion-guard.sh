#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || { echo "Blocked: jq not available, cannot validate native task completion" >&2; exit 2; }
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "$SCRIPT_DIR/lib/agent-manifest.sh" 2>/dev/null || { echo "Blocked: agent manifest library unavailable" >&2; exit 2; }
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" 2>/dev/null || { echo "Blocked: control root resolver unavailable" >&2; exit 2; }

INPUT=$(cat 2>/dev/null) || { echo "Blocked: unable to read TaskCompleted payload" >&2; exit 2; }
[ "$(jq -r '.hook_event_name // empty' <<< "$INPUT" 2>/dev/null)" = "TaskCompleted" ] || exit 0
CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
[ -n "$CWD" ] || CWD="$PWD"
CONTROL_ROOT=$(lbwc_resolve_control_root "${LBWC_CONTROL_ROOT:-}" "" "$CWD" 2>/dev/null || true)
[ -n "$CONTROL_ROOT" ] || { echo "Blocked: TaskCompleted has no resolvable LBWC control root" >&2; exit 2; }
PROJECT_ROOT=$(lbwc_control_root_project_root "$CONTROL_ROOT" 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || { echo "Blocked: TaskCompleted project root is unavailable" >&2; exit 2; }
TASK_ID=$(jq -r '.task_id // .taskId // empty' <<< "$INPUT")
[ -n "$TASK_ID" ] || { echo "Blocked: TaskCompleted payload is missing task identity" >&2; exit 2; }

complete_native_task_locked() {
  local manifest binding contract updated now
  manifest=$(agent_manifest_read "$CONTROL_ROOT") || return 1
  binding=$(jq -ce --arg id "$TASK_ID" '.tasks[$id] // empty' <<< "$manifest") || return 2
  [ "$(jq -r '.state // empty' <<< "$binding")" = "created" ] || return 3
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$(jq -r '.contract_path' <<< "$binding")" "$PROJECT_ROOT" 2>/dev/null) || return 3
  jq -e --arg id "$(jq -r '.contract_id' <<< "$binding")" --arg digest "$(jq -r '.contract_digest' <<< "$binding")" '
    .schema_version == 3
    and .runtime_kind == "native-team"
    and .contract_id == $id
    and .contract_digest == $digest
    and .state == "verified"
  ' <<< "$contract" >/dev/null 2>&1 || return 4
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || return 1
  updated=$(jq -c --arg id "$TASK_ID" --arg now "$now" '.tasks[$id].state = "completed" | .tasks[$id].completed_at = $now' <<< "$manifest") || return 1
  agent_manifest_write "$CONTROL_ROOT" "$updated"
}

agent_manifest_with_lock "$CONTROL_ROOT" complete_native_task_locked
status=$?
case "$status" in
  0) exit 0 ;;
  2) echo "Blocked: native task '$TASK_ID' has no LBWC contract binding" >&2 ;;
  4) echo "Blocked: native task '$TASK_ID' contract is not verified" >&2 ;;
  *) echo "Blocked: native task '$TASK_ID' binding is invalid or completion could not be persisted" >&2 ;;
esac
exit 2
