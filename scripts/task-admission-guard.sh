#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || { echo "Blocked: jq not available, cannot validate native task" >&2; exit 2; }
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
. "$SCRIPT_DIR/lib/agent-manifest.sh" 2>/dev/null || { echo "Blocked: agent manifest library unavailable" >&2; exit 2; }
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" 2>/dev/null || { echo "Blocked: control root resolver unavailable" >&2; exit 2; }

INPUT=$(cat 2>/dev/null) || { echo "Blocked: unable to read TaskCreated payload" >&2; exit 2; }
[ "$(jq -r '.hook_event_name // empty' <<< "$INPUT" 2>/dev/null)" = "TaskCreated" ] || exit 0
CWD=$(jq -r '.cwd // empty' <<< "$INPUT")
[ -n "$CWD" ] || CWD="$PWD"
CONTROL_ROOT=$(lbwc_resolve_control_root "${LBWC_CONTROL_ROOT:-}" "" "$CWD" 2>/dev/null || true)
[ -n "$CONTROL_ROOT" ] || { echo "Blocked: TaskCreated has no resolvable LBWC control root" >&2; exit 2; }
PROJECT_ROOT=$(lbwc_control_root_project_root "$CONTROL_ROOT" 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || { echo "Blocked: TaskCreated project root is unavailable" >&2; exit 2; }
TASK_ID=$(jq -r '.task_id // .taskId // empty' <<< "$INPUT")
TASK_SUBJECT=$(jq -r '.task_subject // .subject // .task_description // empty' <<< "$INPUT")
[ -n "$TASK_ID" ] && [ -n "$TASK_SUBJECT" ] || { echo "Blocked: TaskCreated payload is missing task identity" >&2; exit 2; }

bind_native_task_locked() {
  local manifest candidates entry contract_path contract updated now
  manifest=$(agent_manifest_read "$CONTROL_ROOT") || return 1
  candidates=$(jq -c --arg subject "$TASK_SUBJECT" '
    [.agents[]
      | select(.schema_version == 3 and .runtime_kind == "native-team" and .communication_policy == "native-team")
      | select(.contract_id == $subject or .task_identity == $subject)]
    | unique_by(.contract_id)
  ' <<< "$manifest") || return 1
  [ "$(jq 'length' <<< "$candidates")" -eq 1 ] || return 2
  entry=$(jq -c '.[0]' <<< "$candidates") || return 1
  contract_path=$(jq -r '.contract_path // empty' <<< "$entry")
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$contract_path" "$PROJECT_ROOT" 2>/dev/null) || return 3
  jq -e '.schema_version == 3 and .runtime_kind == "native-team" and (.state == "planned" or .state == "dispatched")' <<< "$contract" >/dev/null 2>&1 || return 3
  jq -e --arg id "$TASK_ID" '.tasks[$id] == null' <<< "$manifest" >/dev/null 2>&1 || return 4
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || return 1
  updated=$(jq -c --arg id "$TASK_ID" --arg subject "$TASK_SUBJECT" --arg now "$now" --argjson entry "$entry" '
    .tasks = (.tasks // {})
    | .tasks[$id] = {
        native_task_id:$id,
        contract_id:$entry.contract_id,
        contract_path:$entry.contract_path,
        contract_digest:$entry.contract_digest,
        subject:$subject,
        state:"created",
        created_at:$now
      }
  ' <<< "$manifest") || return 1
  agent_manifest_write "$CONTROL_ROOT" "$updated"
}

agent_manifest_with_lock "$CONTROL_ROOT" bind_native_task_locked
status=$?
case "$status" in
  0) exit 0 ;;
  2) echo "Blocked: no pending native-team contract matches TaskCreated subject '$TASK_SUBJECT'" >&2 ;;
  3) echo "Blocked: pending native-team contract is missing, stale, or invalid" >&2 ;;
  4) echo "Blocked: native task '$TASK_ID' is already bound" >&2 ;;
  *) echo "Blocked: native task binding could not be persisted" >&2 ;;
esac
exit 2
