#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || {
  echo "Blocked: jq not available, cannot validate workflow spawn" >&2
  exit 2
}

fail() {
  echo "Blocked: $1" >&2
  exit 2
}

INPUT=$(cat 2>/dev/null) || fail "workflow spawn guard could not read tool call input"
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || fail "workflow spawn guard could not parse tool call input"
[ "$TOOL_NAME" = "Workflow" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/lib/workflow-manifest.sh" ] || fail "workflow manifest library is unavailable"
. "$SCRIPT_DIR/lib/workflow-manifest.sh" || fail "workflow manifest library failed to load"
[ -f "$SCRIPT_DIR/lib/lbwc-control-root.sh" ] || fail "control root library is unavailable"
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" || fail "control root library failed to load"

HAS_SCRIPT=$(echo "$INPUT" | jq -r '(.tool_input.script != null)' 2>/dev/null) \
  || fail "Workflow call input could not be parsed"
[ "$HAS_SCRIPT" = "false" ] || fail "Workflow call carries an inline 'script' parameter, only a registered scriptPath is allowed"

SCRIPT_PATH=$(echo "$INPUT" | jq -r '.tool_input.scriptPath // ""' 2>/dev/null) \
  || fail "Workflow call input could not be parsed"
[ -n "$SCRIPT_PATH" ] || fail "Workflow call has no scriptPath"
case "$SCRIPT_PATH" in
  [/]*) ;;
  *) fail "scriptPath must be an absolute path: $SCRIPT_PATH" ;;
esac
[ -f "$SCRIPT_PATH" ] || fail "scriptPath does not resolve to a file on disk: $SCRIPT_PATH"
CANONICAL_SCRIPT_PATH=$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$SCRIPT_PATH")") \
  || fail "scriptPath is unavailable"

CONTROL_ROOT=$(lbwc_resolve_control_root "" "" "$PWD" 2>/dev/null || true)
[ -n "$CONTROL_ROOT" ] || fail "generated workflow has no resolvable control root or manifest"
WORKFLOWS_DIR=$(lbwc_control_root_workflows_dir "$CONTROL_ROOT" 2>/dev/null || true)
[ -n "$WORKFLOWS_DIR" ] || fail "generated workflow directory is unavailable"
case "$CANONICAL_SCRIPT_PATH" in
  "$WORKFLOWS_DIR"[/]*) ;;
  *) fail "scriptPath is outside the registered generated directory: $CANONICAL_SCRIPT_PATH" ;;
esac

CONTRACT_ID=$(basename "$CANONICAL_SCRIPT_PATH")
case "$CONTRACT_ID" in
  *.js) CONTRACT_ID="${CONTRACT_ID%.js}" ;;
  *) fail "scriptPath does not name a generated workflow script: $CANONICAL_SCRIPT_PATH" ;;
esac
workflow_manifest_safe_contract_id "$CONTRACT_ID" || fail "scriptPath names an unsafe workflow identity: $CONTRACT_ID"

MANIFEST_JSON=$(workflow_manifest_read "$CONTROL_ROOT" 2>/dev/null) \
  || fail "workflow manifest is unreadable or malformed, regenerate through the workflow generator"
ENTRY=$(jq -c --arg id "$CONTRACT_ID" '.workflows[$id] // empty' <<< "$MANIFEST_JSON" 2>/dev/null) \
  || fail "workflow manifest is unreadable or malformed, regenerate through the workflow generator"
[ -n "$ENTRY" ] || fail "workflow '$CONTRACT_ID' has no manifest entry, generate it through the workflow generator first"

RECORDED_SCRIPT_PATH=$(jq -r '.script_path // ""' <<< "$ENTRY")
[ "$RECORDED_SCRIPT_PATH" = "$CANONICAL_SCRIPT_PATH" ] \
  || fail "scriptPath does not match the path recorded at generation for '$CONTRACT_ID'"

ACTUAL_SCRIPT_DIGEST=$(shasum -a 256 "$CANONICAL_SCRIPT_PATH" 2>/dev/null | awk '{print $1}')
[ -n "$ACTUAL_SCRIPT_DIGEST" ] || fail "could not hash scriptPath: $CANONICAL_SCRIPT_PATH"
RECORDED_SCRIPT_DIGEST=$(jq -r '.script_digest // ""' <<< "$ENTRY")
[ "$ACTUAL_SCRIPT_DIGEST" = "$RECORDED_SCRIPT_DIGEST" ] \
  || fail "workflow '$CONTRACT_ID' file digest no longer matches the digest recorded at generation, the file was modified after generation"

ACTUAL_ARGS_JSON=$(echo "$INPUT" | jq -Sc '.tool_input.args // null' 2>/dev/null) \
  || fail "workflow call args could not be parsed"
ACTUAL_ARGS_DIGEST=$(printf '%s' "$ACTUAL_ARGS_JSON" | shasum -a 256 | awk '{print $1}')
RECORDED_ARGS_DIGEST=$(jq -r '.args_digest // ""' <<< "$ENTRY")
[ "$ACTUAL_ARGS_DIGEST" = "$RECORDED_ARGS_DIGEST" ] \
  || fail "workflow '$CONTRACT_ID' args do not match the args recorded at generation"

workflow_manifest_claim "$CONTROL_ROOT" "$CONTRACT_ID" "$ACTUAL_SCRIPT_DIGEST" "$ACTUAL_ARGS_DIGEST"
CLAIM_RC=$?
case "$CLAIM_RC" in
  0) exit 0 ;;
  10) fail "workflow '$CONTRACT_ID' has no manifest entry, generate it through the workflow generator first" ;;
  20) fail "workflow '$CONTRACT_ID' digest or args no longer match the manifest, rerun the workflow generator" ;;
  3) fail "workflow '$CONTRACT_ID' is already ${WORKFLOW_MANIFEST_CLAIM_STATE:-claimed} and cannot be started again" ;;
  *) fail "workflow '$CONTRACT_ID' could not be claimed" ;;
esac
