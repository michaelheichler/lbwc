#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || {
  echo "Blocked: jq not available, cannot validate agent spawn" >&2
  exit 2
}

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/lib/agent-manifest.sh" ] || exit 0
. "$SCRIPT_DIR/lib/agent-manifest.sh" || exit 0
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
case "$TOOL_NAME" in
  Agent|TaskCreate) ;;
  *) exit 0 ;;
esac

SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // .tool_input.agent_type // .tool_input.name // ""' 2>/dev/null) || exit 0

block_unresolved_generated_identity() {
  case "$SUBAGENT_TYPE" in
    lbwc-*) echo "Blocked: generated LBWC identity has no resolvable control root or manifest" >&2; exit 2 ;;
  esac
  exit 0
}

CONTROL_ROOT=$(lbwc_resolve_control_root "" "" "$PWD" 2>/dev/null || true)
[ -n "$CONTROL_ROOT" ] || block_unresolved_generated_identity
PROJECT_ROOT=$(lbwc_control_root_project_root "$CONTROL_ROOT" 2>/dev/null || true)
[ -n "$PROJECT_ROOT" ] || block_unresolved_generated_identity
PLANNING_DIR="$CONTROL_ROOT"
MANIFEST_PATH=$(agent_manifest_path "$PLANNING_DIR" 2>/dev/null) || block_unresolved_generated_identity
[ -f "$MANIFEST_PATH" ] || block_unresolved_generated_identity

requested_cwd_values() {
  echo "$INPUT" | jq -r '[.tool_input.cwd? // empty, .tool_input.working_dir? // empty, .tool_input.workingDirectory? // empty, .tool_input.workdir? // empty] | map(select(type == "string")) | .[]' 2>/dev/null \
    || return 1
}

requested_sidechain_cwd() {
  requested_cwd_values | grep -Eq '(^|/)\.lbwc-worktrees/agent-[^/]+(/|$)'
}

requested_worktree_isolation() {
  local isolation=""
  isolation=$(echo "$INPUT" | jq -r '.tool_input.isolation // ""' 2>/dev/null) || return 1
  [ "$isolation" = "worktree" ]
}

STRIP_REASON=""
STRIP_WARN=""
STRIPPED_INPUT=""
if requested_sidechain_cwd; then
  STRIPPED_INPUT=$(echo "$INPUT" | jq '.tool_input | del(.cwd, .working_dir, .workingDirectory, .workdir, .isolation)' 2>/dev/null)
  STRIP_REASON="lbwc stripped sidechain cwd fields, worktree targeting is task metadata, not spawn cwd"
  STRIP_WARN="lbwc guard: stripped sidechain cwd fields from spawn (models add these spontaneously, blocking causes retry loops)"
elif requested_worktree_isolation; then
  STRIPPED_INPUT=$(echo "$INPUT" | jq '.tool_input | del(.isolation)' 2>/dev/null)
  STRIP_REASON="lbwc stripped isolation:worktree, worktree isolation is not managed via spawn params"
  STRIP_WARN="lbwc guard: stripped isolation:worktree from spawn (models add this spontaneously, blocking causes retry loops)"
fi

emit_updated_input() {
  local updated_input="$1" reason="$2" compact_input
  compact_input=$(echo "$updated_input" | jq -c '.' 2>/dev/null) || compact_input="$updated_input"
  jq -n -c --arg reason "$reason" --argjson input "$compact_input" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":$reason,"updatedInput":$input}}'
}

allow_with_strip() {
  if [ -n "$STRIP_REASON" ] && [ -n "$STRIPPED_INPUT" ] && [ "$STRIPPED_INPUT" != "null" ]; then
    [ -n "$STRIP_WARN" ] && echo "$STRIP_WARN" >&2
    emit_updated_input "$STRIPPED_INPUT" "$STRIP_REASON"
  fi
  exit 0
}

[ -n "$SUBAGENT_TYPE" ] || allow_with_strip

find_blocking_open_pair() {
  local manifest="$1" name="$2"
  jq -c --arg name "$name" '
    def reached_running: (.state == "running") or (.state == "used") or (.state == "expired");
    (.agents | to_entries
      | map(select(.value.pair_id != null))
      | group_by(.value.pair_id)
      | map(select(length > 1))
      | map(select((map(.value | reached_running) | all) | not))
    ) as $open
    | ($open | map(select(any(.[]; .key == $name) | not))) as $blocking
    | if ($blocking | length) > 0 then
        ($blocking[0] | sort_by(.value.pair_role // .value.role)) as $sorted
        | {pair_id: $sorted[0].value.pair_id,
           members: [$sorted[] | {role: (.value.pair_role // .value.role), name: .key}]}
      else empty end
  ' <<< "$manifest" 2>/dev/null
}

validate_entry_contract() {
  local name="$1" entry="$2" manifest="$3" contract_path contract contract_id contract_digest task_identity role allowances team_mode pair_id manifest_roles contract_roles
  contract_path=$(jq -r '.contract_path // empty' <<< "$entry")
  [ -n "$contract_path" ] || return 1
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$contract_path" "$PROJECT_ROOT" 2>/dev/null) || return 1
  jq -e '.state == "dispatched"' <<< "$contract" >/dev/null 2>&1 || return 1
  contract_id=$(jq -r '.contract_id // empty' <<< "$contract")
  contract_digest=$(jq -r '.contract_digest // empty' <<< "$contract")
  task_identity=$(jq -r '.task_identity // empty' <<< "$contract")
  role=$(jq -r '.role // empty' <<< "$entry")
  allowances=$(jq -c '.write_allowances // []' <<< "$entry")
  jq -e --arg id "$contract_id" --arg digest "$contract_digest" --arg task "$task_identity" \
    --arg role "$role" --argjson allowances "$allowances" '
      .contract_enabled == true
      and .contract_id == $id
      and .contract_digest == $digest
      and .task_identity == $task
      and .role == $role
      and $id != ""
    ' <<< "$entry" >/dev/null 2>&1 || return 1
  jq -e --arg role "$role" --argjson allowances "$allowances" '.allowances_by_role[$role] == $allowances' <<< "$contract" >/dev/null 2>&1 || return 1
  team_mode=$(jq -r '.team_mode' <<< "$contract")
  pair_id=$(jq -r '.pair_id // empty' <<< "$entry")
  if [ "$team_mode" = "solo" ]; then
    [ -z "$pair_id" ] || return 1
  else
    [ -n "$pair_id" ] || return 1
    manifest_roles=$(jq -c --arg pair "$pair_id" '[.agents[] | select(.pair_id == $pair) | .role]' <<< "$manifest") || return 1
    contract_roles=$(jq -c '.roles' <<< "$contract") || return 1
    [ "$manifest_roles" = "$contract_roles" ] || return 1
  fi
  return 0
}

_mark_manifest_running() {
  local name="$1" manifest="$2" entry="$3" spawn_fields current now updated
  spawn_fields=$(jq -c '{model, maxTurns, permissionMode} | with_entries(select(.value != null))' <<< "$entry" 2>/dev/null) || return 1
  current="$STRIPPED_INPUT"
  [ -n "$current" ] && [ "$current" != null ] || current=$(echo "$INPUT" | jq '.tool_input' 2>/dev/null) || return 1
  STRIPPED_INPUT=$(jq --argjson spawn "$spawn_fields" '. * $spawn' <<< "$current") || return 1

  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || return 1
  updated=$(jq --arg name "$name" --arg now "$now" '
    .agents[$name].state = "running"
    | .agents[$name].started_at = $now
    | .agents[$name].last_activity_at = $now
  ' <<< "$manifest") || return 1
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || return 1
  STRIP_REASON="${STRIP_REASON:+$STRIP_REASON; }enforced registered agent manifest for $name"
  return 0
}

_claim_manifest_spawn_locked() {
  local name="$1" manifest entry blocking state
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  entry=$(jq -c --arg name "$name" '.agents[$name] // empty' <<< "$manifest" 2>/dev/null) || return 1
  [ -n "$entry" ] || return 10
  validate_entry_contract "$name" "$entry" "$manifest" || return 30

  blocking=$(find_blocking_open_pair "$manifest" "$name")
  if [ -n "$blocking" ]; then
    PAIR_ID=$(jq -r '.pair_id' <<< "$blocking")
    PAIR_MEMBERS=$(jq -r '[.members[] | "\(.role) (\(.name))"] | join(", ")' <<< "$blocking")
    return 20
  fi

  state=$(jq -r '.state // ""' <<< "$entry" 2>/dev/null) || state=""
  case "$state" in
    registered) ;;
    running|used|expired) CLAIM_STATE="$state"; return 3 ;;
    *) CLAIM_STATE="$state"; return 3 ;;
  esac

  _mark_manifest_running "$name" "$manifest" "$entry"
}

claim_manifest_spawn() {
  agent_manifest_with_lock "$PLANNING_DIR" _claim_manifest_spawn_locked "$1"
}

manifest_guard() {
  local rc
  claim_manifest_spawn "$SUBAGENT_TYPE"
  rc=$?
  case "$rc" in
    0) return 0 ;;
    10)
      case "$SUBAGENT_TYPE" in
        lbwc-*)
          echo "Blocked: agent '$SUBAGENT_TYPE' has no manifest entry, spawn it through the generator first." >&2
          exit 2
          ;;
        *) return 0 ;;
      esac
      ;;
    20)
      echo "Blocked: Pair ${PAIR_ID:-} (${PAIR_MEMBERS:-?}) is open, spawn every member before starting other work." >&2
      exit 2
      ;;
    30)
      echo "Blocked: generated agent '$SUBAGENT_TYPE' contract is missing, stale, tampered, or not dispatched." >&2
      exit 2
      ;;
    3)
      echo "Blocked: generated agent '$SUBAGENT_TYPE' is already ${CLAIM_STATE:-unregistered} and cannot be spawned again." >&2
      exit 2
      ;;
    *)
      echo "Blocked: registered agent '$SUBAGENT_TYPE' could not be claimed." >&2
      exit 2
      ;;
  esac
}

manifest_guard
allow_with_strip
