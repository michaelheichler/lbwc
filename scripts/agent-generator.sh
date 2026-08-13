#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/lib/agent-manifest.sh"
. "$SCRIPT_DIR/lib/agent-fields.sh"
. "$SCRIPT_DIR/lib/lbwc-control-root.sh"

fail() {
  printf 'agent-generator: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: agent-generator.sh <role> --job <text> --contract <path> --task-id <id> [--exclusive] [--write-allowance <repo-path>] [overrides]\n' >&2
  printf '       agent-generator.sh --pair <role> --job <text> --contract <path> --task-id <id> [--exclusive] [--pair-role <role>] [--write-allowance <repo-path>] [overrides]\n' >&2
  printf '       agent-generator.sh --trio <role> --job <text> --contract <path> --task-id <id> [--exclusive] [--write-allowance <repo-path>] [--role-write-allowance <role>:<repo-path>] [overrides]\n' >&2
  exit 1
}

ROLE_DEFAULTS_PATH="$PLUGIN_ROOT/templates/agent-roles/defaults.json"
[ -f "$ROLE_DEFAULTS_PATH" ] || fail "role defaults not found: $ROLE_DEFAULTS_PATH"

is_valid_role() { jq -e --arg role "$1" 'has($role)' "$ROLE_DEFAULTS_PATH" >/dev/null 2>&1; }

PAIR_MODE=""
TRIO_MODE=""
if [ "${1:-}" = "--pair" ]; then
  PAIR_MODE=1
  shift
elif [ "${1:-}" = "--trio" ]; then
  TRIO_MODE=1
  shift
fi
ROLE="${1:-}"
[ -n "$ROLE" ] || usage
ROLE="${ROLE#lbwc-}"
shift
is_valid_role "$ROLE" || fail "invalid role '$ROLE'"

declare -A OVERRIDES=()
WRITE_ALLOWANCES=()
WRITE_CAPABILITIES=()
ROLE_WRITE_ALLOWANCE_ROLES=()
ROLE_WRITE_ALLOWANCE_PATHS=()
ROLE_WRITE_CAPABILITY_ROLES=()
ROLE_WRITE_CAPABILITY_VALUES=()
CONTROL_ROOT_ARG=""
JOB=""
PAIR_ROLE_ARG=""
EXCLUSIVE_MODE=""
CONTRACT_PATH=""
TASK_ID=""

option_token() { agent_field_token "$1"; }

apply_option() {
  local key="$1" value="$2" token role path
  case "$key" in
    --job) JOB="$value" ;;
    --contract|--contract-input) CONTRACT_PATH="$value" ;;
    --task-id|--task-identity) TASK_ID="$value" ;;
    --control-root) CONTROL_ROOT_ARG="$value" ;;
    --pair-role) PAIR_ROLE_ARG="$value" ;;
    --write-allowance) WRITE_ALLOWANCES+=("$value") ;;
    --write-capability|--capability) WRITE_CAPABILITIES+=("$value") ;;
    --role-write-allowance)
      role="${value%%:*}"
      path="${value#*:}"
      [ "$role" != "$value" ] && [ -n "$role" ] && [ -n "$path" ] || fail "invalid --role-write-allowance '$value'"
      ROLE_WRITE_ALLOWANCE_ROLES+=("$role")
      ROLE_WRITE_ALLOWANCE_PATHS+=("$path")
      ;;
    --role-write-capability)
      role="${value%%:*}"
      capability="${value#*:}"
      [ "$role" != "$value" ] && [ -n "$role" ] && [ -n "$capability" ] || fail "invalid --role-write-capability '$value'"
      ROLE_WRITE_CAPABILITY_ROLES+=("$role")
      ROLE_WRITE_CAPABILITY_VALUES+=("$capability")
      ;;
    *)
      token=$(option_token "$key") || fail "unknown option '$key'"
      OVERRIDES["$token"]="$value"
      ;;
  esac
}

parse_options() {
  local argument key value
  while [ "$#" -gt 0 ]; do
    argument="$1"
    shift
    if [ "$argument" = "--exclusive" ]; then
      EXCLUSIVE_MODE=1
      continue
    fi
    if [[ "$argument" == --*=* ]]; then
      key="${argument%%=*}"
      value="${argument#*=}"
    else
      key="$argument"
      [ "$#" -gt 0 ] || fail "missing value for $key"
      value="$1"
      shift
    fi
    apply_option "$key" "$value"
  done
}

parse_options "$@"
[ -n "$JOB" ] || fail "--job is required"
[ -n "$CONTRACT_PATH" ] || fail "--contract is required for generated LBWC agents"
[ -n "$TASK_ID" ] || fail "--task-id is required for generated LBWC agents"
[ -z "$PAIR_ROLE_ARG" ] || [ -n "$PAIR_MODE" ] || fail "--pair-role is only valid with --pair"
[ -z "$PAIR_ROLE_ARG" ] || [ -z "$TRIO_MODE" ] || fail "--pair-role is not valid with --trio"

task_write_path_is_safe() {
  case "$1" in
    ''|/*|.|./*|*/.|..|../*|*/..|*/../*|*'//'*) return 1 ;;
    *$'\n'*|*$'\r'*) return 1 ;;
    */) return 1 ;;
  esac
}

[[ "$CONTRACT_PATH" = /* ]] || CONTRACT_PATH="$PWD/$CONTRACT_PATH"
CONTRACT_PATH=$(cd "$(dirname "$CONTRACT_PATH")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$CONTRACT_PATH")") || fail "contract path is unavailable"
[ -f "$CONTRACT_PATH" ] || fail "contract not found: $CONTRACT_PATH"
PROJECT_ROOT=$(jq -r '.project_root // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
[ -n "$PROJECT_ROOT" ] || fail "contract project root is required"
PROJECT_ROOT=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || fail "contract project root is unavailable"
CONTRACT_SCHEMA_PREVIEW=$(jq -r '.schema_version // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
if [ "$CONTRACT_SCHEMA_PREVIEW" = "3" ]; then
  CONTRACT_CONTROL_ROOT=$(jq -r '.control_root // empty' "$CONTRACT_PATH" 2>/dev/null) || fail "invalid contract"
  [ -n "$CONTROL_ROOT_ARG" ] || CONTROL_ROOT_ARG="$CONTRACT_CONTROL_ROOT"
  CONTROL_ROOT=$(lbwc_control_root_validate "$CONTROL_ROOT_ARG" 0) || fail "control root is unavailable or invalid"
  CONTRACT_CONTROL_ROOT=$(lbwc_control_root_validate "$CONTRACT_CONTROL_ROOT" 0) || fail "contract control root is unavailable"
  [ "$CONTROL_ROOT" = "$CONTRACT_CONTROL_ROOT" ] || fail "contract control root mismatch"
else
  [ "$CONTRACT_SCHEMA_PREVIEW" = "2" ] || fail "unsupported contract schema"
  [ -z "$CONTROL_ROOT_ARG" ] || fail "schema 2 contract does not accept --control-root"
  CONTROL_ROOT=$(lbwc_control_root_validate "$PROJECT_ROOT/.lbwc-planning" 1) || fail "active planning control root is unavailable"
fi
PLANNING_DIR="$CONTROL_ROOT"
CONFIG_PATH="$PROJECT_ROOT/.lbwc-planning/config.json"
TEMPLATE_DEFAULTS="$PLUGIN_ROOT/templates/agent-roles/defaults.json"
[ -f "$TEMPLATE_DEFAULTS" ] || fail "role defaults not found: $TEMPLATE_DEFAULTS"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"

CONTRACT_ID=""
CONTRACT_DIGEST=""
CONTRACT_ALLOWANCES_JSON='[]'
CONTRACT_CAPABILITIES_JSON='[]'
CONTRACT_SCHEMA_VERSION=2
CONTRACT_RUNTIME_KIND=""
CONTRACT_COMMUNICATION_POLICY=""
CONTRACT_CAPABILITY_ARGS_JSON='[]'
declare -A CONTRACT_ROLE_CAPABILITIES=()
validate_contract() {
  local contract root task requested
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$CONTRACT_PATH" "$PROJECT_ROOT" --job "$JOB" 2>&1) || fail "$contract"
  contract=$(jq -ce 'select(type == "object")' <<< "$contract" 2>/dev/null) || fail "invalid contract"
  CONTRACT_DIGEST=$(jq -r '.contract_digest // empty' <<< "$contract")
  [ -n "$CONTRACT_DIGEST" ] || fail "contract digest is required"
  root=$(jq -r '.project_root // .canonical_project_root // empty' <<< "$contract")
  [ -n "$root" ] || fail "contract project root is required"
  root=$(cd "$root" 2>/dev/null && pwd -P) || fail "contract project root is unavailable"
  [ "$root" = "$PROJECT_ROOT" ] || fail "contract project root mismatch"
  jq -e '(.schema_version == 2 or .schema_version == 3) and .created_by == "main" and .state == "planned"' <<< "$contract" >/dev/null || fail "contract must be a planned main-session contract"
  CONTRACT_SCHEMA_VERSION=$(jq -r '.schema_version' <<< "$contract")
  if [ "$CONTRACT_SCHEMA_VERSION" = "3" ]; then
    contract_control_root=$(jq -r '.control_root // empty' <<< "$contract")
    [ -n "$contract_control_root" ] || fail "contract control root is required"
    contract_control_root=$(lbwc_control_root_validate "$contract_control_root" 0) || fail "contract control root is unavailable"
    [ "$contract_control_root" = "$CONTROL_ROOT" ] || fail "contract control root mismatch"
    CONTRACT_CAPABILITIES_JSON=$(jq -ce --arg role "$ROLE" '.capabilities_by_role[$role] | select(type == "array")' <<< "$contract") || fail "contract capabilities are invalid"
    CONTRACT_RUNTIME_KIND=$(jq -r '.runtime_kind // empty' <<< "$contract")
    CONTRACT_COMMUNICATION_POLICY=$(jq -r '.communication_policy // empty' <<< "$contract")
    CONTRACT_CAPABILITY_ARGS_JSON=$(printf '%s\n' "${WRITE_CAPABILITIES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0) | (split(":")) | select(length == 2) | {access:"write",kind:.[0],path:.[1]})')
    jq -ne --argjson requested "$CONTRACT_CAPABILITY_ARGS_JSON" --argjson allowed "$CONTRACT_CAPABILITIES_JSON" '$requested == $allowed' >/dev/null || fail "write capabilities do not match contract"
    for contract_role in $(jq -r '.roles[]' <<< "$contract"); do
      CONTRACT_ROLE_CAPABILITIES["$contract_role"]=$(jq -ce --arg role "$contract_role" '.capabilities_by_role[$role] // []' <<< "$contract") || fail "contract capabilities are invalid"
    done
  fi
  task=$(jq -r '.task_identity // .task_id // .contract_id // empty' <<< "$contract")
  [ -n "$task" ] || fail "contract task identity is required"
  [ -n "$TASK_ID" ] || TASK_ID="$task"
  [ "$TASK_ID" = "$task" ] || fail "contract task identity mismatch"
  CONTRACT_ID=$(jq -r '.contract_id // .id // empty' <<< "$contract")
  [ -n "$CONTRACT_ID" ] || fail "contract id is required"
  jq -e --arg role "$ROLE" '(.roles | type == "array" and index($role) != null)' <<< "$contract" >/dev/null || fail "contract role mismatch"
  CONTRACT_ALLOWANCES_JSON=$(jq -ce --arg role "$ROLE" '.allowances_by_role[$role] | select(type == "array" and all(.[]; type == "string"))' <<< "$contract") || fail "contract write allowances are invalid"
  if [ "$CONTRACT_SCHEMA_VERSION" = "2" ]; then
    requested=$(printf '%s\n' "${WRITE_ALLOWANCES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
    jq -ne --argjson requested "$requested" --argjson allowed "$CONTRACT_ALLOWANCES_JSON" '$requested == $allowed' >/dev/null || fail "write allowances do not match contract"
  fi
  case "$ROLE" in
    *critic) [ "$CONTRACT_ALLOWANCES_JSON" = '[]' ] || fail "contract grants allowances to critic" ;;
  esac
}
validate_contract

for write_allowance in "${WRITE_ALLOWANCES[@]}"; do
  task_write_path_is_safe "$write_allowance" || fail "invalid --write-allowance '$write_allowance'"
done

if [ "$CONTRACT_SCHEMA_VERSION" = "3" ] && [ "${#WRITE_ALLOWANCES[@]}" -gt 0 ]; then
  fail "schema 3 contracts require typed write capabilities"
fi

NAME_MAX_ATTEMPTS=100
LIVE_AGENT_MAX_AGE_SECONDS=3600
DEFAULT_AGENT_CAP=4

WORDLIST_A="${LBWC_AGENT_WORDLIST_A:-$PLUGIN_ROOT/config/agent-generator-adjectives.txt}"
WORDLIST_B="${LBWC_AGENT_WORDLIST_B:-$PLUGIN_ROOT/config/agent-generator-nouns.txt}"

load_words() {
  local file="$1" target="$2"
  local -n words="$target"
  [ -f "$file" ] || fail "wordlist not found: $file"
  mapfile -t words < <(grep -E '^[a-z0-9]+$' "$file" || true)
  [ "${#words[@]}" -gt 0 ] || fail "wordlist is empty: $file"
}

pick_word() {
  local array_name="$1" out_var="$2"
  local -n word_array="$array_name"
  printf -v "$out_var" '%s' "${word_array[RANDOM % ${#word_array[@]}]}"
}

load_words "$WORDLIST_A" WORDS_A
load_words "$WORDLIST_B" WORDS_B

name_is_available() {
  local name="$1" manifest="$2" agents_dir="$3"
  [ ! -e "$agents_dir/$name.md" ] || return 1
  ! jq -e --arg name "$name" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1
}

choose_name() {
  local role="$1" manifest="$2" agents_dir="$3" left right noun attempt name
  [ -n "${LBWC_AGENT_RANDOM_SEED:-}" ] && RANDOM="$LBWC_AGENT_RANDOM_SEED"
  for ((attempt = 0; attempt < NAME_MAX_ATTEMPTS; attempt++)); do
    pick_word WORDS_A left
    pick_word WORDS_A right
    pick_word WORDS_B noun
    name="lbwc-$role-$left-$right-$noun"
    if name_is_available "$name" "$manifest" "$agents_dir"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  fail "could not find a collision-free generated name"
}

parse_resolved_settings() {
  local settings="$1" line key raw
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=${line%%=*}
    case "$key" in
      RESOLVED_AGENT|RESOLVED_AGENT_MODEL|RESOLVED_MODEL|RESOLVED_MAX_TURNS|RESOLVED_EFFORT|RESOLVED_REASONING|RESOLVED_REASONING_JSON) ;;
      *) fail "invalid resolver assignment '$key'" ;;
    esac
    raw=${line#*=}
    [[ "$raw" == \'*\' ]] || fail "invalid resolver value for $key"
    raw=${raw:1:${#raw}-2}
    raw=${raw//"'\\''"/"'"}
    printf -v "$key" '%s' "$raw"
  done <<< "$settings"
}

declare -A ROLE_MODEL=()
declare -A ROLE_EFFORT=()
declare -A ROLE_REASONING_JSON=()
declare -A ROLE_MAXTURNS=()

resolve_role_settings() {
  local role="$1" settings rc=0 settings_script
  settings_script="${LBWC_AGENT_SETTINGS_SCRIPT:-$SCRIPT_DIR/resolve-agent-settings.sh}"
  [ -f "$settings_script" ] || fail "agent settings resolver not found"

  local -a resolver_args=("$role" "$CONFIG_PATH" "$PLUGIN_ROOT")
  [ "${OVERRIDES[MODEL]+set}" = set ] && resolver_args+=(--model "${OVERRIDES[MODEL]}")
  [ "${OVERRIDES[EFFORT]+set}" = set ] && resolver_args+=(--effort "${OVERRIDES[EFFORT]}")
  [ "${OVERRIDES[REASONING]+set}" = set ] && resolver_args+=(--reasoning "${OVERRIDES[REASONING]}")
  [ "${OVERRIDES[MAX_TURNS]+set}" = set ] && resolver_args+=(--max-turns "${OVERRIDES[MAX_TURNS]}")

  settings=$(bash "$settings_script" "${resolver_args[@]}" 2>&1) || rc=$?
  if [ "$rc" -eq 3 ]; then
    fail "unknown model while resolving settings for '$role': $settings"
  elif [ "$rc" -ne 0 ]; then
    fail "$settings"
  fi
  RESOLVED_AGENT_MODEL=""
  RESOLVED_REASONING_JSON=""
  parse_resolved_settings "$settings"
  [ -n "$RESOLVED_AGENT_MODEL" ] || fail "resolver omitted the Claude Code model selector for '$role'"
  jq -e 'type == "string" or . == null' <<< "$RESOLVED_REASONING_JSON" >/dev/null 2>&1 \
    || fail "resolver emitted invalid reasoning JSON for '$role'"

  ROLE_MODEL["$role"]="$RESOLVED_AGENT_MODEL"
  ROLE_EFFORT["$role"]="$RESOLVED_EFFORT"
  ROLE_REASONING_JSON["$role"]="$RESOLVED_REASONING_JSON"
  ROLE_MAXTURNS["$role"]="$RESOLVED_MAX_TURNS"
}

resolve_role_settings "$ROLE"
PAIR_ROLE=""
if [ -n "$PAIR_MODE" ]; then
  if [ -n "$PAIR_ROLE_ARG" ]; then
    PAIR_ROLE="$PAIR_ROLE_ARG"
  else
    PAIR_ROLE=$(jq -r --arg r "$ROLE" '.[$r].pairsWith // empty' "$TEMPLATE_DEFAULTS")
  fi
  [ -n "$PAIR_ROLE" ] || fail "--pair requires defaults.json's '$ROLE.pairsWith' or an explicit --pair-role"
  is_valid_role "$PAIR_ROLE" || fail "invalid pair role '$PAIR_ROLE'"
  resolve_role_settings "$PAIR_ROLE"
fi

TRIO_ROLES=()
if [ -n "$TRIO_MODE" ]; then
  mapfile -t TRIO_ROLES < <(jq -r --arg r "$ROLE" '.trios[$r] // [] | .[]' "$TEMPLATE_DEFAULTS")
  [ "${#TRIO_ROLES[@]}" -ge 2 ] || fail "--trio requires defaults.json's 'trios.$ROLE' to list at least 2 roles"
  for trio_role in "${TRIO_ROLES[@]}"; do
    is_valid_role "$trio_role" || fail "invalid trio role '$trio_role'"
    [ "$trio_role" = "$ROLE" ] || resolve_role_settings "$trio_role"
  done
fi

role_is_on_team() {
  local candidate="$1" role
  for role in "${TEAM_ROLES[@]}"; do
    [ "$role" = "$candidate" ] && return 0
  done
  return 1
}

role_is_critic() {
  case "$1" in
    *critic) return 0 ;;
    *) return 1 ;;
  esac
}

test_write_path_is_exact() {
  case "$1" in
    tests/*)
      case "$1" in
        *['*?[']*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

TEAM_ROLES=("$ROLE")
if [ -n "$PAIR_MODE" ]; then
  TEAM_ROLES+=("$PAIR_ROLE")
elif [ -n "$TRIO_MODE" ]; then
  TEAM_ROLES=("${TRIO_ROLES[@]}")
fi

build_capabilities_json() {
  local role="$1" raw kind path role_capability_index
  if [ "$CONTRACT_SCHEMA_VERSION" != "3" ]; then
    printf '%s\n' '[]'
    return
  fi
  if [ "$role" = "$ROLE" ]; then
    printf '%s\n' "$CONTRACT_CAPABILITY_ARGS_JSON"
    return
  fi
  for role_capability_index in "${!ROLE_WRITE_CAPABILITY_ROLES[@]}"; do
    if [ "${ROLE_WRITE_CAPABILITY_ROLES[$role_capability_index]}" = "$role" ]; then
      raw="${ROLE_WRITE_CAPABILITY_VALUES[$role_capability_index]}"
      kind="${raw%%:*}"
      path="${raw#*:}"
      jq -cn --arg kind "$kind" --arg path "$path" '[{access:"write",kind:$kind,path:$path}]'
      return
    fi
  done
  printf '%s\n' '[]'
}

validate_team_contract_roles() {
  local team_role role_allowances expected requested_roles mode index scoped_role scoped_path capability_json
  if [ -n "$PAIR_MODE" ]; then mode="pair"; elif [ -n "$TRIO_MODE" ]; then mode="trio"; else mode="solo"; fi
  requested_roles=$(printf '%s\n' "${TEAM_ROLES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
  jq -e --arg mode "$mode" --argjson roles "$requested_roles" '.team_mode == $mode and .roles == $roles' "$CONTRACT_PATH" >/dev/null 2>&1 || fail "contract team mismatch"
  for team_role in "${TEAM_ROLES[@]}"; do
    expected='[]'
    if [ "$team_role" = "$ROLE" ]; then
      expected=$(printf '%s\n' "${WRITE_ALLOWANCES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')
    else
      for index in "${!ROLE_WRITE_ALLOWANCE_ROLES[@]}"; do
        scoped_role=${ROLE_WRITE_ALLOWANCE_ROLES[$index]}
        scoped_path=${ROLE_WRITE_ALLOWANCE_PATHS[$index]}
        if [ "$scoped_role" = "$team_role" ]; then
          expected=$(jq -c --arg path "$scoped_path" '. + [$path]' <<< "$expected")
        fi
      done
    fi
    role_allowances=$(jq -c --arg role "$team_role" '.allowances_by_role[$role]' "$CONTRACT_PATH")
    if [ "$CONTRACT_SCHEMA_VERSION" = "3" ]; then
      capability_json=$(build_capabilities_json "$team_role")
      [ "$capability_json" = "${CONTRACT_ROLE_CAPABILITIES[$team_role]}" ] || fail "contract capabilities mismatch for '$team_role'"
    else
      [ "$role_allowances" = "$expected" ] || fail "contract allowances mismatch for '$team_role'"
    fi
  done
}
validate_team_contract_roles
mkdir -p "$AGENTS_DIR"

if role_is_critic "$ROLE" && [ "${#WRITE_ALLOWANCES[@]}" -gt 0 ]; then
  fail "--write-allowance is not valid for a critic"
fi

for i in "${!ROLE_WRITE_ALLOWANCE_ROLES[@]}"; do
  [ -n "$TRIO_MODE" ] || fail "--role-write-allowance is only valid with --trio"
  [ "${ROLE_WRITE_ALLOWANCE_ROLES[$i]}" = "test-dev" ] || fail "--role-write-allowance is only valid for test-dev in a trio"
  role_is_on_team "${ROLE_WRITE_ALLOWANCE_ROLES[$i]}" || fail "--role-write-allowance role is not in this team: '${ROLE_WRITE_ALLOWANCE_ROLES[$i]}'"
  task_write_path_is_safe "${ROLE_WRITE_ALLOWANCE_PATHS[$i]}" || fail "invalid --role-write-allowance '${ROLE_WRITE_ALLOWANCE_ROLES[$i]}:${ROLE_WRITE_ALLOWANCE_PATHS[$i]}'"
  test_write_path_is_exact "${ROLE_WRITE_ALLOWANCE_PATHS[$i]}" || fail "--role-write-allowance for test-dev must be an exact repository test path: '${ROLE_WRITE_ALLOWANCE_PATHS[$i]}'"
done

renderer_args_for_role() {
  local role="$1" token
  RENDER_ARGS=("NAME=$NAME" "JOB=$JOB" "MODEL=${ROLE_MODEL[$role]}" "MAX_TURNS=${ROLE_MAXTURNS[$role]}" "EFFORT=${ROLE_EFFORT[$role]}")
  for token in DESCRIPTION TOOLS DISALLOWED_TOOLS PERMISSION_MODE SKILLS MCP_SERVERS MEMORY BACKGROUND ISOLATION COLOR INITIAL_PROMPT; do
    if [ "${OVERRIDES[$token]+set}" = set ]; then
      RENDER_ARGS+=("$token=${OVERRIDES[$token]}")
    fi
  done
}

build_overrides_json() {
  local json='{}' token
  for token in "${!OVERRIDES[@]}"; do
    json=$(jq -c --arg key "$token" --arg value "${OVERRIDES[$token]}" '.[$key] = $value' <<< "$json")
  done
  printf '%s\n' "$json"
}

build_write_allowances_json() {
  local role="$1" json='[]' path i
  if role_is_critic "$role"; then
    printf '%s\n' "$json"
    return
  fi
  if [ "$role" = "$ROLE" ]; then
    for path in "${WRITE_ALLOWANCES[@]}"; do
      json=$(jq -c --arg path "$path" '. + [$path]' <<< "$json")
    done
  fi
  for i in "${!ROLE_WRITE_ALLOWANCE_ROLES[@]}"; do
    if [ "${ROLE_WRITE_ALLOWANCE_ROLES[$i]}" = "$role" ]; then
      json=$(jq -c --arg path "${ROLE_WRITE_ALLOWANCE_PATHS[$i]}" '. + [$path]' <<< "$json")
    fi
  done
  printf '%s\n' "$json"
}

render_and_install_one() {
  local role="$1" tmp
  NAME=$(choose_name "$role" "$MANIFEST" "$AGENTS_DIR") || return 1
  TARGET="$AGENTS_DIR/$NAME.md"
  renderer_args_for_role "$role"
  tmp="${TARGET}.tmp.${BASHPID:-$$}"
  if ! bash "$SCRIPT_DIR/render-agent-template.sh" "$role" "${RENDER_ARGS[@]}" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$TARGET" || { rm -f "$tmp"; return 1; }
}

register_entry() {
  local name="$1" role="$2" target="$3" pair_id="$4" pair_role="$5" overrides="$6" allowances="$7" created entry pid_json role_json
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  pid_json=$([ -n "$pair_id" ] && jq -n --arg v "$pair_id" '$v' || printf 'null')
  role_json=$([ -n "$pair_role" ] && jq -n --arg v "$pair_role" '$v' || printf 'null')
  entry=$(jq -cn \
    --arg name "$name" --arg role "$role" --arg project_root "$PROJECT_ROOT" \
    --arg definition_path "$target" --arg created_at "$created" \
    --arg model "${ROLE_MODEL[$role]}" --argjson effort "${ROLE_REASONING_JSON[$role]}" --arg max_turns "${ROLE_MAXTURNS[$role]}" \
    --argjson overrides "$overrides" --argjson allowances "$allowances" --argjson pair_id "$pid_json" --argjson pair_role "$role_json" \
    --arg contract_path "$CONTRACT_PATH" --arg contract_id "$CONTRACT_ID" --arg contract_digest "$CONTRACT_DIGEST" --arg task_id "$TASK_ID" \
    --arg control_root "$CONTROL_ROOT" --arg schema_version "$CONTRACT_SCHEMA_VERSION" --argjson capabilities "$(build_capabilities_json "$role")" \
    --arg runtime_kind "$CONTRACT_RUNTIME_KIND" --arg communication_policy "$CONTRACT_COMMUNICATION_POLICY" \
    '{name:$name,role:$role,project_root:$project_root,control_root:$control_root,schema_version:($schema_version|tonumber),definition_path:$definition_path,state:"registered",created_at:$created_at,model:$model,effort:$effort,max_turns:$max_turns,overrides:$overrides,write_allowances:$allowances,capabilities:$capabilities,pair_id:$pair_id,pair_role:$pair_role} + (if $runtime_kind != "" then {runtime_kind:$runtime_kind,communication_policy:$communication_policy} else {} end) + (if $contract_id != "" then {contract_enabled:true,contract_path:$contract_path,contract_id:$contract_id,contract_digest:$contract_digest,task_identity:$task_id} else {} end)')
  MANIFEST=$(jq -c --arg name "$name" --argjson entry "$entry" '.agents[$name] = $entry' <<< "$MANIFEST")
}

manifest_live_count() {
  local now
  now=$(date -u +%s)
  jq --arg now "$now" --argjson max_age "$LIVE_AGENT_MAX_AGE_SECONDS" '
    [.agents[] | select(
        .state == "running"
        or (.state == "registered" and ((($now | tonumber) - (.created_at | fromdateiso8601)) < $max_age))
      )] | length
  ' <<< "$MANIFEST"
}

rollback_targets() {
  local target
  for target in "$@"; do rm -f "$target"; done
}

render_role_or_rollback() {
  local role="$1" label="$2"
  shift 2
  if ! render_and_install_one "$role"; then
    rollback_targets "$@"
    GENERATOR_ERROR="could not render generated $label agent"
    return 1
  fi
}

write_manifest_or_rollback() {
  local what="$1"
  shift
  if ! agent_manifest_write "$PLANNING_DIR" "$MANIFEST"; then
    rollback_targets "$@"
    GENERATOR_ERROR="could not register generated $what in manifest"
    return 1
  fi
}

generate_trio_locked() {
  local pair_id names=() targets=() role overrides_json allowances_json
  pair_id=$(manifest_new_pair_id)
  for role in "${TRIO_ROLES[@]}"; do
    render_role_or_rollback "$role" "$role" "${targets[@]}" || return 1
    names+=("$NAME")
    targets+=("$TARGET")
  done
  overrides_json=$(build_overrides_json)
  for i in "${!TRIO_ROLES[@]}"; do
    allowances_json=$(build_write_allowances_json "${TRIO_ROLES[$i]}")
    register_entry "${names[$i]}" "${TRIO_ROLES[$i]}" "${targets[$i]}" "$pair_id" "${TRIO_ROLES[$i]}" "$overrides_json" "$allowances_json"
  done
  write_manifest_or_rollback "agent trio" "${targets[@]}" || return 1
  TRIO_NAMES=("${names[@]}")
}

generate_agent_locked() {
  MANIFEST=$(agent_manifest_read "$PLANNING_DIR") || { GENERATOR_ERROR="invalid agent manifest"; return 1; }
  local cap="${LBWC_AGENT_CAP:-$DEFAULT_AGENT_CAP}" needed=1 live overrides_json allowances_json pair_id
  if [ -n "$EXCLUSIVE_MODE" ]; then
    if ! jq -e '
      all(.agents[];
        if type != "object" then false
        else .state as $state
          | ($state | type) == "string"
            and (["registered", "running", "used", "expired"] | index($state) != null)
        end
      )
    ' <<< "$MANIFEST" >/dev/null; then
      GENERATOR_ERROR="exclusive generation blocked: invalid agent lifecycle state"
      return 1
    fi
    if jq -e '
      .agents[] | select(.state == "registered" or .state == "running")
    ' <<< "$MANIFEST" >/dev/null; then
      GENERATOR_ERROR="exclusive generation blocked: registered or running agent exists"
      return 1
    fi
  fi
  [ -n "$PAIR_MODE" ] && needed=2
  [ -n "$TRIO_MODE" ] && needed="${#TRIO_ROLES[@]}"
  live=$(manifest_live_count)
  if [ $((live + needed)) -gt "$cap" ]; then
    GENERATOR_ERROR="agent cap reached: $cap live (running, or registered under 1h old) agents"
    return 1
  fi

  if [ -n "$TRIO_MODE" ]; then
    generate_trio_locked
  elif [ -n "$PAIR_MODE" ]; then
    pair_id=$(manifest_new_pair_id)
    render_role_or_rollback "$ROLE" "engineer" || return 1
    ENGINEER_NAME="$NAME"
    ENGINEER_TARGET="$TARGET"
    render_role_or_rollback "$PAIR_ROLE" "critic" "$ENGINEER_TARGET" || return 1
    CRITIC_NAME="$NAME"
    CRITIC_TARGET="$TARGET"
    overrides_json=$(build_overrides_json)
    allowances_json=$(build_write_allowances_json "$ROLE")
    register_entry "$ENGINEER_NAME" "$ROLE" "$ENGINEER_TARGET" "$pair_id" "engineer" "$overrides_json" "$allowances_json"
    allowances_json=$(build_write_allowances_json "$PAIR_ROLE")
    register_entry "$CRITIC_NAME" "$PAIR_ROLE" "$CRITIC_TARGET" "$pair_id" "critic" "$overrides_json" "$allowances_json"
    write_manifest_or_rollback "agent pair" "$ENGINEER_TARGET" "$CRITIC_TARGET" || return 1
  else
    render_role_or_rollback "$ROLE" "agent" || return 1
    SINGLE_NAME="$NAME"
    SINGLE_TARGET="$TARGET"
    overrides_json=$(build_overrides_json)
    allowances_json=$(build_write_allowances_json "$ROLE")
    register_entry "$SINGLE_NAME" "$ROLE" "$SINGLE_TARGET" "" "" "$overrides_json" "$allowances_json"
    write_manifest_or_rollback "agent" "$SINGLE_TARGET" || return 1
  fi
}

GENERATOR_ERROR=""
if ! agent_manifest_with_lock "$PLANNING_DIR" generate_agent_locked; then
  fail "${GENERATOR_ERROR:-could not generate agent}"
fi

print_spawn_ready() {
  local role="$1" name="$2" label="$3"
  printf 'Agent-call parameters:\n'
  printf '  subagent_type: %s\n' "$name"
  printf '  name: %s\n' "$name"
  printf '  model: %s\n' "${ROLE_MODEL[$role]}"
  [ -n "${ROLE_MAXTURNS[$role]}" ] && printf '  maxTurns: %s\n' "${ROLE_MAXTURNS[$role]}"
  [ -n "${ROLE_EFFORT[$role]}" ] && printf '  effort: %s\n' "${ROLE_EFFORT[$role]}"
  if [ -n "$label" ]; then
    printf '%s: SPAWN_READY %s\n' "$label" "$name"
  else
    printf 'SPAWN_READY %s\n' "$name"
  fi
}

if [ -n "$TRIO_MODE" ]; then
  for i in "${!TRIO_ROLES[@]}"; do
    print_spawn_ready "${TRIO_ROLES[$i]}" "${TRIO_NAMES[$i]}" "${TRIO_ROLES[$i]^^}"
  done
elif [ -n "$PAIR_MODE" ]; then
  print_spawn_ready "$ROLE" "$ENGINEER_NAME" "ENGINEER"
  print_spawn_ready "$PAIR_ROLE" "$CRITIC_NAME" "CRITIC"
else
  print_spawn_ready "$ROLE" "$SINGLE_NAME" ""
fi
