#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/lib/lbwc-control-root.sh"
. "$SCRIPT_DIR/lib/lbwc-settings.sh"

SETTINGS_PATH="${LBWC_SETTINGS_PATH:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"

fail() {
  printf 'team-command-transaction: %s\n' "$1" >&2
  exit 1
}

fail_diag() {
  local message="$1"
  if [ -n "${RUN_ROOT:-}" ] && [ -d "${RUN_ROOT:-}" ]; then
    printf '%s\n' "$(jq -cn --arg action "$ACTION" --arg message "$message" \
      '{event:"fail",action:$action,message:$message,at:(now | todate)}')" \
      >> "$RUN_ROOT/diagnostics.jsonl" 2>/dev/null || true
  fi
  fail "$message"
}

usage() {
  printf '%s\n' \
    'Usage: team-command-transaction.sh preflight --project-root PATH [--role ROLE ...] [--scope PATH ...] [--engineer ROLE] [--test-dev]' \
    '       team-command-transaction.sh propose --project-root PATH [--engineer ROLE] [--test-dev]' \
    '       team-command-transaction.sh prepare --project-root PATH --run-id ID --instruction TEXT [--role ROLE ...] [--scope PATH ...] [--engineer ROLE] [--test-dev]' \
    '       team-command-transaction.sh spawn-payload --project-root PATH --run-root PATH' \
    '       team-command-transaction.sh record-spawn --project-root PATH --run-root PATH --contract-id ID --teammate NAME' \
    '       team-command-transaction.sh task-payload --project-root PATH --run-root PATH' \
    '       team-command-transaction.sh record-task --project-root PATH --run-root PATH --contract-id ID --task-id ID' \
    '       team-command-transaction.sh fail --project-root PATH --run-root PATH [--event TEXT]' \
    '       team-command-transaction.sh complete --project-root PATH --run-root PATH [--event TEXT]' \
    '       team-command-transaction.sh summary --project-root PATH --run-root PATH' >&2
  exit 2
}

is_valid_role() {
  jq -e --arg role "$1" 'has($role)' "$ROLE_DEFAULTS_PATH" >/dev/null 2>&1
}

is_critic_role() {
  case "$1" in
    *critic) return 0 ;;
    *) return 1 ;;
  esac
}

is_valid_run_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

is_valid_record_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]
}

protected_scope_path() {
  local value="$1"
  case "$value" in
    .git|.git/*|.temporary-agent-runfiles|.temporary-agent-runfiles/*|.lbwc-planning|.lbwc-planning/*|.claude|.claude/*) return 0 ;;
    .env|.env.*|*/.env|*/.env.*) return 0 ;;
    *credentials.json|*secrets.json|*service-account.json) return 0 ;;
    *.pem|*.key|*.cert|*.p12|*.pfx) return 0 ;;
  esac
  return 1
}

require_file() {
  [ -f "$1" ] || fail "$2: $1"
}

ACTION="${1:-}"
[ -n "$ACTION" ] || usage
case "$ACTION" in
  preflight|propose|prepare|spawn-payload|record-spawn|task-payload|record-task|fail|complete|summary) ;;
  *) usage ;;
esac
shift

PROJECT_ROOT_ARG=""
RUN_ROOT_ARG=""
RUN_ID=""
INSTRUCTION=""
ENGINEER_ARG=""
WANT_TEST_DEV=false
CONTRACT_ID_ARG=""
TEAMMATE_ARG=""
TASK_ID_ARG=""
EVENT_TEXT=""
ROLES=()
SCOPES=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || fail '--project-root requires a path'
      PROJECT_ROOT_ARG="$2"
      shift 2
      ;;
    --run-root)
      [ "$#" -ge 2 ] || fail '--run-root requires a path'
      RUN_ROOT_ARG="$2"
      shift 2
      ;;
    --run-id)
      [ "$#" -ge 2 ] || fail '--run-id requires a value'
      RUN_ID="$2"
      shift 2
      ;;
    --instruction)
      [ "$#" -ge 2 ] || fail '--instruction requires text'
      INSTRUCTION="$2"
      shift 2
      ;;
    --role)
      [ "$#" -ge 2 ] || fail '--role requires a value'
      ROLES+=("$2")
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || fail '--scope requires a path'
      SCOPES+=("$2")
      shift 2
      ;;
    --engineer)
      [ "$#" -ge 2 ] || fail '--engineer requires a role'
      ENGINEER_ARG="$2"
      shift 2
      ;;
    --test-dev)
      WANT_TEST_DEV=true
      shift
      ;;
    --contract-id)
      [ "$#" -ge 2 ] || fail '--contract-id requires a value'
      CONTRACT_ID_ARG="$2"
      shift 2
      ;;
    --teammate)
      [ "$#" -ge 2 ] || fail '--teammate requires a name'
      TEAMMATE_ARG="$2"
      shift 2
      ;;
    --task-id)
      [ "$#" -ge 2 ] || fail '--task-id requires a value'
      TASK_ID_ARG="$2"
      shift 2
      ;;
    --event)
      [ "$#" -ge 2 ] || fail '--event requires text'
      EVENT_TEXT="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || fail 'jq is required'
ROLE_DEFAULTS_PATH="$SCRIPT_DIR/../templates/agent-roles/defaults.json"
require_file "$ROLE_DEFAULTS_PATH" 'role defaults not found'

PROJECT_ROOT=""
RUN_ROOT=""
RESOLVED_SCOPES='[]'
ACTIVE_CONTROL_ROOT=""
CONTROL_ROOT_KIND="temporary-run"
AGENT_TEAMS_STATUS='{}'
CONTRACT_REQUESTED_BACKEND=""
CONTRACT_RESOLVED_BACKEND=""

canonical_project_root() {
  local candidate="$1"
  [ -n "$candidate" ] || fail '--project-root is required'
  [ -d "$candidate" ] || fail "project root does not exist: $candidate"
  [ ! -L "$candidate" ] || fail 'project root must not be a symbolic link'
  (cd -P "$candidate" && pwd -P) || fail "project root is not readable: $candidate"
}

resolve_run_root() {
  [ -n "$RUN_ROOT_ARG" ] || fail '--run-root is required'
  local canonical
  canonical=$(cd -P "$RUN_ROOT_ARG" 2>/dev/null && pwd -P) || fail "run root is not readable: $RUN_ROOT_ARG"
  [ "$(dirname "$canonical")" = "$PROJECT_ROOT/.temporary-agent-runfiles/runs" ] \
    || fail 'run root is outside the project temporary run directory'
  RUN_ROOT="$canonical"
}

resolve_scopes() {
  local scope_json scope
  local -a scope_args=()
  for scope in ${SCOPES[@]+"${SCOPES[@]}"}; do
    scope_args+=(--scope "$scope")
  done
  scope_json=$(bash "$SCRIPT_DIR/team-run-state.sh" resolve-scopes \
    --project-root "$PROJECT_ROOT" ${scope_args[@]+"${scope_args[@]}"}) \
    || fail 'scope resolution failed'
  RESOLVED_SCOPES=$(jq -ce '.scopes' <<< "$scope_json") || fail 'scope resolution returned invalid JSON'
}

reject_protected_scopes() {
  local scope
  while IFS= read -r scope; do
    [ -n "$scope" ] || continue
    if protected_scope_path "$scope"; then
      fail "scope is protected and cannot be granted to a generated worker: $scope"
    fi
  done < <(jq -r '.[]' <<< "$RESOLVED_SCOPES")
}

resolve_active_control_root() {
  ACTIVE_CONTROL_ROOT=""
  CONTROL_ROOT_KIND="temporary-run"
  local candidate
  candidate=$(lbwc_control_root_validate "$PROJECT_ROOT/.lbwc-planning" 1 2>/dev/null) || return 0
  ACTIVE_CONTROL_ROOT="$candidate"
  CONTROL_ROOT_KIND="active-planning"
}

planning_routing_available() {
  [ -f "$ACTIVE_CONTROL_ROOT/config.json" ] || return 1
  jq -e 'type == "object"' "$ACTIVE_CONTROL_ROOT/config.json" >/dev/null 2>&1 || return 1
  jq -e '.routing | type == "object"' "$ACTIVE_CONTROL_ROOT/config.json" >/dev/null 2>&1
}

resolve_routing() {
  ROUTING_MODE=""
  ROUTING_PROFILE=""
  ROUTING_MODEL="unknown"
  ROUTING_EFFORT=""
  ROUTING_REASONING_JSON='null'
  ROUTING_MAX_TURNS=""
  local route_json effort_raw merged_config workflow_effort num den base_turns

  if [ "$CONTROL_ROOT_KIND" = "active-planning" ] && planning_routing_available; then
    ROUTING_MODE="saved"
    route_json=$(bash "$SCRIPT_DIR/lbwc-routing.sh" resolve "$ACTIVE_CONTROL_ROOT" "$ROSTER_ENGINEER") \
      || fail "route resolution failed for '$ROSTER_ENGINEER': $route_json"
    ROUTING_PROFILE=$(jq -r '.profile' <<< "$route_json")
    ROUTING_MODEL=$(jq -r '.model' <<< "$route_json")
    ROUTING_REASONING_JSON=$(jq -c '.reasoning' <<< "$route_json")
    ROUTING_EFFORT=$(jq -r 'if .reasoning == null then "" else .reasoning end' <<< "$route_json")
    merged_config=$(lbwc_merged_config "$ACTIVE_CONTROL_ROOT/config.json")
    workflow_effort=$(jq -r '.effort // "balanced"' <<< "$merged_config")
    case "$workflow_effort" in thorough|balanced|fast|turbo) ;; *) workflow_effort="balanced" ;; esac
  else
    ROUTING_MODE="seeded"
    ROUTING_PROFILE="balanced"
    local binary_path
    binary_path="${CLAUDE_CODE_EXECPATH:-}"
    if [ -z "$binary_path" ]; then
      binary_path=$(command -v claude 2>/dev/null || true)
    fi
    [ -n "$binary_path" ] && [ -f "$binary_path" ] \
      || fail "routing authority requires an initialized .lbwc-planning or the Claude Code executable; run /lbwc:models refresh first or install Claude Code"
    local catalog_json
    catalog_json=$(bash "$SCRIPT_DIR/claude-capabilities.sh" refresh-from-binary "$binary_path") \
      || fail "could not extract capability catalog from $binary_path"
    CATALOG_JSON="$catalog_json"
    ROUTING_MODEL=$(jq -r '.models[] | select(.selector | contains("sonnet")) | .selector' <<< "$catalog_json" | head -1)
    [ -n "$ROUTING_MODEL" ] || fail "no sonnet model selector in capability catalog"
    ROUTING_REASONING_JSON=$(jq -c '.reasoning.accepted_values[] | select(. == "high")' <<< "$catalog_json" | head -1)
    [ -n "$ROUTING_REASONING_JSON" ] || fail "no high reasoning value in capability catalog"
    ROUTING_EFFORT="high"
    workflow_effort="balanced"
  fi

  case "$workflow_effort" in
    thorough) num=3; den=2 ;;
    balanced) num=1; den=1 ;;
    fast) num=4; den=5 ;;
    turbo) num=3; den=5 ;;
  esac
  base_turns=$(jq -r --arg role "$ROSTER_ENGINEER" '.[$role].maxTurns // empty' "$ROLE_DEFAULTS_PATH")
  case "$base_turns" in
    ''|*[!0-9]*) fail "no maxTurns default for role '$ROSTER_ENGINEER' in $ROLE_DEFAULTS_PATH" ;;
  esac
  ROUTING_MAX_TURNS=$(( (base_turns * num + den / 2) / den ))
  [ "$ROUTING_MAX_TURNS" -ge 1 ] || ROUTING_MAX_TURNS=1
}

resolve_roster() {
  ROSTER_ENGINEER=""
  ROSTER_CRITIC=""
  ROSTER_TEST_DEV=false
  local configured_critic
  if [ "${#ROLES[@]}" -gt 0 ]; then
    local role seen_critic=false seen_testdev=false engineer_count=0
    for role in "${ROLES[@]}"; do
      is_valid_role "$role" || fail "invalid role: $role"
      if [ "$role" = "test-dev" ]; then
        [ "$seen_testdev" = false ] || fail 'duplicate role: test-dev'
        seen_testdev=true
      elif is_critic_role "$role"; then
        [ "$seen_critic" = false ] || fail 'roster accepts at most one critic'
        seen_critic=true
        ROSTER_CRITIC="$role"
      else
        engineer_count=$((engineer_count + 1))
        [ "$engineer_count" -eq 1 ] || fail 'roster accepts exactly one engineer role'
        ROSTER_ENGINEER="$role"
      fi
    done
    [ -n "$ROSTER_ENGINEER" ] || fail 'roster requires one engineer role'
    ROSTER_TEST_DEV="$seen_testdev"
    configured_critic=$(jq -r --arg role "$ROSTER_ENGINEER" '.[$role].pairsWith // empty' "$ROLE_DEFAULTS_PATH")
    if [ "$seen_critic" = true ]; then
      [ -n "$configured_critic" ] || fail "role '$ROSTER_ENGINEER' has no configured critic"
      [ "$ROSTER_CRITIC" = "$configured_critic" ] \
        || fail "critic '$ROSTER_CRITIC' is not the configured pair for '$ROSTER_ENGINEER' ($configured_critic)"
    else
      [ -n "$configured_critic" ] || fail "role '$ROSTER_ENGINEER' has no configured pair; pass its critic explicitly"
      ROSTER_CRITIC="$configured_critic"
    fi
  else
    ROSTER_ENGINEER="${ENGINEER_ARG:-web-engineer}"
    is_valid_role "$ROSTER_ENGINEER" || fail "invalid engineer role: $ROSTER_ENGINEER"
    configured_critic=$(jq -r --arg role "$ROSTER_ENGINEER" '.[$role].pairsWith // empty' "$ROLE_DEFAULTS_PATH")
    [ -n "$configured_critic" ] || fail "engineer role '$ROSTER_ENGINEER' has no configured critic"
    ROSTER_CRITIC="$configured_critic"
    ROSTER_TEST_DEV="$WANT_TEST_DEV"
  fi
  if [ "$ROSTER_TEST_DEV" = true ]; then
    jq -e --arg role "$ROSTER_ENGINEER" '.trios[$role] != null' "$ROLE_DEFAULTS_PATH" >/dev/null \
      || fail "role '$ROSTER_ENGINEER' has no configured trio for test-dev"
    TEAM_MODE="trio"
  else
    TEAM_MODE="pair"
  fi
  ROSTER_ROLES_JSON=$(jq -cn \
    --arg engineer "$ROSTER_ENGINEER" --arg critic "$ROSTER_CRITIC" --argjson test_dev "$ROSTER_TEST_DEV" \
    '[$engineer, $critic] + (if $test_dev then ["test-dev"] else [] end)')
}

read_agent_teams_status() {
  AGENT_TEAMS_STATUS=$(bash "$SCRIPT_DIR/lbwc-config.sh" agent-teams-status --settings "$SETTINGS_PATH") \
    || fail 'could not read agent teams status'
}

require_run_roster() {
  local contract
  [ -f "$RUN_ROOT/run.json" ] || fail_diag "run state is missing: $RUN_ROOT/run.json"
  EXPECTED_CONTRACT=$(jq -r '.contract_id // empty' "$RUN_ROOT/contract.json" 2>/dev/null) || true
  [ -n "$EXPECTED_CONTRACT" ] || fail_diag 'contract record is missing or unreadable'
  contract=$(bash "$SCRIPT_DIR/task-contract.sh" read "$PROJECT_ROOT" "$EXPECTED_CONTRACT" 2>/dev/null) \
    || fail_diag 'contract is missing, stale, or tampered'
  CONTRACT_REQUESTED_BACKEND=$(jq -r '.requested_backend // empty' <<< "$contract")
  CONTRACT_RESOLVED_BACKEND=$(jq -r '.resolved_backend // empty' <<< "$contract")
  case "$CONTRACT_REQUESTED_BACKEND" in in_process|tmux) ;; *) fail_diag 'contract backend metadata is invalid' ;; esac
  case "$CONTRACT_RESOLVED_BACKEND" in in_process|tmux) ;; *) fail_diag 'contract backend metadata is invalid' ;; esac
  [ "$CONTRACT_REQUESTED_BACKEND" = "$CONTRACT_RESOLVED_BACKEND" ] || fail_diag 'contract backend metadata is invalid'
  jq -e --arg contract "$EXPECTED_CONTRACT" --arg requested "$CONTRACT_REQUESTED_BACKEND" --arg resolved "$CONTRACT_RESOLVED_BACKEND" '
    .schema_version == 3 and .contract_id == $contract
    and .requested_backend == $requested and .resolved_backend == $resolved
  ' "$RUN_ROOT/contract.json" >/dev/null || fail_diag 'contract backend metadata does not match the contract'
  jq -e --arg requested "$CONTRACT_REQUESTED_BACKEND" --arg resolved "$CONTRACT_RESOLVED_BACKEND" '
    .requested_backend == $requested and .resolved_backend == $resolved
  ' "$RUN_ROOT/run.json" >/dev/null || fail_diag 'run backend metadata does not match the contract'
  ROSTER_JSON=$(jq -ce '.teammates // [] | map(.name)' "$RUN_ROOT/run.json") \
    || fail_diag 'run state roster is unreadable'
  [ "$(jq 'length' <<< "$ROSTER_JSON")" -ge 1 ] || fail_diag 'run state has no teammates'
  CONTROL_ROOT_RECORD=$(jq -r '.control_root // empty' "$RUN_ROOT/run.json")
  [ -n "$CONTROL_ROOT_RECORD" ] || fail_diag 'run state is missing its control root record'
  MANIFEST_PATH=$(lbwc_control_root_manifest_path "$CONTROL_ROOT_RECORD" 2>/dev/null) \
    || fail_diag "control root is unavailable: $CONTROL_ROOT_RECORD"
  [ -f "$MANIFEST_PATH" ] || fail_diag "agent manifest is missing: $MANIFEST_PATH"
  jq -e 'type == "object" and (.agents | type == "object")' "$MANIFEST_PATH" >/dev/null \
    || fail_diag 'agent manifest is unreadable'
  jq -e --argjson roster "$ROSTER_JSON" --arg contract "$EXPECTED_CONTRACT" \
    --arg requested "$CONTRACT_REQUESTED_BACKEND" --arg resolved "$CONTRACT_RESOLVED_BACKEND" '
    . as $manifest
    | all($roster[];
        ($manifest.agents[.] | type == "object")
        and $manifest.agents[.].contract_id == $contract
        and ($manifest.agents[.].execution | type == "object")
        and $manifest.agents[.].execution.requested_backend == $requested
        and $manifest.agents[.].execution.resolved_backend == $resolved
      )
  ' "$MANIFEST_PATH" >/dev/null || fail_diag 'manifest backend metadata does not match the contract'
}

case "$ACTION" in
  preflight)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    require_file "$SCRIPT_DIR/cleanup-temporary-agent-runfiles.sh" 'cleanup helper not found'
    require_file "$SCRIPT_DIR/team-run-state.sh" 'run state helper not found'
    require_file "$SCRIPT_DIR/team-context-index.sh" 'context index helper not found'
    require_file "$SCRIPT_DIR/task-contract.sh" 'contract helper not found'
    require_file "$SCRIPT_DIR/agent-generator.sh" 'generator helper not found'
    require_file "$SCRIPT_DIR/lbwc-config.sh" 'config helper not found'
    require_file "$SCRIPT_DIR/lbwc-routing.sh" 'routing helper not found'
    resolve_scopes
    reject_protected_scopes
    resolve_active_control_root
    resolve_roster
    resolve_routing
    read_agent_teams_status
    jq -n \
      --arg project_root "$PROJECT_ROOT" \
      --argjson scopes "$RESOLVED_SCOPES" \
      --argjson roles "$ROSTER_ROLES_JSON" \
      --arg engineer "$ROSTER_ENGINEER" \
      --arg team_mode "$TEAM_MODE" \
      --arg control_root_kind "$CONTROL_ROOT_KIND" \
      --arg active_control_root "$ACTIVE_CONTROL_ROOT" \
      --arg routing_mode "$ROUTING_MODE" \
      --arg routing_profile "$ROUTING_PROFILE" \
      --arg model "$ROUTING_MODEL" \
      --argjson reasoning "$ROUTING_REASONING_JSON" \
      --arg max_turns "$ROUTING_MAX_TURNS" \
      --arg settings_path "$SETTINGS_PATH" \
      --argjson agent_teams_status "$AGENT_TEAMS_STATUS" \
      '{schema_version:1,project_root:$project_root,scopes:$scopes,roles:$roles,engineer:$engineer,
        team_mode:$team_mode,
        control_root_kind:$control_root_kind,active_control_root:$active_control_root,
        routing:{mode:$routing_mode,profile:$routing_profile,model:$model,reasoning:$reasoning,
          max_turns:($max_turns|tonumber)},
        agent_teams:{enabled:($agent_teams_status.enabled == true),settings_path:$settings_path,
          status:$agent_teams_status},
        side_effects:false}'
    ;;

  propose)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_roster
    jq -n --argjson roles "$ROSTER_ROLES_JSON" --arg engineer "$ROSTER_ENGINEER" \
      --arg critic "$ROSTER_CRITIC" --arg team_mode "$TEAM_MODE" \
      --argjson test_dev "$ROSTER_TEST_DEV" \
      '{schema_version:1,roles:$roles,engineer:$engineer,critic:$critic,team_mode:$team_mode,test_dev:$test_dev}'
    ;;

  prepare)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    [ -n "$RUN_ID" ] || fail '--run-id is required'
    is_valid_run_id "$RUN_ID" || fail 'run id is invalid'
    [ -n "$INSTRUCTION" ] || fail '--instruction is required'
    resolve_scopes
    reject_protected_scopes
    resolve_active_control_root
    resolve_roster

    scope_args=()
    while IFS= read -r scope; do
      [ -n "$scope" ] && scope_args+=(--scope "$scope")
    done < <(jq -r '.[]' <<< "$RESOLVED_SCOPES")
    RUN_ROOT=$(bash "$SCRIPT_DIR/team-run-state.sh" create \
      --project-root "$PROJECT_ROOT" --run-id "$RUN_ID" ${scope_args[@]+"${scope_args[@]}"}) \
      || fail 'run creation failed'

    CONTROL_ROOT="$ACTIVE_CONTROL_ROOT"
    if [ "$CONTROL_ROOT_KIND" = "temporary-run" ]; then
      CONTROL_ROOT="$RUN_ROOT"
      resolve_routing
      printf '%s\n' "$CATALOG_JSON" > "$CONTROL_ROOT/claude-capabilities.json"
      jq -n \
        --arg model "$ROUTING_MODEL" \
        --argjson reasoning "$ROUTING_REASONING_JSON" \
        --slurpfile defaults "$ROLE_DEFAULTS_PATH" \
        '{
          schema_version: 1,
          routing: {
            active_profile: "balanced",
            profiles: {
              quality: {roles: {}},
              balanced: {
                roles: ($defaults[0] | keys | map({key: ., value: {model: $model, reasoning: $reasoning, status: "resolved"}}) | from_entries)
              },
              turbo: {roles: {}}
            }
          }
        }' > "$CONTROL_ROOT/routing.json"
    fi

    capability_args=()
    scope=""
    while IFS= read -r scope; do
      [ -n "$scope" ] || continue
      capability_args+=(--role-write-capability "$ROSTER_ENGINEER:directory:$scope")
    done < <(jq -r '.[]' <<< "$RESOLVED_SCOPES")
    CONTRACT_PATH=$(bash "$SCRIPT_DIR/task-contract.sh" issue "$PROJECT_ROOT" "$RUN_ID" \
      --command team --role "$ROSTER_ENGINEER" --team "$TEAM_MODE" --job "$INSTRUCTION" \
      --control-root "$CONTROL_ROOT" --runtime-kind native-team --communication-policy native-team \
      --requested-backend in_process --resolved-backend in_process \
      ${capability_args[@]+"${capability_args[@]}"}) \
      || fail_diag 'contract issue failed'
    CONTRACT_ID=$(basename "$CONTRACT_PATH" .json)
    CONTRACT_JSON=$(bash "$SCRIPT_DIR/task-contract.sh" verify "$CONTRACT_PATH" "$PROJECT_ROOT") \
      || fail_diag 'contract verification failed'
    CONTRACT_REQUESTED_BACKEND=$(jq -r '.requested_backend' <<< "$CONTRACT_JSON")
    CONTRACT_RESOLVED_BACKEND=$(jq -r '.resolved_backend' <<< "$CONTRACT_JSON")

    GENERATED=()
    TEAMMATES_JSON='[]'
    generator_args=(--native-team)
    if [ "$TEAM_MODE" = "trio" ]; then
      generator_args+=(--trio "$ROSTER_ENGINEER")
    else
      generator_args+=(--pair "$ROSTER_ENGINEER")
    fi
    generator_args+=(--job "$INSTRUCTION" \
      --contract "$CONTRACT_PATH" --task-id "$CONTRACT_ID" --control-root "$CONTROL_ROOT")
    while IFS= read -r scope; do
      [ -n "$scope" ] || continue
      generator_args+=(--write-capability "directory:$scope")
    done < <(jq -r '.[]' <<< "$RESOLVED_SCOPES")
    GENERATOR_OUTPUT=$(bash "$SCRIPT_DIR/agent-generator.sh" "${generator_args[@]}") \
      || fail_diag "agent generation failed for '$TEAM_MODE' rooted at '$ROSTER_ENGINEER': $GENERATOR_OUTPUT"
    while IFS= read -r line; do
      case "$line" in
        SPAWN_READY\ *|*': SPAWN_READY '*)
          name="${line##*SPAWN_READY }"
          [ -n "$name" ] || fail_diag 'generator reported an empty spawn-ready name'
          GENERATED+=("$name")
          ;;
      esac
    done <<< "$GENERATOR_OUTPUT"
    [ "${#GENERATED[@]}" -eq "$(jq 'length' <<< "$ROSTER_ROLES_JSON")" ] \
      || fail_diag "generator registered ${#GENERATED[@]} names for a $(jq 'length' <<< "$ROSTER_ROLES_JSON")-role roster"
    MANIFEST_READ_PATH=$(lbwc_control_root_manifest_path "$CONTROL_ROOT") || fail_diag 'control root manifest path is unavailable'
    while IFS= read -r name; do
      role=$(jq -r --arg name "$name" '.agents[$name].role // empty' "$MANIFEST_READ_PATH")
      [ -n "$role" ] || fail_diag "generated name '$name' is not registered in the run manifest"
      TEAMMATES_JSON=$(jq -c --arg name "$name" --arg role "$role" '. + [{name:$name,role:$role}]' <<< "$TEAMMATES_JSON")
    done < <(printf '%s\n' ${GENERATED[@]+"${GENERATED[@]}"})

    bash "$SCRIPT_DIR/task-contract.sh" state "$PROJECT_ROOT" "$CONTRACT_ID" dispatched >/dev/null \
      || fail_diag 'contract dispatch failed'

    CONTRACT_RECORD_JSON=$(jq -cn --arg id "$CONTRACT_ID" --arg requested "$CONTRACT_REQUESTED_BACKEND" --arg resolved "$CONTRACT_RESOLVED_BACKEND" \
      '{schema_version:3,contract_id:$id,status:"dispatched",requested_backend:$requested,resolved_backend:$resolved}')
    printf '%s\n' "$CONTRACT_RECORD_JSON" > "$RUN_ROOT/contract.json"
    UPDATED_RUN=$(jq -c --argjson teammates "$TEAMMATES_JSON" --arg contract "$CONTRACT_ID" \
      --arg team_mode "$TEAM_MODE" --arg control_root "$CONTROL_ROOT" \
      --arg requested_backend "$CONTRACT_REQUESTED_BACKEND" --arg resolved_backend "$CONTRACT_RESOLVED_BACKEND" \
      '.records = (.records // {})
       | .records["contract:\($contract)"] = {kind:"contract",id:$contract,status:"dispatched",updated_at:(now | todate)}
       | .teammates = $teammates
       | .team_mode = $team_mode
       | .control_root = $control_root
       | .requested_backend = $requested_backend
       | .resolved_backend = $resolved_backend
       | .updated_at = (now | todate)' "$RUN_ROOT/run.json") \
      || fail_diag 'run state update failed'
    printf '%s\n' "$UPDATED_RUN" > "$RUN_ROOT/run.json"
    printf '%s\n' "$(jq -cn --arg id "$CONTRACT_ID" --argjson teammates "$TEAMMATES_JSON" \
      '{event:"prepare",contract_id:$id,teammates:$teammates,at:(now | todate)}')" \
      >> "$RUN_ROOT/diagnostics.jsonl" || fail_diag 'diagnostics append failed'

    jq -n \
      --arg run_root "$RUN_ROOT" \
      --arg control_root "$CONTROL_ROOT" \
      --arg control_root_kind "$CONTROL_ROOT_KIND" \
      --arg contract_path "$CONTRACT_PATH" \
      --arg contract_id "$CONTRACT_ID" \
      --arg team_mode "$TEAM_MODE" \
      --arg requested_backend "$CONTRACT_REQUESTED_BACKEND" --arg resolved_backend "$CONTRACT_RESOLVED_BACKEND" \
      --argjson teammates "$TEAMMATES_JSON" \
      --argjson scopes "$RESOLVED_SCOPES" \
      --arg engineer "$ROSTER_ENGINEER" \
      '{schema_version:3,run_root:$run_root,control_root:$control_root,
        control_root_kind:$control_root_kind,contract_path:$contract_path,contract_id:$contract_id,
        team_mode:$team_mode,teammates:$teammates,scopes:$scopes,engineer:$engineer,
         requested_backend:$requested_backend,resolved_backend:$resolved_backend,
        contract_state:"dispatched",task_subject:$contract_id,
        ordered_actions:["agent_spawn","task_create"]}'
    ;;

  spawn-payload)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    require_run_roster
    PAYLOADS='[]'
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      jq -e --arg name "$name" --arg contract "$EXPECTED_CONTRACT" '
        (.agents[$name] | type == "object")
        and (.agents[$name].contract_id == $contract)
        and (.agents[$name].state == "registered")
        and (.agents[$name].runtime_kind == "native-team")
      ' "$MANIFEST_PATH" >/dev/null || fail_diag "teammate '$name' is not spawn-ready for contract $EXPECTED_CONTRACT"
      PAYLOADS=$(jq -c --arg name "$name" '. + [{subagent_type:$name,name:$name}]' <<< "$PAYLOADS")
    done < <(jq -r '.[]' <<< "$ROSTER_JSON")
    jq -n --arg contract_id "$EXPECTED_CONTRACT" --argjson payloads "$PAYLOADS" \
      --argjson roster "$ROSTER_JSON" \
      '{schema_version:1,contract_id:$contract_id,roster:$roster,agent_payloads:$payloads,next_action:"task-payload"}'
    ;;

  record-spawn)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    [ -n "$CONTRACT_ID_ARG" ] || fail '--contract-id is required'
    is_valid_record_id "$CONTRACT_ID_ARG" || fail 'contract id is invalid'
    [ -n "$TEAMMATE_ARG" ] || fail '--teammate is required'
    is_valid_record_id "$TEAMMATE_ARG" || fail 'teammate name is invalid'
    require_run_roster
    [ "$CONTRACT_ID_ARG" = "$EXPECTED_CONTRACT" ] || fail_diag "contract id mismatch: expected $EXPECTED_CONTRACT"
    jq -e --arg name "$TEAMMATE_ARG" '.agents[$name] | type == "object"' "$MANIFEST_PATH" >/dev/null \
      || fail_diag "teammate is not registered in the run manifest: $TEAMMATE_ARG"
    jq -e --arg name "$TEAMMATE_ARG" '.agents[$name].state == "running"' "$MANIFEST_PATH" >/dev/null \
      || fail_diag "teammate '$TEAMMATE_ARG' is not running in the manifest; the spawn guard must claim it first"
    SPAWN_RECORD=$(jq -c --argjson roster "$ROSTER_JSON" --arg teammate "$TEAMMATE_ARG" '
      .records = (.records // {})
      | .records["spawn:\($teammate)"] = {kind:"spawn",id:$teammate,status:"recorded",updated_at:(now | todate)}
      | (([.records | to_entries[] | select(.key | startswith("spawn:")) | .value.id]) | unique) as $recorded
      | .spawned = $recorded
      | .spawn_complete = (($roster - $recorded) | length == 0)
      | .updated_at = (now | todate)
    ' "$RUN_ROOT/run.json") || fail_diag 'run state is unreadable'
    printf '%s\n' "$SPAWN_RECORD" > "$RUN_ROOT/run.json"
    printf '%s\n' "$(jq -cn --arg teammate "$TEAMMATE_ARG" --arg contract "$CONTRACT_ID_ARG" \
      '{event:"record-spawn",teammate:$teammate,contract_id:$contract,at:(now | todate)}')" \
      >> "$RUN_ROOT/diagnostics.jsonl" || fail_diag 'diagnostics append failed'
    SPAWN_COMPLETE=$(jq -r '.spawn_complete' <<< "$SPAWN_RECORD")
    SPAWNED_JSON=$(jq -c '.spawned // []' <<< "$SPAWN_RECORD")
    jq -n --arg teammate "$TEAMMATE_ARG" --arg contract_id "$CONTRACT_ID_ARG" \
      --argjson spawned "$SPAWNED_JSON" --argjson roster "$ROSTER_JSON" \
      --argjson complete "$SPAWN_COMPLETE" \
      '{schema_version:1,teammate:$teammate,contract_id:$contract_id,recorded:true,
        spawned:$spawned,roster:$roster,spawn_complete:$complete}'
    ;;

  task-payload)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    require_run_roster
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      jq -e --arg name "$name" --arg contract "$EXPECTED_CONTRACT" '
        (.agents[$name] | type == "object")
        and (.agents[$name].contract_id == $contract)
        and (.agents[$name].state == "running")
      ' "$MANIFEST_PATH" >/dev/null || fail_diag "teammate '$name' is not running in the manifest"
      jq -e --arg key "spawn:$name" '.records[$key].status == "recorded"' "$RUN_ROOT/run.json" >/dev/null \
        || fail_diag "spawn evidence is missing for teammate: $name"
    done < <(jq -r '.[]' <<< "$ROSTER_JSON")
    jq -n --arg contract_id "$EXPECTED_CONTRACT" --argjson roster "$ROSTER_JSON" \
      '{schema_version:1,task:{subject:$contract_id,description:$contract_id},
        contract_id:$contract_id,roster:$roster}'
    ;;

  record-task)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    [ -n "$CONTRACT_ID_ARG" ] || fail '--contract-id is required'
    is_valid_record_id "$CONTRACT_ID_ARG" || fail 'contract id is invalid'
    [ -n "$TASK_ID_ARG" ] || fail '--task-id is required'
    is_valid_record_id "$TASK_ID_ARG" || fail 'task id is invalid'
    require_run_roster
    [ "$CONTRACT_ID_ARG" = "$EXPECTED_CONTRACT" ] || fail_diag "contract id mismatch: expected $EXPECTED_CONTRACT"
    jq -e --arg task "$TASK_ID_ARG" --arg contract "$CONTRACT_ID_ARG" \
      '.tasks[$task].contract_id == $contract' "$MANIFEST_PATH" >/dev/null \
      || fail_diag "native task is not bound to this contract: $TASK_ID_ARG"
    TASK_RECORD=$(jq -c --arg task "$TASK_ID_ARG" '
      .records = (.records // {})
      | .records["task:\($task)"] = {kind:"task",id:$task,status:"bound",updated_at:(now | todate)}
      | .updated_at = (now | todate)
    ' "$RUN_ROOT/run.json") || fail_diag 'run state is unreadable'
    printf '%s\n' "$TASK_RECORD" > "$RUN_ROOT/run.json"
    printf '%s\n' "$(jq -cn --arg task "$TASK_ID_ARG" --arg contract "$CONTRACT_ID_ARG" \
      '{event:"record-task",task_id:$task,contract_id:$contract,at:(now | todate)}')" \
      >> "$RUN_ROOT/diagnostics.jsonl" || fail_diag 'diagnostics append failed'
    jq -n --arg task_id "$TASK_ID_ARG" --arg contract_id "$CONTRACT_ID_ARG" \
      '{schema_version:1,task_id:$task_id,contract_id:$contract_id,recorded:true,contract_state:"dispatched"}'
    ;;

  fail)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    bash "$SCRIPT_DIR/team-run-state.sh" update --run-root "$RUN_ROOT" \
      --status failed ${EVENT_TEXT:+--event "$EVENT_TEXT"} >/dev/null \
      || fail_diag 'run state update failed'
    jq -n --arg run_root "$RUN_ROOT" --arg event "$EVENT_TEXT" \
      '{schema_version:1,run_root:$run_root,status:"failed",event:$event}'
    ;;

  complete)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    bash "$SCRIPT_DIR/team-run-state.sh" update --run-root "$RUN_ROOT" \
      --status completed ${EVENT_TEXT:+--event "$EVENT_TEXT"} >/dev/null \
      || fail_diag 'run state update failed'
    jq -n --arg run_root "$RUN_ROOT" --arg event "$EVENT_TEXT" \
      '{schema_version:1,run_root:$run_root,status:"completed",event:$event}'
    ;;

  summary)
    PROJECT_ROOT=$(canonical_project_root "$PROJECT_ROOT_ARG")
    resolve_run_root
    bash "$SCRIPT_DIR/team-run-state.sh" summary --run-root "$RUN_ROOT" \
      || fail_diag 'summary failed'
    ;;
esac
