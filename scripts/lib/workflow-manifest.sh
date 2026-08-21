#!/usr/bin/env bash
set -u

WORKFLOW_MANIFEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$WORKFLOW_MANIFEST_SCRIPT_DIR/lbwc-control-root.sh" 2>/dev/null || return 1
. "$WORKFLOW_MANIFEST_SCRIPT_DIR/manifest-lock.sh" 2>/dev/null || return 1

# Out-parameter: callers read this after a claim/finish/expire rejection to see the current state.
export WORKFLOW_MANIFEST_CLAIM_STATE=""

workflow_manifest_control_root() {
  local requested="${1:-.lbwc-planning}" resolved
  resolved=$(lbwc_control_root_validate "$requested" 1 2>/dev/null) || return 1
  printf '%s\n' "$resolved"
}

workflow_manifest_path() {
  lbwc_control_root_workflow_manifest_path "${1:-.lbwc-planning}"
}

workflow_manifest_lock_path() {
  lbwc_control_root_workflow_manifest_lock_path "${1:-.lbwc-planning}"
}

workflow_manifest_acquire_lock() {
  local planning_dir="${1:-.lbwc-planning}" lock_dir control_root
  control_root=$(workflow_manifest_control_root "$planning_dir") || return 1
  lock_dir=$(workflow_manifest_lock_path "$control_root")
  manifest_lock_acquire "$lock_dir" WORKFLOW_MANIFEST
}

workflow_manifest_release_lock() {
  local lock_dir control_root
  control_root=$(workflow_manifest_control_root "${1:-.lbwc-planning}") || return 1
  lock_dir=$(workflow_manifest_lock_path "$control_root")
  manifest_lock_release "$lock_dir"
}

workflow_manifest_with_lock() {
  local planning_dir="${1:-.lbwc-planning}" callback="${2:-}" lock_dir control_root
  shift 2 || return 1
  [ -n "$callback" ] || return 1
  control_root=$(workflow_manifest_control_root "$planning_dir") || return 1
  lock_dir=$(workflow_manifest_lock_path "$control_root")
  manifest_lock_with_lock "$lock_dir" WORKFLOW_MANIFEST "$callback" "$@"
}

workflow_manifest_read() {
  local planning_dir="${1:-.lbwc-planning}" path control_root
  control_root=$(workflow_manifest_control_root "$planning_dir") || return 1
  path=$(workflow_manifest_path "$control_root")
  manifest_read "$path" workflows
}

workflow_manifest_write() {
  local planning_dir="$1" manifest="$2" path control_root
  control_root=$(workflow_manifest_control_root "$planning_dir") || return 1
  path=$(workflow_manifest_path "$control_root")
  manifest_write "$path" workflows "$manifest"
}

workflow_manifest_safe_contract_id() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  case "$1" in *..*) return 1 ;; esac
}

workflow_manifest_safe_digest() {
  [[ "${1:-}" =~ ^[0-9a-f]{64}$ ]]
}

_workflow_manifest_register_locked() {
  local planning_dir="$1" contract_id="$2" script_path="$3" script_digest="$4" args_digest="$5" roster="$6"
  local manifest existing created entry
  manifest=$(workflow_manifest_read "$planning_dir") || return 1
  existing=$(jq -c --arg id "$contract_id" '.workflows[$id] // empty' <<< "$manifest") || return 1
  [ -z "$existing" ] || return 3
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  entry=$(jq -cn \
    --arg contract_id "$contract_id" --arg script_path "$script_path" \
    --arg script_digest "$script_digest" --arg args_digest "$args_digest" \
    --argjson roster "$roster" --arg created_at "$created" \
    '{contract_id:$contract_id,script_path:$script_path,script_digest:$script_digest,args_digest:$args_digest,roster:$roster,state:"registered",created_at:$created_at}') || return 1
  manifest=$(jq -c --arg id "$contract_id" --argjson entry "$entry" '.workflows[$id] = $entry' <<< "$manifest") || return 1
  workflow_manifest_write "$planning_dir" "$manifest"
}

workflow_manifest_register() {
  local planning_dir="$1" contract_id="$2" script_path="$3" script_digest="$4" args_digest="$5" roster="$6"
  workflow_manifest_safe_contract_id "$contract_id" || return 1
  [ -n "$script_path" ] || return 1
  workflow_manifest_safe_digest "$script_digest" || return 1
  workflow_manifest_safe_digest "$args_digest" || return 1
  jq -e '(type == "array") and all(.[]; type == "string" and length > 0)' <<< "$roster" >/dev/null 2>&1 || return 1
  workflow_manifest_with_lock "$planning_dir" _workflow_manifest_register_locked "$planning_dir" "$contract_id" "$script_path" "$script_digest" "$args_digest" "$roster"
}

_workflow_manifest_claim_locked() {
  local planning_dir="$1" contract_id="$2" script_digest="$3" args_digest="$4"
  local manifest entry state now updated
  manifest=$(workflow_manifest_read "$planning_dir") || return 1
  entry=$(jq -c --arg id "$contract_id" '.workflows[$id] // empty' <<< "$manifest") || return 1
  [ -n "$entry" ] || return 10
  jq -e --arg d "$script_digest" '.script_digest == $d' <<< "$entry" >/dev/null 2>&1 || return 20
  jq -e --arg d "$args_digest" '.args_digest == $d' <<< "$entry" >/dev/null 2>&1 || return 20
  state=$(jq -r '.state' <<< "$entry")
  if [ "$state" != "registered" ]; then
    WORKFLOW_MANIFEST_CLAIM_STATE="$state"
    return 3
  fi
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  updated=$(jq --arg id "$contract_id" --arg now "$now" '
    .workflows[$id].state = "running" | .workflows[$id].started_at = $now
  ' <<< "$manifest") || return 1
  workflow_manifest_write "$planning_dir" "$updated"
}

workflow_manifest_claim() {
  local planning_dir="$1" contract_id="$2" script_digest="$3" args_digest="$4"
  workflow_manifest_safe_contract_id "$contract_id" || return 1
  workflow_manifest_with_lock "$planning_dir" _workflow_manifest_claim_locked "$planning_dir" "$contract_id" "$script_digest" "$args_digest"
}

_workflow_manifest_finish_locked() {
  local planning_dir="$1" contract_id="$2" from_state="$3" to_state="$4" timestamp_field="$5"
  local manifest entry state now updated
  manifest=$(workflow_manifest_read "$planning_dir") || return 1
  entry=$(jq -c --arg id "$contract_id" '.workflows[$id] // empty' <<< "$manifest") || return 1
  [ -n "$entry" ] || return 10
  state=$(jq -r '.state' <<< "$entry")
  if [ "$state" != "$from_state" ]; then
    WORKFLOW_MANIFEST_CLAIM_STATE="$state"
    return 3
  fi
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  updated=$(jq --arg id "$contract_id" --arg state "$to_state" --arg field "$timestamp_field" --arg now "$now" '
    .workflows[$id].state = $state | .workflows[$id][$field] = $now
  ' <<< "$manifest") || return 1
  workflow_manifest_write "$planning_dir" "$updated"
}

workflow_manifest_complete() {
  local planning_dir="$1" contract_id="$2"
  workflow_manifest_safe_contract_id "$contract_id" || return 1
  workflow_manifest_with_lock "$planning_dir" _workflow_manifest_finish_locked "$planning_dir" "$contract_id" running used completed_at
}

_workflow_manifest_expire_locked() {
  local planning_dir="$1" contract_id="$2"
  local manifest entry state now updated
  manifest=$(workflow_manifest_read "$planning_dir") || return 1
  entry=$(jq -c --arg id "$contract_id" '.workflows[$id] // empty' <<< "$manifest") || return 1
  [ -n "$entry" ] || return 10
  state=$(jq -r '.state' <<< "$entry")
  case "$state" in
    registered|running) ;;
    *) WORKFLOW_MANIFEST_CLAIM_STATE="$state"; return 3 ;;
  esac
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  updated=$(jq --arg id "$contract_id" --arg now "$now" '
    .workflows[$id].state = "expired" | .workflows[$id].expired_at = $now
  ' <<< "$manifest") || return 1
  workflow_manifest_write "$planning_dir" "$updated"
}

workflow_manifest_expire() {
  local planning_dir="$1" contract_id="$2"
  workflow_manifest_safe_contract_id "$contract_id" || return 1
  workflow_manifest_with_lock "$planning_dir" _workflow_manifest_expire_locked "$planning_dir" "$contract_id"
}
