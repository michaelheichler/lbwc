#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PLANNING_DIR_OVERRIDE="${LBWC_PLANNING_DIR:-}"

command -v jq >/dev/null 2>&1 || {
  echo "Blocked: jq not available, cannot validate file write" >&2
  exit 2
}
. "$SCRIPT_DIR/lib/lbwc-control-root.sh" 2>/dev/null || {
  echo "Blocked: control root resolver unavailable" >&2
  exit 2
}

INPUT=$(cat 2>/dev/null) || { echo "Blocked: unable to read file guard input" >&2; exit 2; }
[ -n "$INPUT" ] || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || TOOL_NAME=""
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null) || FILE_PATH=""
[ -n "$FILE_PATH" ] || exit 0
case "$FILE_PATH" in
  *$'\n'*) echo "Blocked: newline in file path" >&2; exit 2 ;;
  ..|../*|*/..|*/../*) echo "Blocked: path traversal in file path ($FILE_PATH)" >&2; exit 2 ;;
esac

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || HOOK_CWD=""
[ -n "$HOOK_CWD" ] || HOOK_CWD="$PWD"
HOOK_CWD=$(cd "$HOOK_CWD" 2>/dev/null && pwd -P || printf '%s' "$HOOK_CWD")
case "$FILE_PATH" in
  [/]*) RESOLVED_PATH="$FILE_PATH" ;;
  *) RESOLVED_PATH="$HOOK_CWD/$FILE_PATH" ;;
esac

CONTROL_ROOT=""
if [ -n "$PLANNING_DIR_OVERRIDE" ]; then
  CONTROL_ROOT=$(lbwc_control_root_validate "$PLANNING_DIR_OVERRIDE" 1 2>/dev/null || true)
else
  CONTROL_ROOT=$(lbwc_resolve_control_root "" "" "$HOOK_CWD" 2>/dev/null || true)
fi
if [ -n "$CONTROL_ROOT" ]; then
  MANIFEST=$(lbwc_control_root_manifest_path "$CONTROL_ROOT" 2>/dev/null || true)
else
  MANIFEST=""
fi

resolve_agent_role() {
  local identifier="$1"
  [ -n "$identifier" ] || return 1
  [ -f "$MANIFEST" ] || return 1
  jq -r --arg id "$identifier" '.agents[$id].role // empty' "$MANIFEST" 2>/dev/null
}

resolve_agent_entry() {
  local identifier="$1"
  [ -n "$identifier" ] || return 1
  [ -f "$MANIFEST" ] || return 1
  jq -c --arg id "$identifier" '.agents[$id] // empty' "$MANIFEST" 2>/dev/null
}

canonical_directory() {
  cd "$1" 2>/dev/null && pwd -P
}

canonical_existing_parent() {
  local directory="$1" parent
  directory=$(dirname "$directory")
  while [ ! -d "$directory" ]; do
    [ -L "$directory" ] && return 1
    parent=$(dirname "$directory")
    [ "$parent" != "$directory" ] || return 1
    directory="$parent"
  done
  canonical_directory "$directory"
}

canonical_existing_path() {
  local path="$1" parent target symlink_hops=0
  while [ -L "$path" ]; do
    symlink_hops=$((symlink_hops + 1))
    [ "$symlink_hops" -le 40 ] || return 1
    parent=$(canonical_existing_parent "$path") || return 1
    target=$(readlink "$path") || return 1
    if [[ "$target" = /* ]]; then
      path="$target"
    else
      path="$parent/$target"
    fi
  done
  [ -e "$path" ] || return 1
  if [ -d "$path" ]; then
    canonical_directory "$path"
  else
    parent=$(canonical_existing_parent "$path") || return 1
    printf '%s/%s\n' "$parent" "$(basename "$path")"
  fi
}

path_is_within_root() {
  [ "$1" = "$2" ] && return 0
  [[ "$1" = "$2/"* ]]
}

agent_write_capability_allows() {
  local entry="$1" identifier="$2" expected_root actual_root candidate_path candidate_parent candidate_target allowance contract_path contract contract_root contract_task manifest_contract_id entry_role relative_path contract_state schema_version capability capability_kind capability_path capability_relative
  schema_version=$(jq -r 'if .schema_version != null then .schema_version elif .capabilities != null then 3 else 2 end' <<< "$entry")
  expected_root=$(jq -r '.project_root // empty' <<< "$entry") || return 1
  [ -n "$expected_root" ] || return 1
  expected_root=$(canonical_directory "$expected_root") || return 1
  actual_root=$(canonical_directory "$HOOK_CWD") || return 1
  [ "$actual_root" = "$expected_root" ] || return 2
  candidate_path="$actual_root/$FILE_PATH"
  [[ "$FILE_PATH" == /* ]] && candidate_path="$FILE_PATH"
  case "$candidate_path" in
    "$expected_root"/*) relative_path=${candidate_path#"$expected_root"/} ;;
    *) return 5 ;;
  esac
  case "$relative_path" in
    config/subagent-critical-execution.txt|config/destructive-commands.txt|scripts/*guard*|scripts/task-contract.sh|scripts/agent-lifecycle.sh|.lbwc-planning/.agent-manifest.json|.lbwc-planning/.contracts|.lbwc-planning/.contracts/*|.claude/agents|.claude/agents/*) return 7 ;;
  esac
  contract_path=$(jq -r '.contract_path // empty' <<< "$entry")
  if [ -n "$contract_path" ] || [[ "$identifier" == lbwc-* ]]; then
    [ -n "$contract_path" ] || return 6
    contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$contract_path" "$expected_root" 2>/dev/null) || return 6
    [ "$(jq -r '.contract_digest // empty' <<< "$contract")" = "$(jq -r '.contract_digest // empty' <<< "$entry")" ] || return 6
    manifest_contract_id=$(jq -r '.contract_id // empty' <<< "$entry")
    [ -n "$manifest_contract_id" ] || return 6
    [ "$manifest_contract_id" = "$(jq -r '.contract_id // empty' <<< "$contract")" ] || return 6
    contract_root=$(jq -r '.project_root // empty' <<< "$contract")
    [ "$contract_root" = "$expected_root" ] || return 6
    entry_role=$(jq -r '.role // empty' <<< "$entry")
    [ -n "$entry_role" ] || return 6
    contract_task=$(jq -r '.task_identity // empty' <<< "$contract")
    [ "$contract_task" = "$(jq -r '.task_identity // empty' <<< "$entry")" ] || return 6
    contract_state=$(jq -r '.state // empty' <<< "$contract")
    case "$contract_state" in dispatched|running) ;; *) return 6 ;; esac
    jq -e --arg role "$entry_role" --argjson allowances "$(jq -c '.write_allowances' <<< "$entry")" '.allowances_by_role[$role] == $allowances' <<< "$contract" >/dev/null 2>&1 || return 6
    schema_version=$(jq -r '.schema_version // 2' <<< "$contract")
    if [ "$schema_version" = "3" ]; then
      jq -e --arg role "$entry_role" --argjson capabilities "$(jq -c '.capabilities // []' <<< "$entry")" '.capabilities_by_role[$role] == $capabilities' <<< "$contract" >/dev/null 2>&1 || return 6
    fi
  fi
  if [ "$schema_version" = "3" ]; then
    jq -e '.capabilities | type == "array" and length > 0 and all(.[]; type == "object")' <<< "$entry" >/dev/null 2>&1 || return 3
    while IFS= read -r capability; do
      capability_kind=$(jq -r '.kind // empty' <<< "$capability")
      capability_path=$(jq -r '.path // empty' <<< "$capability")
      case "$capability_kind" in
        file)
          capability_relative="$relative_path"
          [ "$candidate_path" = "$expected_root/$capability_path" ] || continue
          ;;
        directory)
          if [ "$capability_path" = "." ]; then
            capability_relative="$relative_path"
          else
            case "$relative_path" in
              "$capability_path"|"$capability_path"/*) capability_relative="$relative_path" ;;
              *) continue ;;
            esac
          fi
          ;;
        *) return 6 ;;
      esac
      candidate_parent=$(canonical_existing_parent "$candidate_path") || return 5
      path_is_within_root "$candidate_parent" "$expected_root" || return 5
      if [ -L "$candidate_path" ]; then
        candidate_target=$(canonical_existing_path "$candidate_path") || return 5
        path_is_within_root "$candidate_target" "$expected_root" || return 5
      fi
      case "$capability_relative" in
        .lbwc-planning|.lbwc-planning/*|.temporary-agent-runfiles|.temporary-agent-runfiles/*|.claude/agents|.claude/agents/*|.git|.git/*|.env|.env.*|*/.env|*/.env.*|*.pem|*.key|*.cert|*.p12|*.pfx|*/credentials.json|*/secrets.json|*/service-account.json|credentials.json|secrets.json|service-account.json|config/subagent-critical-execution.txt|config/destructive-commands.txt|scripts/*guard*|scripts/task-contract.sh|scripts/agent-lifecycle.sh) return 7 ;;
      esac
      return 0
    done < <(jq -c '.capabilities[]' <<< "$entry")
    return 4
  fi
  jq -e '.write_allowances | type == "array" and length > 0 and all(.[]; type == "string")' <<< "$entry" >/dev/null 2>&1 || return 3
  while IFS= read -r allowance; do
    if [ "$candidate_path" = "$expected_root/$allowance" ]; then
      candidate_parent=$(canonical_existing_parent "$candidate_path") || return 5
      path_is_within_root "$candidate_parent" "$expected_root" || return 5
      if [ -L "$candidate_path" ]; then
        candidate_target=$(canonical_existing_path "$candidate_path") || return 5
        path_is_within_root "$candidate_target" "$expected_root" || return 5
      fi
      return 0
    fi
  done < <(jq -r '.write_allowances[]' <<< "$entry")
  return 4
}

path_in_planning() {
  local planning_dir="${CONTROL_ROOT:-${PLANNING_DIR_OVERRIDE:-.lbwc-planning}}"
  if [ -n "$CONTROL_ROOT" ]; then
    case "$1" in
      "$CONTROL_ROOT"|"$CONTROL_ROOT"/*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  if [[ "$planning_dir" != /* ]]; then
    planning_dir="$HOOK_CWD/${planning_dir#./}"
  fi
  case "$1" in
    "$planning_dir"|"$planning_dir"/*|*"/$planning_dir"|*"/$planning_dir"/*) return 0 ;;
    *) return 1 ;;
  esac
}

path_is_agent_definition() {
  case "$1" in
    .claude/agents|.claude/agents/*|*/.claude/agents|*/.claude/agents/*) return 0 ;;
    *) return 1 ;;
  esac
}

path_is_doc_file() {
  case "$1" in
    *.md|*.mdx|*.rst|*.txt) return 0 ;;
  esac
  path_in_planning "$1"
}

path_is_test_file() {
  local base
  base=$(basename -- "$1")
  case "$1" in
    */test/*|*/tests/*) return 0 ;;
  esac
  case "$base" in
    test_*|*_test.*|*.test.*|*.spec.*) return 0 ;;
    *) return 1 ;;
  esac
}

AGENT_IDENTIFIER=$(printf '%s' "$INPUT" | jq -r '
  .agent_id // .agentId // .agent_type // .agentType // .subagent_type // .subagentType // .name // empty
' 2>/dev/null) || AGENT_IDENTIFIER=""
AGENT_ENTRY=$(resolve_agent_entry "$AGENT_IDENTIFIER") || AGENT_ENTRY=""
AGENT_ROLE=$(resolve_agent_role "$AGENT_IDENTIFIER")

if [ -n "$AGENT_ENTRY" ]; then
  agent_write_capability_allows "$AGENT_ENTRY" "$AGENT_IDENTIFIER"
  capability_status=$?
  case "$capability_status" in
    0) ;;
    2)
      echo "Blocked: generated workers may write only from the manifest primary workspace" >&2
      exit 2
      ;;
    3)
      echo "Blocked: worker '$AGENT_IDENTIFIER' has no assigned write allowance" >&2
      exit 2
      ;;
    5)
      echo "Blocked: path escapes the canonical primary root" >&2
      exit 2
      ;;
    6)
      echo "Blocked: worker '$AGENT_IDENTIFIER' contract is missing, mismatched, stale, or outside allowance" >&2
      exit 2
      ;;
    7)
      echo "Blocked: generated workers cannot write LBWC policy, guard, contract, manifest, lifecycle, or agent-definition paths" >&2
      exit 2
      ;;
    *)
      echo "Blocked: path is outside worker '$AGENT_IDENTIFIER' assigned write allowance" >&2
      exit 2
      ;;
  esac
elif [ -n "$AGENT_IDENTIFIER" ] && [[ "$AGENT_IDENTIFIER" == lbwc-* ]]; then
  echo "Blocked: worker '$AGENT_IDENTIFIER' manifest capability could not be resolved" >&2
  exit 2
fi

case "$AGENT_ROLE" in
  architect|lead|scout)
    path_in_planning "$RESOLVED_PATH" || {
      echo "Blocked: role '$AGENT_ROLE' can only write under the control root" >&2
      exit 2
    }
    ;;
  docs)
    path_is_doc_file "$RESOLVED_PATH" || {
      echo "Blocked: role 'docs' can only write documentation files" >&2
      exit 2
    }
    ;;
  qa-author|test-dev)
    path_is_test_file "$RESOLVED_PATH" || {
      echo "Blocked: role '$AGENT_ROLE' can only write test files" >&2
      exit 2
    }
    ;;
esac

if [ -z "$AGENT_ROLE" ] && [ "$TOOL_NAME" != "" ] && [ -f "$MANIFEST" ]; then
  OPEN_PAIR=$(jq -r '[.agents[] | select(.state == "registered" or .state == "running")] | length' "$MANIFEST" 2>/dev/null) || OPEN_PAIR=0
  case "${OPEN_PAIR:-0}" in ''|*[!0-9]*) OPEN_PAIR=0 ;; esac
  if [ "$OPEN_PAIR" -gt 0 ] 2>/dev/null; then
    path_is_doc_file "$RESOLVED_PATH" || path_is_agent_definition "$RESOLVED_PATH" || {
      echo "Blocked: main session has a spawned pair/trio open, delegate product writes to it instead of writing directly" >&2
      exit 2
    }
  fi
fi

exit 0
