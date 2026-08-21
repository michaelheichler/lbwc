#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_PATH="$SCRIPT_DIR/../config/settings.json"
ROLE_DEFAULTS_PATH="$SCRIPT_DIR/../templates/agent-roles/defaults.json"
ROUTING_PATH="$SCRIPT_DIR/lbwc-routing.sh"
LOCK_ATTEMPTS=100
LOCK_SLEEP_SECONDS=0.05
LOCK_DIR=""

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: lbwc-config.sh <init|migrate|validate|get|set|set-json> <planning-dir> [setting] [json-value]' >&2
  printf '%s\n' '       lbwc-config.sh default-config' >&2
  printf '%s\n' '       lbwc-config.sh validate-config-json (reads JSON on stdin)' >&2
  printf '%s\n' '       lbwc-config.sh validate-tmux-execution-json (reads JSON on stdin)' >&2
  printf '%s\n' '       lbwc-config.sh agent-teams-status --settings PATH [--project-root PATH]' >&2
  printf '%s\n' '       lbwc-config.sh agent-teams-check --settings PATH [--project-root PATH]' >&2
  printf '%s\n' '       lbwc-config.sh agent-teams-enable --settings PATH --approved' >&2
}

require_jq() {
  command -v jq >/dev/null 2>&1 || fail 'jq is required'
}

default_claude_settings_path() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_CONFIG_DIR/settings.json"
  elif [ -d "$HOME/.config/claude-code" ]; then
    printf '%s\n' "$HOME/.config/claude-code/settings.json"
  else
    printf '%s\n' "$HOME/.claude/settings.json"
  fi
}

agent_teams_file_is_object() {
  jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

agent_teams_file_setting() {
  local settings_path="$1" setting_value
  [ -f "$settings_path" ] || return 1
  agent_teams_file_is_object "$settings_path" || return 1
  if ! jq -e '(.env | type) == "object" and (.env | has("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"))' \
    "$settings_path" >/dev/null 2>&1; then
    return 1
  fi
  setting_value=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS | tostring' "$settings_path")
  printf '%s\n' "$setting_value"
}

agent_teams_settings_candidates() {
  local settings_path="$1" project_root="$2" settings_explicit="$3"
  local dir
  if [ "$settings_explicit" = true ]; then
    printf '%s\n' "$settings_path"
    return 0
  fi
  dir=$(dirname "$settings_path")
  if [ -n "$project_root" ]; then
    printf '%s\n' "$project_root/.claude/settings.local.json"
    printf '%s\n' "$project_root/.claude/settings.json"
  fi
  printf '%s\n' "$dir/settings.local.json"
  printf '%s\n' "$settings_path"
}

agent_teams_status() {
  local settings_path="$1" project_root="$2" settings_explicit="$3"
  local candidate seen="" fail_closed=false setting_value
  if [ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS+x}" ]; then
    if [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" ]; then
      jq -n '{enabled:true,source:"environment"}'
    else
      jq -n '{enabled:false,source:"environment"}'
    fi
    return 0
  fi
  [ "$settings_explicit" = true ] && fail_closed=true
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    case " $seen " in
      *" $candidate "*) continue ;;
    esac
    seen="$seen $candidate"
    if [ -f "$candidate" ] && ! agent_teams_file_is_object "$candidate"; then
      [ "$fail_closed" = true ] && fail "settings file is not valid JSON: $candidate"
      continue
    fi
    if setting_value=$(agent_teams_file_setting "$candidate"); then
      if [ "$setting_value" = "1" ]; then
        jq -n --arg path "$candidate" '{enabled:true,source:"settings",settings_path:$path}'
      else
        jq -n --arg path "$candidate" '{enabled:false,source:"settings",settings_path:$path}'
      fi
      return 0
    fi
  done < <(agent_teams_settings_candidates "$settings_path" "$project_root" "$settings_explicit")
  jq -n --arg path "$settings_path" '{enabled:false,source:"none",settings_path:$path}'
}

agent_teams_check() {
  local status_json enabled
  status_json=$(agent_teams_status "$1" "$2" "$3")
  enabled=$(jq -r '.enabled' <<< "$status_json")
  if [ "$enabled" = true ]; then
    printf '%s\n' 'TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK.'
  else
    printf '%s\n' 'TEAM CHECK IS NOT ENABLED.'
  fi
}

agent_teams_enable() {
  local settings_path="$1" approved="$2" temporary
  [ "$approved" = true ] || fail 'agent teams setting requires explicit approval'
  mkdir -p "$(dirname "$settings_path")"
  [ -f "$settings_path" ] || printf '{}\n' > "$settings_path"
  jq -e 'type == "object"' "$settings_path" >/dev/null 2>&1 || fail "settings file is not valid JSON: $settings_path"
  temporary="${settings_path}.lbwc-agent-teams.tmp.${BASHPID:-$$}"
  jq '.env = (.env // {}) | .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' "$settings_path" > "$temporary" || {
    rm -f "$temporary"
    fail "could not write agent teams setting: $settings_path"
  }
  mv -f "$temporary" "$settings_path" || {
    rm -f "$temporary"
    fail "could not persist agent teams setting: $settings_path"
  }
  jq -n --arg path "$settings_path" '{enabled:true,source:"settings",settings_path:$path,restart_required:true,message:"Agent Teams enabled in settings. You must restart Claude Code before running /lbwc:team."}'
}

global_command() {
  local command="$1" settings_path="" approved=false project_root="" settings_explicit=false
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --settings)
        [ "$#" -ge 2 ] || fail '--settings requires a path'
        settings_path="$2"
        settings_explicit=true
        shift 2
        ;;
      --project-root)
        [ "$#" -ge 2 ] || fail '--project-root requires a path'
        project_root="$2"
        shift 2
        ;;
      --approved)
        approved=true
        shift
        ;;
      *)
        fail "unknown agent teams option: $1"
        ;;
    esac
  done
  if [ -z "$settings_path" ]; then
    settings_path=$(default_claude_settings_path)
  fi
  case "$command" in
    agent-teams-status)
      [ "$approved" = false ] || fail '--approved is not valid for status'
      agent_teams_status "$settings_path" "$project_root" "$settings_explicit"
      ;;
    agent-teams-check)
      [ "$approved" = false ] || fail '--approved is not valid for check'
      agent_teams_check "$settings_path" "$project_root" "$settings_explicit"
      ;;
    agent-teams-enable) agent_teams_enable "$settings_path" "$approved" ;;
    *) return 1 ;;
  esac
}

parity_defaults_json() {
  cat <<'JSON'
{
  "skill_suggestions": true,
  "auto_install_skills": false,
  "discovery_questions": true,
  "discussion_mode": "questions",
  "visual_format": "unicode",
  "pipeline_research": false,
  "branch_per_milestone": false,
  "plain_summary": true,
  "active_profile": "default",
  "custom_profiles": {},
  "agent_max_turns": {},
  "qa_skip_agents": [],
  "token_budgets": true,
  "two_phase_completion": true,
  "smart_routing": true,
  "validation_gates": true,
  "snapshot_resume": true,
  "lease_locks": true,
  "event_recovery": true,
  "worktree_isolation": "off",
  "monorepo_routing": true,
  "debug_logging": false,
  "statusline_hide_limits": false,
  "statusline_hide_limits_for_api_key": false,
  "statusline_hide_agent_in_tmux": false,
  "statusline_collapse_agent_in_tmux": false
}
JSON
}

read_defaults() {
  local base parity
  [ -f "$DEFAULTS_PATH" ] || fail "default configuration is not readable: $DEFAULTS_PATH"
  base=$(cat "$DEFAULTS_PATH")
  jq -e 'type == "object"' <<< "$base" >/dev/null 2>&1 \
    || fail "default configuration is not valid JSON: $DEFAULTS_PATH"
  parity=$(parity_defaults_json)
  jq -cn --argjson base "$base" --argjson parity "$parity" '$base * $parity' \
    || fail 'could not build default configuration'
}

allowed_role_names() {
  [ -f "$ROLE_DEFAULTS_PATH" ] || fail "role defaults are not readable: $ROLE_DEFAULTS_PATH"
  jq -ce '[keys[] | select(. != "oracles" and . != "trios")]' "$ROLE_DEFAULTS_PATH" \
    || fail "role defaults are not valid JSON: $ROLE_DEFAULTS_PATH"
}

config_path() {
  printf '%s/config.json\n' "$1"
}

resolve_known_system_alias() {
  local current="$1" target
  case "$current" in
    /var|"/var/"*)
      [ -L /var ] || {
        printf '%s\n' "$current"
        return 0
      }
      target=$(readlink /var) || fail 'could not resolve the macOS /var alias'
      [ "$target" = 'private/var' ] || {
        printf '%s\n' "$current"
        return 0
      }
      printf '/private/var%s\n' "${current#/var}"
      ;;
    *)
      printf '%s\n' "$current"
      ;;
  esac
}

assert_no_symbolic_links() {
  local current="$1" parent
  if [[ "$current" != "/"* ]]; then
    current="$(pwd -P)/$current"
  fi
  current=$(resolve_known_system_alias "$current")
  while [ "$current" != "/" ] && [ "${current%/}" != "$current" ]; do
    current=${current%/}
  done
  while :; do
    [ ! -L "$current" ] || fail "symbolic link paths are not allowed: $current"
    [ "$current" = "/" ] && return 0
    parent=$(dirname "$current")
    [ "$parent" != "$current" ] || return 0
    current="$parent"
  done
}

cleanup_lock() {
  if [ -n "$LOCK_DIR" ] && [ -d "$LOCK_DIR" ]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

enter_planning_dir() {
  local planning_dir="$1" opened_dir
  cd -P -- "$planning_dir" || fail "could not enter planning directory: $planning_dir"
  opened_dir=$(pwd -P) || fail "could not resolve planning directory: $planning_dir"
  assert_no_symbolic_links "$opened_dir"
}

acquire_lock() {
  local attempt=0
  LOCK_DIR=".config.lock"
  assert_no_symbolic_links "$LOCK_DIR"
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    assert_no_symbolic_links "$LOCK_DIR"
    attempt=$((attempt + 1))
    [ "$attempt" -lt "$LOCK_ATTEMPTS" ] || fail "could not acquire configuration lock: $LOCK_DIR"
    sleep "$LOCK_SLEEP_SECONDS"
  done
  assert_no_symbolic_links "$LOCK_DIR"
}

validate_config_json() {
  local value="$1" roles
  roles=$(allowed_role_names)
  jq -e --argjson roles "$roles" '
    def effort: type == "string" and IN("thorough", "balanced", "fast", "turbo");
    def autonomy: type == "string" and IN("cautious", "standard", "confident", "pure-vibe");
    def verification_tier: type == "string" and IN("quick", "standard", "deep");
    def positive_integer: type == "number" and . > 0 and . == floor;
    def role_name:
      . as $name | type == "string" and ($roles | index($name) != null);
    def turn_limit:
      . == false or (type == "number" and . >= 0 and . == floor);
    def turn_setting:
      turn_limit
      or (
        type == "object"
        and all(to_entries[]; (.key | IN("thorough", "balanced", "fast", "turbo")) and (.value | turn_limit))
      );
    def custom_profile_name:
      . as $name
      | type == "string"
      and ($name | test("^[a-z0-9]+(-[a-z0-9]+)*$") and length <= 30)
      and (["default", "prototype", "production", "yolo", "custom"] | index($name) == null);
    def custom_profile:
      type == "object"
      and (keys | sort == ["autonomy", "effort", "verification_tier"])
      and (.effort | effort)
      and (.autonomy | autonomy)
      and (.verification_tier | verification_tier);
    def exact_keys($allowed):
      (keys - $allowed | length) == 0;
    def tmux_restrictions:
      type == "object"
      and exact_keys([
        "allow_nested_spawn", "allow_agent_git", "allow_agent_ask_user", "require_orchestrator_attach"
      ])
      and (.allow_nested_spawn | type == "boolean")
      and (.allow_agent_git | type == "boolean")
      and (.allow_agent_ask_user | type == "boolean")
      and (.require_orchestrator_attach | type == "boolean");
    def tmux_execution:
      type == "object"
      and exact_keys([
        "enabled", "session_name_prefix", "max_agents",
        "attach_policy", "heartbeat_interval_seconds",
        "heartbeat_stale_seconds", "comms_latency_tolerance_ms", "comms_fallback",
        "cleanup_policy", "layout", "restrictions"
      ])
      and (.enabled | type == "boolean")
      and (.session_name_prefix | type == "string" and test("^[A-Za-z][A-Za-z0-9_-]{0,31}$"))
      and (.max_agents | type == "number" and . >= 1 and . <= 4 and . == floor)
      and (.attach_policy | type == "string" and IN("orchestrator_only", "visible_grid"))
      and (.heartbeat_interval_seconds | positive_integer)
      and (.heartbeat_stale_seconds | positive_integer)
      and (.comms_latency_tolerance_ms | positive_integer)
      and (.comms_fallback | type == "string" and IN("bus_only", "fall_back_to_in_process"))
      and (.cleanup_policy | type == "string" and IN("kill_on_complete", "keep_panes"))
      and (.layout | type == "string" and IN("main-vertical", "main-horizontal", "tiled", "even-horizontal", "even-vertical"))
      and (.restrictions | tmux_restrictions);
    def workflow_execution:
      type == "object"
      and exact_keys(["enabled"])
      and (.enabled | type == "boolean");
    type == "object"
    and exact_keys([
      "schema_version", "effort", "autonomy", "auto_commit", "planning_tracking", "auto_push",
      "verification_tier", "skill_suggestions", "auto_install_skills", "discovery_questions",
      "discussion_mode", "context_compiler", "visual_format", "max_tasks_per_plan", "prefer_teams",
      "agent_execution_mode", "tmux_execution", "workflow_execution",
      "pipeline_research", "branch_per_milestone", "plain_summary", "active_profile", "custom_profiles",
      "agent_max_turns", "qa_skip_agents", "auto_uat", "require_phase_discussion", "rolling_summary",
      "metrics", "token_budgets", "two_phase_completion", "smart_routing", "validation_gates",
      "snapshot_resume", "lease_locks", "event_recovery", "worktree_isolation", "monorepo_routing",
      "debug_logging", "statusline_hide_limits", "statusline_hide_limits_for_api_key",
      "statusline_hide_agent_in_tmux", "statusline_collapse_agent_in_tmux", "caveman_style",
      "caveman_commit", "caveman_review", "max_uat_remediation_rounds", "routing", "model_profile", "roles"
    ])
    and .schema_version == 1
    and (.effort | effort)
    and (.autonomy | autonomy)
    and (.auto_commit | type == "boolean")
    and (.planning_tracking | type == "string" and IN("manual", "ignore", "commit"))
    and (.auto_push | type == "string" and IN("never", "after_phase", "always"))
    and (.verification_tier | verification_tier)
    and (.skill_suggestions | type == "boolean")
    and (.auto_install_skills | type == "boolean")
    and (.discovery_questions | type == "boolean")
    and (.discussion_mode | type == "string" and IN("questions", "assumptions", "auto"))
    and (.context_compiler | type == "boolean")
    and (.visual_format | type == "string" and IN("unicode", "ascii"))
    and (.max_tasks_per_plan | type == "number" and . > 0 and . == floor)
    and (.prefer_teams | type == "string" and IN("always", "auto", "never"))
    and (.agent_execution_mode | type == "string" and IN("in_process", "tmux", "workflow", "ask"))
    and (.tmux_execution | tmux_execution)
    and (.workflow_execution | workflow_execution)
    and (.pipeline_research | type == "boolean")
    and (.branch_per_milestone | type == "boolean")
    and (.plain_summary | type == "boolean")
    and (.active_profile | type == "string")
    and (.custom_profiles | type == "object" and all(to_entries[]; (.key | custom_profile_name) and (.value | custom_profile)))
    and (
      . as $config
      | .active_profile as $active
      | $active == "custom"
        or $active == "default"
        or $active == "prototype"
        or $active == "production"
        or $active == "yolo"
        or ($config.custom_profiles | has($active))
    )
    and (.agent_max_turns | type == "object" and all(to_entries[]; (.key | role_name) and (.value | turn_setting)))
    and (.qa_skip_agents | type == "array" and length == ([.[]] | unique | length) and all(.[]; role_name))
    and (.auto_uat | type == "boolean")
    and (.require_phase_discussion | type == "boolean")
    and (.rolling_summary | type == "boolean")
    and (.metrics | type == "boolean")
    and (.token_budgets | type == "boolean")
    and (.two_phase_completion | type == "boolean")
    and (.smart_routing | type == "boolean")
    and (.validation_gates | type == "boolean")
    and (.snapshot_resume | type == "boolean")
    and (.lease_locks | type == "boolean")
    and (.event_recovery | type == "boolean")
    and (.worktree_isolation | type == "string" and IN("off", "on"))
    and (.monorepo_routing | type == "boolean")
    and (.debug_logging | type == "boolean")
    and (.statusline_hide_limits | type == "boolean")
    and (.statusline_hide_limits_for_api_key | type == "boolean")
    and (.statusline_hide_agent_in_tmux | type == "boolean")
    and (.statusline_collapse_agent_in_tmux | type == "boolean")
    and (.caveman_style | type == "string" and IN("none", "lite", "full", "ultra", "auto"))
    and (.caveman_commit | type == "boolean")
    and (.caveman_review | type == "boolean")
    and (.max_uat_remediation_rounds | . == false or (type == "number" and . > 0 and . == floor))
    and (.routing | type == "object" and exact_keys(["active_profile", "profiles"]))
    and (.routing.active_profile | type == "string" and IN("quality", "balanced", "turbo"))
    and (.routing.profiles | type == "object" and (keys | sort == ["balanced", "quality", "turbo"]))
    and (.routing.profiles.quality | type == "object" and (keys | sort == ["roles"]) and (.roles | type == "object"))
    and (.routing.profiles.balanced | type == "object" and (keys | sort == ["roles"]) and (.roles | type == "object"))
    and (.routing.profiles.turbo | type == "object" and (keys | sort == ["roles"]) and (.roles | type == "object"))
    and (if has("model_profile") then .model_profile | IN("quality", "balanced", "budget", "turbo") else true end)
    and (if has("roles") then .roles | type == "object" else true end)
  ' <<< "$value" >/dev/null 2>&1
}

validate_or_fail() {
  local value="$1"
  validate_config_json "$value" || fail 'invalid configuration'
}

validate_tmux_execution_json() {
  local tmux_execution default_config config
  tmux_execution=$(cat)
  jq -e 'type == "object"' <<< "$tmux_execution" >/dev/null 2>&1 \
    || fail 'invalid tmux execution configuration'
  default_config=$(migrate_config_json '{}') || fail 'could not build default configuration'
  config=$(jq -cn --argjson defaults "$default_config" --argjson tmux_execution "$tmux_execution" \
    '$defaults | .tmux_execution = $tmux_execution') \
    || fail 'could not build tmux execution validation configuration'
  validate_config_json "$config" || fail 'invalid tmux execution configuration'
  printf '%s\n' "$tmux_execution"
}

read_existing_config() {
  local path="$1"
  assert_no_symbolic_links "$path"
  if [ ! -e "$path" ]; then
    printf '{}\n'
    return 0
  fi
  [ -f "$path" ] || fail "configuration is not a file: $path"
  jq -e 'type == "object"' "$path" >/dev/null 2>&1 || fail "configuration is not valid JSON: $path"
  cat "$path"
}

assert_supported_config_version() {
  local value="$1"
  jq -e 'if has("schema_version") then .schema_version == 1 else true end' <<< "$value" >/dev/null 2>&1 || fail 'unsupported configuration version'
}

migrate_config_json() {
  local existing="$1" defaults
  defaults=$(read_defaults)
  jq -cn --argjson defaults "$defaults" --argjson existing "$existing" '
    def normalized_profile($value):
      if $value == "budget" then "turbo" else $value end;
    ($defaults * $existing)
    | .schema_version = 1
    | .routing = (.routing // {})
    | .routing.profiles = (.routing.profiles // {})
    | .routing.profiles.quality = (.routing.profiles.quality // {})
    | .routing.profiles.balanced = (.routing.profiles.balanced // {})
    | .routing.profiles.turbo = (.routing.profiles.turbo // {})
    | .routing.profiles.quality.roles = (.routing.profiles.quality.roles // {})
    | .routing.profiles.balanced.roles = (.routing.profiles.balanced.roles // {})
    | .routing.profiles.turbo.roles = (.routing.profiles.turbo.roles // {})
    | .tmux_execution = (($defaults.tmux_execution // {}) * (.tmux_execution // {}))
    | .tmux_execution |= del(.session_timeout_seconds, .pane_base_index)
    | .tmux_execution.restrictions = (($defaults.tmux_execution.restrictions // {}) * (.tmux_execution.restrictions // {}))
    | .workflow_execution = (($defaults.workflow_execution // {}) * (.workflow_execution // {}))
    | .routing.active_profile = (
        if $existing.routing.active_profile? != null
        then normalized_profile($existing.routing.active_profile)
        elif $existing.model_profile? != null
        then normalized_profile($existing.model_profile)
        else "balanced"
        end
      )
  '
}

atomic_write() {
  local path="$1" value="$2" temporary
  [ "$path" = "${path##*/}" ] || fail "configuration path must be relative: $path"
  assert_no_symbolic_links "$path"
  temporary=$(mktemp "./.config.json.tmp.XXXXXX") || fail 'could not create configuration temporary file'
  assert_no_symbolic_links "$temporary"
  if ! printf '%s\n' "$value" > "$temporary"; then
    rm -f "$temporary"
    fail "could not write configuration temporary file: $temporary"
  fi
  assert_no_symbolic_links "$path"
  mv -f "$temporary" "$path" || {
    rm -f "$temporary"
    fail "could not atomically persist configuration: $path"
  }
}

initialize_config() {
  local planning_dir="$1" path reported_path existing migrated
  read_defaults >/dev/null
  assert_no_symbolic_links "$planning_dir"
  mkdir -p "$planning_dir" || fail "could not create planning directory: $planning_dir"
  assert_no_symbolic_links "$planning_dir"
  reported_path=$(config_path "$planning_dir")
  enter_planning_dir "$planning_dir"
  acquire_lock
  path="config.json"
  assert_no_symbolic_links "$path"
  existing=$(read_existing_config "$path")
  assert_supported_config_version "$existing"
  migrated=$(migrate_config_json "$existing") || fail 'could not migrate configuration'
  validate_or_fail "$migrated"
  atomic_write "$path" "$migrated"
  printf '%s\n' "$reported_path"
}

validate_config_file() {
  local planning_dir="$1" path value
  path=$(config_path "$planning_dir")
  [ -f "$path" ] || fail "configuration is not readable: $path"
  value=$(read_existing_config "$path")
  validate_or_fail "$value"
  printf '%s\n' "$path"
}

setting_is_writable() {
  case "$1" in
    effort|autonomy|auto_commit|planning_tracking|auto_push|verification_tier|skill_suggestions|auto_install_skills|discovery_questions|discussion_mode|context_compiler|visual_format|max_tasks_per_plan|prefer_teams|agent_execution_mode|tmux_execution|tmux_execution.enabled|tmux_execution.session_name_prefix|tmux_execution.max_agents|tmux_execution.attach_policy|tmux_execution.heartbeat_interval_seconds|tmux_execution.heartbeat_stale_seconds|tmux_execution.comms_latency_tolerance_ms|tmux_execution.comms_fallback|tmux_execution.cleanup_policy|tmux_execution.layout|tmux_execution.restrictions.allow_nested_spawn|tmux_execution.restrictions.allow_agent_git|tmux_execution.restrictions.allow_agent_ask_user|tmux_execution.restrictions.require_orchestrator_attach|workflow_execution|workflow_execution.enabled|pipeline_research|branch_per_milestone|plain_summary|active_profile|custom_profiles|agent_max_turns|qa_skip_agents|auto_uat|require_phase_discussion|rolling_summary|metrics|token_budgets|two_phase_completion|smart_routing|validation_gates|snapshot_resume|lease_locks|event_recovery|worktree_isolation|monorepo_routing|debug_logging|statusline_hide_limits|statusline_hide_limits_for_api_key|statusline_hide_agent_in_tmux|statusline_collapse_agent_in_tmux|caveman_style|caveman_commit|caveman_review|max_uat_remediation_rounds|routing.active_profile)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

plan_execution_is_active() {
  local planning_dir="$1" execution_state="$1/.execution-state.json" state_file="$1/STATE.md" contract_path
  if [ -f "$execution_state" ] && jq -e '.status | IN("running", "executing", "active")' "$execution_state" >/dev/null 2>&1; then
    return 0
  fi
  if [ -f "$state_file" ] && grep -Eq '^[[:space:]]*Status:[[:space:]]*(active|executing)[[:space:]]*$' "$state_file"; then
    return 0
  fi
  for contract_path in "$planning_dir/.contracts/tasks/"*.json; do
    [ -f "$contract_path" ] || continue
    if jq -e '.state | IN("dispatched", "running")' "$contract_path" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

running_tmux_agents_exist() {
  local planning_dir="$1" registry="$1/.runtime/tmux-bus/registry.json"
  [ -f "$registry" ] || return 1
  jq -e '
    type == "object"
    and (.agents | type == "array")
    and all(.agents[];
      type == "object"
      and (.state | type == "string" and IN("registered", "running", "idle", "failed", "shutdown"))
    )
  ' "$registry" >/dev/null 2>&1 || return 2
  jq -e '[.agents[] | select(.state == "running")] | length > 0' "$registry" >/dev/null 2>&1
}

execution_setting_is_frozen() {
  local planning_dir="$1" setting="$2" value="$3" registry_status=0
  plan_execution_is_active "$planning_dir" || return 1
  case "$setting" in
    agent_execution_mode)
      if [ "$value" = '"in_process"' ]; then
        running_tmux_agents_exist "$planning_dir" || registry_status=$?
        case "$registry_status" in
          0) return 0 ;;
          1) return 1 ;;
          *) return 0 ;;
        esac
      fi
      return 0
      ;;
    tmux_execution.cleanup_policy|statusline_hide_agent_in_tmux|statusline_collapse_agent_in_tmux)
      return 1
      ;;
    tmux_execution|tmux_execution.*|workflow_execution|workflow_execution.*|effort|routing.active_profile)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_execution_setting_is_writable() {
  local planning_dir="$1" setting="$2" value="$3"
  if execution_setting_is_frozen "$planning_dir" "$setting" "$value"; then
    fail "execution configuration is frozen while a plan is active: $setting"
  fi
}

get_setting() {
  local planning_dir="$1" setting="$2" path value
  path=$(config_path "$planning_dir")
  value=$(read_existing_config "$path")
  validate_or_fail "$value"
  jq -e --arg setting "$setting" 'getpath($setting | split(".")) != null' <<< "$value" >/dev/null || fail "unknown setting: $setting"
  jq --arg setting "$setting" 'getpath($setting | split("."))' <<< "$value"
}

set_setting() {
  local planning_dir="$1" setting="$2" literal="$3" path reported_path planning_root existing updated
  setting_is_writable "$setting" || fail "setting is not writable: $setting"
  jq -e 'type' <<< "$literal" >/dev/null 2>&1 || fail 'setting value is not valid JSON'
  assert_no_symbolic_links "$planning_dir"
  [ -d "$planning_dir" ] || fail "planning directory does not exist: $planning_dir"
  reported_path=$(config_path "$planning_dir")
  enter_planning_dir "$planning_dir"
  planning_root=$(pwd -P)
  acquire_lock
  path="config.json"
  existing=$(read_existing_config "$path")
  validate_or_fail "$existing"
  assert_execution_setting_is_writable "$planning_root" "$setting" "$literal"
  updated=$(jq -c --arg setting "$setting" --argjson value "$literal" 'setpath($setting | split("."); $value)' <<< "$existing") || fail 'could not update configuration'
  validate_or_fail "$updated"
  atomic_write "$path" "$updated"
  printf '%s\n' "$reported_path"
}

prepare_transaction_directory() {
  local command="$1" planning_dir="$2"
  assert_no_symbolic_links "$planning_dir"
  case "$command" in
    init|migrate)
      mkdir -p "$planning_dir" || fail "could not create planning directory: $planning_dir"
      ;;
    *)
      [ -d "$planning_dir" ] || fail "planning directory does not exist: $planning_dir"
      ;;
  esac
  assert_no_symbolic_links "$planning_dir"
}

main() {
  local command="${1:-}" planning_dir="${2:-}"
  require_jq
  case "$command" in
    agent-teams-status|agent-teams-check|agent-teams-enable)
      shift
      global_command "$command" "$@"
      return
      ;;
    default-config)
      [ "$#" -eq 1 ] || { usage; exit 1; }
      local default_config
      default_config=$(migrate_config_json '{}') || fail 'could not build default configuration'
      validate_or_fail "$default_config"
      jq '.' <<< "$default_config"
      return
      ;;
    validate-config-json)
      [ "$#" -eq 1 ] || { usage; exit 1; }
      local stdin_config
      stdin_config=$(cat)
      validate_or_fail "$stdin_config"
      printf '%s\n' "$stdin_config"
      return
      ;;
    validate-tmux-execution-json)
      [ "$#" -eq 1 ] || { usage; exit 1; }
      validate_tmux_execution_json
      return
      ;;
  esac
  [ -n "$command" ] && [ -n "$planning_dir" ] || { usage; exit 1; }
  [ -f "$ROUTING_PATH" ] || fail "routing transaction script is unavailable: $ROUTING_PATH"
  if [ "${LBWC_CONFIG_TRANSACTION_ACTIVE:-0}" != 1 ]; then
    prepare_transaction_directory "$command" "$planning_dir"
    exec bash "$ROUTING_PATH" transaction "$planning_dir" bash "$0" "$@"
  fi
  bash "$ROUTING_PATH" assert-transaction "$planning_dir" >/dev/null
  trap cleanup_lock EXIT
  case "$command" in
    init|migrate)
      [ "$#" -eq 2 ] || { usage; exit 1; }
      initialize_config "$planning_dir"
      ;;
    validate)
      [ "$#" -eq 2 ] || { usage; exit 1; }
      validate_config_file "$planning_dir"
      ;;
    get)
      [ "$#" -eq 3 ] || { usage; exit 1; }
      get_setting "$planning_dir" "$3"
      ;;
    assert-execution-setting-writable)
      [ "$#" -eq 4 ] || { usage; exit 1; }
      setting_is_writable "$3" || fail "setting is not writable: $3"
      jq -e 'type' <<< "$4" >/dev/null 2>&1 || fail 'setting value is not valid JSON'
      assert_execution_setting_is_writable "$planning_dir" "$3" "$4"
      ;;
    set|set-json)
      [ "$#" -eq 4 ] || { usage; exit 1; }
      set_setting "$planning_dir" "$3" "$4"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
