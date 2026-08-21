#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLE_DEFAULTS_PATH="$SCRIPT_DIR/../templates/agent-roles/defaults.json"
ENV_TOOL=""
LOCK_DIR=""
LOCK_DIR_IDENTITY=""
LOCK_BACKEND=""
LOCK_FD=9
LOCK_GUARD=""
LOCK_HELD=0
LOCK_TOOL=""
LOCK_OWNER_RECORD=""
LOCK_STALE_AFTER_SECONDS=30
LOCK_WAIT_ATTEMPTS_DEFAULT=500
OD_TOOL=""
STAT_STYLE=""
STAT_TOOL=""
TRANSACTION_ACTIVE="${LBWC_CONFIG_TRANSACTION_ACTIVE:-0}"

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: lbwc-routing.sh <set|check|activate|copy|resolve|validate|migrate|assert-transaction> <planning-dir> [arguments]' >&2
}

cleanup() {
  local owner_file
  [ "$LOCK_HELD" -eq 1 ] && [ -n "$LOCK_DIR" ] && [ -n "$LOCK_OWNER_RECORD" ] || return 0
  owner_file="$LOCK_DIR/owner"
  lock_is_owned || return 0
  rm -f -- "$owner_file" 2>/dev/null || return 0
  lock_directory_has_identity || return 0
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

require_tools() {
  local tool
  for tool in awk date jq mkdir mktemp mv ps shasum sleep; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
  done
  configure_platform_tools
}

system_name() {
  if [ -x /usr/bin/uname ]; then
    command /usr/bin/uname -s
  elif [ -x /bin/uname ]; then
    command /bin/uname -s
  else
    return 1
  fi
}

lock_backend_for_system() {
  case "$1" in
    Darwin) printf '%s\n' lockf ;;
    Linux) printf '%s\n' flock ;;
    *) return 1 ;;
  esac
}

first_executable() {
  local candidate
  for candidate in "$@"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

configure_platform_tools() {
  local platform
  platform=$(system_name) || fail 'could not identify the operating system'
  LOCK_BACKEND=$(lock_backend_for_system "$platform") \
    || fail "unsupported operating system for routing locks: $platform"
  ENV_TOOL=$(first_executable /usr/bin/env /bin/env) || fail 'a trusted system env is required'
  OD_TOOL=$(first_executable /usr/bin/od /bin/od) || fail 'a trusted system od is required'
  case "$LOCK_BACKEND" in
    lockf)
      LOCK_TOOL=$(first_executable /usr/bin/lockf) || fail '/usr/bin/lockf is required on macOS'
      STAT_TOOL=$(first_executable /usr/bin/stat) || fail '/usr/bin/stat is required on macOS'
      STAT_STYLE=bsd
      ;;
    flock)
      LOCK_TOOL=$(first_executable /usr/bin/flock /bin/flock) || fail 'flock is required on Linux'
      STAT_TOOL=$(first_executable /usr/bin/stat /bin/stat) || fail 'stat is required on Linux'
      STAT_STYLE=gnu
      ;;
  esac
}

invoke_lock_backend() {
  local backend="$1" tool="$2" fd="$3"
  case "$backend" in
    lockf) command "$tool" -s -t 0 "$fd" ;;
    flock) command "$tool" -n "$fd" ;;
    *) return 1 ;;
  esac
}

directory_identity() {
  local identity
  case "$STAT_STYLE" in
    bsd) identity=$(command "$STAT_TOOL" -f '%d:%i' -- "$1" 2>/dev/null) || return 1 ;;
    gnu) identity=$(command "$STAT_TOOL" -Lc '%d:%i' -- "$1" 2>/dev/null) || return 1 ;;
    *) return 1 ;;
  esac
  [[ "$identity" =~ ^[0-9]+:[0-9]+$ ]] || return 1
  printf '%s\n' "$identity"
}

file_inode() {
  local inode
  case "$STAT_STYLE" in
    bsd) inode=$(command "$STAT_TOOL" -f '%i' -- "$1" 2>/dev/null) || return 1 ;;
    gnu) inode=$(command "$STAT_TOOL" -Lc '%i' -- "$1" 2>/dev/null) || return 1 ;;
    *) return 1 ;;
  esac
  [[ "$inode" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$inode"
}

lock_directory_has_identity() {
  local current_identity
  [ -n "$LOCK_DIR_IDENTITY" ] && [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ] || return 1
  current_identity=$(directory_identity "$LOCK_DIR") || return 1
  [ "$current_identity" = "$LOCK_DIR_IDENTITY" ]
}

lock_is_owned() {
  local owner_file current
  lock_directory_has_identity || return 1
  owner_file="$LOCK_DIR/owner"
  [ -f "$owner_file" ] && [ ! -L "$owner_file" ] || return 1
  current=$(<"$owner_file")
  [ "$current" = "$LOCK_OWNER_RECORD" ]
}

resolve_planning_directory() {
  local input="$1" trimmed parent physical_parent
  case "/$input/" in
    */../*) fail "planning directory traversal is not allowed: $input" ;;
  esac
  trimmed="$input"
  while [ "$trimmed" != "/" ] && [ "${trimmed%/}" != "$trimmed" ]; do
    trimmed=${trimmed%/}
  done
  [ ! -L "$trimmed" ] || fail "planning directory boundary must not be a symbolic link: $input"
  [ "${trimmed##*/}" = '.lbwc-planning' ] || fail "planning directory must end with .lbwc-planning: $input"
  [ -d "$trimmed" ] || fail "planning directory does not exist: $input"
  case "$trimmed" in
    */*)
      parent=${trimmed%/*}
      [ -n "$parent" ] || parent=/
      ;;
    *) parent=. ;;
  esac
  physical_parent=$(cd -P -- "$parent" 2>/dev/null && pwd -P) || fail "could not resolve planning directory: $input"
  printf '%s/%s\n' "$physical_parent" '.lbwc-planning'
}

reclaim_stale_lock() {
  local lock_dir="$1" owner_file record pid created token now current
  owner_file="$lock_dir/owner"
  [ -d "$lock_dir" ] && [ ! -L "$lock_dir" ] || return 1
  [ -f "$owner_file" ] && [ ! -L "$owner_file" ] || return 1
  record=$(<"$owner_file")
  IFS=$'\t' read -r pid created token <<< "$record"
  [ "$record" = "$pid"$'\t'"$created"$'\t'"$token" ] || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$created" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$token" =~ ^[A-Za-z0-9._:-]+$ ]] || return 1
  now=$(date +%s) || return 1
  [ "$created" -le "$now" ] || return 1
  [ $((now - created)) -ge "$LOCK_STALE_AFTER_SECONDS" ] || return 1
  kill -0 "$pid" 2>/dev/null && return 1
  ps -p "$pid" -o pid= >/dev/null 2>&1 && return 1
  [ -f "$owner_file" ] && [ ! -L "$owner_file" ] || return 1
  current=$(<"$owner_file")
  [ "$current" = "$record" ] || return 1
  rm -f -- "$owner_file" 2>/dev/null || return 1
  rmdir "$lock_dir" 2>/dev/null || return 1
}

acquire_config_lock() {
  local planning_dir="$1" attempt wait_attempts created token guard_inode fd_inode guard_held=0
  local token_status token_detail token_diag_file shell_detail
  if [ "$TRANSACTION_ACTIVE" = 1 ]; then
    LOCK_DIR="${LBWC_CONFIG_TRANSACTION_LOCK_DIR:-}"
    LOCK_DIR_IDENTITY="${LBWC_CONFIG_TRANSACTION_LOCK_IDENTITY:-}"
    LOCK_GUARD="${LBWC_CONFIG_TRANSACTION_GUARD:-}"
    LOCK_FD="${LBWC_CONFIG_TRANSACTION_FD:-}"
    LOCK_OWNER_RECORD="${LBWC_CONFIG_TRANSACTION_OWNER:-}"
    [[ "$LOCK_FD" =~ ^[0-9]+$ ]] || fail 'inherited configuration transaction descriptor is invalid'
    [ "${LBWC_CONFIG_TRANSACTION_PLANNING_DIR:-}" = "$planning_dir" ] \
      || fail 'inherited configuration transaction targets another planning directory'
    [ "$LOCK_DIR" = "$planning_dir/.routing.lock" ] \
      || fail 'inherited configuration transaction lock path is invalid'
    [ "$LOCK_GUARD" = "$planning_dir/.routing.lock.guard" ] \
      || fail 'inherited configuration transaction guard path is invalid'
    [ -e "/dev/fd/$LOCK_FD" ] || fail 'inherited configuration transaction descriptor is unavailable'
    guard_inode=$(file_inode "$LOCK_GUARD") || fail 'could not identify inherited configuration transaction guard'
    fd_inode=$(file_inode "/dev/fd/$LOCK_FD") || fail 'could not identify inherited configuration transaction descriptor'
    [ "$guard_inode" = "$fd_inode" ] || fail 'inherited configuration transaction guard changed'
    lock_is_owned || fail 'inherited configuration transaction ownership is invalid'
    return 0
  fi
  LOCK_DIR="$planning_dir/.routing.lock"
  LOCK_GUARD="$planning_dir/.routing.lock.guard"
  wait_attempts="${LBWC_ROUTING_LOCK_WAIT_ATTEMPTS:-$LOCK_WAIT_ATTEMPTS_DEFAULT}"
  [[ "$wait_attempts" =~ ^[1-9][0-9]*$ ]] || fail 'routing lock wait attempts must be a positive integer'
  [ "$wait_attempts" -le 5000 ] || fail 'routing lock wait attempts exceed the safe bound'
  token_diag_file=$(mktemp "${TMPDIR:-/tmp}/lbwc-routing-lock-diag.XXXXXX") || fail 'could not create routing lock diagnostic file'
  {
    if token=$(command "$ENV_TOOL" LC_ALL=C "$OD_TOOL" -An -N 16 -tx1 /dev/urandom); then
      token_status=0
    else
      token_status=$?
    fi
  } 2>"$token_diag_file"
  shell_detail=$(<"$token_diag_file")
  rm -f -- "$token_diag_file" 2>/dev/null || true
  token_detail="${token//$'\n'/ }"
  shell_detail="${shell_detail//$'\n'/ }"
  [ -n "$token_detail" ] || token_detail='(no output captured)'
  [ -n "$shell_detail" ] || shell_detail='(no output captured)'
  [ "$token_status" -eq 0 ] \
    || fail "could not create secure routing lock owner token: $OD_TOOL exited $token_status (od stdout: $token_detail) (captured stderr: $shell_detail)"
  token=${token//[[:space:]]/}
  [[ "$token" =~ ^[0-9a-f]{32}$ ]] \
    || fail "routing lock owner token was malformed: $OD_TOOL produced unexpected output (od stdout: $token_detail) (captured stderr: $shell_detail)"
  [ ! -L "$LOCK_DIR" ] || fail "symbolic link paths are not allowed: $LOCK_DIR"
  [ ! -e "$LOCK_GUARD" ] || { [ -f "$LOCK_GUARD" ] && [ ! -L "$LOCK_GUARD" ]; } \
    || fail "routing lock guard must be a regular file: $LOCK_GUARD"
  exec 9>> "$LOCK_GUARD" || fail 'could not open routing lock guard'
  [ -f "$LOCK_GUARD" ] && [ ! -L "$LOCK_GUARD" ] || fail "routing lock guard must be a regular file: $LOCK_GUARD"
  guard_inode=$(file_inode "$LOCK_GUARD") || fail 'could not identify routing lock guard'
  fd_inode=$(file_inode "/dev/fd/$LOCK_FD") || fail 'could not identify routing lock guard descriptor'
  [ "$guard_inode" = "$fd_inode" ] || fail 'routing lock guard changed while opening'
  for ((attempt = 0; attempt < wait_attempts; attempt++)); do
    if invoke_lock_backend "$LOCK_BACKEND" "$LOCK_TOOL" "$LOCK_FD"; then
      guard_held=1
      break
    fi
    sleep 0.01
  done
  [ "$guard_held" -eq 1 ] || fail "could not acquire routing lock: $LOCK_DIR"
  for ((attempt = 0; attempt < wait_attempts; attempt++)); do
    [ ! -L "$LOCK_DIR" ] || fail "symbolic link paths are not allowed: $LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      LOCK_DIR_IDENTITY=$(directory_identity "$LOCK_DIR") || {
        rmdir "$LOCK_DIR" 2>/dev/null || true
        fail 'could not identify routing lock directory'
      }
      created=$(date +%s) || {
        lock_directory_has_identity && rmdir "$LOCK_DIR" 2>/dev/null || true
        fail 'could not record routing lock creation time'
      }
      LOCK_OWNER_RECORD="$$"$'\t'"$created"$'\t'"$token"
      if ! printf '%s\n' "$LOCK_OWNER_RECORD" > "$LOCK_DIR/owner"; then
        if lock_directory_has_identity; then
          rm -f -- "$LOCK_DIR/owner" 2>/dev/null || true
          lock_directory_has_identity && rmdir "$LOCK_DIR" 2>/dev/null || true
        fi
        LOCK_OWNER_RECORD=""
        fail 'could not record routing lock ownership'
      fi
      lock_is_owned || fail 'routing lock changed while recording ownership'
      LOCK_HELD=1
      return 0
    fi
    reclaim_stale_lock "$LOCK_DIR" && continue
    sleep 0.01
  done
  fail "could not acquire routing lock: $LOCK_DIR"
}

export_config_transaction() {
  local planning_dir="$1"
  lock_is_owned || fail 'configuration transaction ownership is invalid'
  export LBWC_CONFIG_TRANSACTION_ACTIVE=1
  export LBWC_CONFIG_TRANSACTION_PLANNING_DIR="$planning_dir"
  export LBWC_CONFIG_TRANSACTION_LOCK_DIR="$LOCK_DIR"
  export LBWC_CONFIG_TRANSACTION_LOCK_IDENTITY="$LOCK_DIR_IDENTITY"
  export LBWC_CONFIG_TRANSACTION_GUARD="$LOCK_GUARD"
  export LBWC_CONFIG_TRANSACTION_FD="$LOCK_FD"
  export LBWC_CONFIG_TRANSACTION_OWNER="$LOCK_OWNER_RECORD"
}

assert_no_pending_model_refresh() {
  local planning_dir="$1" pending="$1/.lbwc-model-refresh.pending"
  [ ! -e "$pending" ] && [ ! -L "$pending" ] \
    || fail "pending model refresh requires recovery: $pending"
}

run_config_transaction() {
  local planning_dir="$1"
  shift
  [ "$#" -gt 0 ] || fail 'configuration transaction requires a command'
  acquire_config_lock "$planning_dir"
  assert_no_pending_model_refresh "$planning_dir"
  export_config_transaction "$planning_dir"
  command "$@"
}

validate_profile() {
  case "$1" in
    quality|balanced|turbo) ;;
    *) fail "unknown routing profile: $1" ;;
  esac
}

validate_role() {
  local role="$1"
  jq -e --arg role "$role" 'has($role)' "$ROLE_DEFAULTS_PATH" >/dev/null 2>&1 \
    || fail "unknown routing role: $role"
}

validate_config_file() {
  local config="$1"
  [ ! -L "$config" ] || fail "symbolic link paths are not allowed: $config"
  [ -f "$config" ] || fail "configuration is not readable: $config"
  jq -e 'type == "object"' "$config" >/dev/null 2>&1 || fail "configuration is not valid JSON: $config"
}

validate_routing_shape() {
  local config="$1"
  jq -e '
    (.routing.profiles | keys | sort) == ["balanced", "quality", "turbo"]
    and (.routing.active_profile | IN("quality", "balanced", "turbo"))
    and (all(.routing.profiles[]; .roles | type == "object"))
    and (all(.routing.profiles[].roles[];
      type == "object"
      and (keys | sort) == ["model", "reasoning", "status"]
      and (.model | type == "string" and length > 0)
      and ((.reasoning | type == "string" and length > 0) or .reasoning == null)
      and (.status | IN("resolved", "unresolved"))
    ))
  ' "$config" >/dev/null 2>&1 || fail 'routing profiles must be exactly quality, balanced, and turbo with valid cells'
}

validate_current_catalog() {
  local catalog="$1" binary expected actual
  bash "$SCRIPT_DIR/claude-capabilities.sh" validate "$catalog" >/dev/null
  binary=$(jq -r '.source.binary_path' "$catalog")
  expected=$(jq -r '.source.sha256' "$catalog")
  [ -f "$binary" ] && [ -x "$binary" ] || fail "catalog Claude Code binary is unavailable: $binary"
  actual=$(shasum -a 256 "$binary" | awk '{print $1}') || fail 'could not fingerprint Claude Code executable'
  [ "$actual" = "$expected" ] || fail 'Claude Code binary fingerprint differs from the saved capability catalog'
}

validate_route_value() {
  local catalog="$1" selector="$2" reasoning_json="$3"
  jq -e --arg selector "$selector" '[.models[].selector] | index($selector) != null' "$catalog" >/dev/null \
    || fail "model selector is not present in the saved capability catalog: $selector"
  jq -e 'type == "string" or . == null' <<< "$reasoning_json" >/dev/null 2>&1 \
    || fail 'reasoning must be a detected string or null'
  if jq -e '. != null' <<< "$reasoning_json" >/dev/null; then
    jq -e --argjson reasoning "$reasoning_json" '.reasoning.accepted_values | index($reasoning) != null' "$catalog" >/dev/null \
      || fail "reasoning value is not present in the saved capability catalog: $(jq -r . <<< "$reasoning_json")"
    jq -e --arg selector "$selector" --argjson reasoning "$reasoning_json" '
      if .reasoning.scope == "global"
      then true
      else
        (.reasoning.model_associations[$selector] // null) as $allowed
        | $allowed == null or ($allowed | index($reasoning) != null)
      end
    ' "$catalog" >/dev/null || fail "reasoning value is not accepted for model selector: $selector"
  fi
}

validate_profile_routes() {
  local catalog="$1" config="$2" profile="$3" role model reasoning status
  while IFS=$'\t' read -r role model reasoning status; do
    [ -n "$role" ] || continue
    validate_role "$role"
    [ "$status" = "resolved" ] || fail "unresolved routing cell: $profile/$role"
    validate_route_value "$catalog" "$model" "$reasoning"
  done < <(jq -r --arg profile "$profile" '
    .routing.profiles[$profile].roles
    | to_entries[]
    | [.key, .value.model, (.value.reasoning | tojson), .value.status]
    | @tsv
  ' "$config")
}

validate_routing_config() {
  local planning_dir="$1" catalog config profile active
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  validate_current_catalog "$catalog"
  validate_config_file "$config"
  validate_routing_shape "$config"
  active=$(jq -r '.routing.active_profile // empty' "$config")
  validate_profile "$active"
  for profile in quality balanced turbo; do
    jq -e --arg profile "$profile" '.routing.profiles[$profile].roles | type == "object"' "$config" >/dev/null 2>&1 \
      || fail "routing profile roles must be an object: $profile"
    validate_profile_routes "$catalog" "$config" "$profile"
  done
  printf '%s\n' "$config"
}

atomic_write_config() {
  local planning_dir="$1" value="$2" temporary
  if [ "$LOCK_DIR" != "$planning_dir/.routing.lock" ] || [ ! -d "$LOCK_DIR" ] \
    || [ -z "$LOCK_OWNER_RECORD" ] || ! lock_is_owned; then
    fail 'routing configuration write requires the routing lock'
  fi
  temporary=$(mktemp "$planning_dir/.config.json.routing.XXXXXX") || fail 'could not create routing configuration temporary file'
  printf '%s\n' "$value" > "$temporary" || {
    rm -f "$temporary"
    fail 'could not write routing configuration temporary file'
  }
  validate_routing_shape "$temporary"
  lock_is_owned || {
    rm -f "$temporary"
    fail 'routing configuration write requires the routing lock'
  }
  mv -f "$temporary" "$planning_dir/config.json" || {
    rm -f "$temporary"
    fail 'could not atomically persist routing configuration'
  }
  printf '%s\n' "$planning_dir/config.json"
}

atomic_set_route() {
  local planning_dir="$1" profile="$2" role="$3" selector="$4" reasoning_json="$5"
  local catalog config updated
  [ -n "$role" ] || fail 'routing role must not be empty'
  validate_profile "$profile"
  validate_role "$role"
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  acquire_config_lock "$planning_dir"
  validate_config_file "$config"
  validate_routing_shape "$config"
  validate_current_catalog "$catalog"
  validate_route_value "$catalog" "$selector" "$reasoning_json"
  updated=$(jq -c \
    --arg profile "$profile" \
    --arg role "$role" \
    --arg model "$selector" \
    --argjson reasoning "$reasoning_json" '
      .routing.profiles[$profile].roles[$role] = {
        model: $model,
        reasoning: $reasoning,
        status: "resolved"
      }
    ' "$config") || fail 'could not update routing configuration'
  atomic_write_config "$planning_dir" "$updated"
}

copy_profile() {
  local planning_dir="$1" source="$2" destination="$3" catalog config updated
  validate_profile "$source"
  validate_profile "$destination"
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  acquire_config_lock "$planning_dir"
  validate_current_catalog "$catalog"
  validate_config_file "$config"
  validate_routing_shape "$config"
  validate_profile_routes "$catalog" "$config" "$source"
  updated=$(jq -c --arg source "$source" --arg destination "$destination" '
    .routing.profiles[$destination].roles = .routing.profiles[$source].roles
  ' "$config") || fail 'could not copy routing profile'
  atomic_write_config "$planning_dir" "$updated"
}

activate_profile() {
  local planning_dir="$1" profile="$2" catalog config updated profile_json
  validate_profile "$profile"
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  acquire_config_lock "$planning_dir"
  validate_current_catalog "$catalog"
  validate_config_file "$config"
  validate_routing_shape "$config"
  profile_json=$(jq -cn --arg profile "$profile" '$profile') || fail 'could not encode routing profile'
  bash "$SCRIPT_DIR/lbwc-config.sh" assert-execution-setting-writable \
    "$planning_dir" routing.active_profile "$profile_json"
  updated=$(jq -c --arg profile "$profile" '.routing.active_profile = $profile' "$config") \
    || fail 'could not activate routing profile'
  atomic_write_config "$planning_dir" "$updated"
}

resolve_route() {
  local planning_dir="$1" role="$2" requested_profile="${3:-}" catalog config profile cell model reasoning
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  validate_current_catalog "$catalog"
  validate_config_file "$config"
  validate_routing_shape "$config"
  validate_role "$role"
  if [ -n "$requested_profile" ]; then
    profile="$requested_profile"
  else
    profile=$(jq -r '.routing.active_profile // empty' "$config")
  fi
  validate_profile "$profile"
  cell=$(jq -c --arg profile "$profile" --arg role "$role" '.routing.profiles[$profile].roles[$role] // null' "$config")
  jq -e 'type == "object" and .status == "resolved" and (.model | type == "string") and has("reasoning")' <<< "$cell" >/dev/null \
    || fail "route is unresolved or absent for profile '$profile' and role '$role'"
  model=$(jq -r '.model' <<< "$cell")
  reasoning=$(jq -c '.reasoning' <<< "$cell")
  validate_route_value "$catalog" "$model" "$reasoning"
  jq -cS -n --arg model "$model" --arg profile "$profile" --argjson reasoning "$reasoning" --arg role "$role" \
    '{model:$model,profile:$profile,reasoning:$reasoning,role:$role}'
}

check_route_value() {
  local planning_dir="$1" selector="$2" reasoning_json="$3" catalog
  catalog="$planning_dir/claude-capabilities.json"
  validate_current_catalog "$catalog"
  validate_route_value "$catalog" "$selector" "$reasoning_json"
  jq -cS -n --arg model "$selector" --argjson reasoning "$reasoning_json" '{model:$model,reasoning:$reasoning}'
}

migrate_routes() {
  local planning_dir="$1" catalog config migrated role profile profile_json
  catalog="$planning_dir/claude-capabilities.json"
  config="$planning_dir/config.json"
  acquire_config_lock "$planning_dir"
  validate_current_catalog "$catalog"
  validate_config_file "$config"
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    validate_role "$role"
  done < <(jq -r '(.roles // {}) | if type == "object" then keys[] else empty end' "$config")
  profile=$(jq -r '(.routing.active_profile // .model_profile // "balanced") | if . == "budget" then "turbo" else . end' "$config") \
    || fail 'could not resolve migrated routing profile'
  validate_profile "$profile"
  profile_json=$(jq -cn --arg profile "$profile" '$profile') || fail 'could not encode routing profile'
  bash "$SCRIPT_DIR/lbwc-config.sh" assert-execution-setting-writable \
    "$planning_dir" routing.active_profile "$profile_json"
  migrated=$(jq -c --slurpfile catalog "$catalog" '
    def normalized_profile($value): if $value == "budget" then "turbo" else $value end;
    def normalized_cell($cell):
      ($cell.model // null) as $model
      | (if $cell | has("reasoning") then $cell.reasoning else ($cell.effort // null) end) as $reasoning
      | ($catalog[0]) as $capabilities
      | ($capabilities.models | map(.selector) | index($model) != null) as $known_model
      | ($reasoning == null or ($capabilities.reasoning.accepted_values | index($reasoning) != null)) as $known_reasoning
      | ($capabilities.reasoning.model_associations[$model] // null) as $association
      | ($reasoning == null
          or $capabilities.reasoning.scope == "global"
          or $association == null
          or ($association | index($reasoning) != null)) as $allowed_reasoning
      | {model: $model, reasoning: $reasoning, status: (if $known_model and $known_reasoning and $allowed_reasoning then "resolved" else "unresolved" end)};
    (.routing.profiles // {}) as $existing_profiles
    | (($existing_profiles.budget.roles // {}) * ($existing_profiles.turbo.roles // {})) as $turbo_roles
    | .routing.profiles = {
        quality: {roles: ($existing_profiles.quality.roles // {})},
        balanced: {roles: ($existing_profiles.balanced.roles // {})},
        turbo: {roles: $turbo_roles}
      }
    | .routing.active_profile = normalized_profile(.routing.active_profile // .model_profile // "balanced")
    | .routing.profiles |= with_entries(.value.roles |= with_entries(.value |= normalized_cell(.)))
    | .routing.active_profile as $active
    | ((.roles // {}) | with_entries(
        select(.value | has("model") or has("effort") or has("reasoning"))
        | .value = normalized_cell({
            model: .value.model,
            reasoning: (if .value | has("reasoning") then .value.reasoning else (.value.effort // null) end)
          })
      )) as $legacy_roles
    | .routing.profiles[$active].roles = ($legacy_roles * .routing.profiles[$active].roles)
    | if (.roles | type) == "object"
      then .roles |= with_entries(.value |= del(.model, .effort, .reasoning))
      else .
      end
    | del(.model_profile)
  ' "$config") || fail 'could not migrate routing configuration'
  atomic_write_config "$planning_dir" "$migrated"
}

main() {
  local command="${1:-}" planning_dir
  require_tools
  trap cleanup EXIT
  if [ "$command" = transaction ]; then
    [ "$#" -ge 4 ] || { usage; exit 1; }
    planning_dir=$(resolve_planning_directory "$2")
    shift 2
    run_config_transaction "$planning_dir" "$@"
    return
  fi
  case "$command" in
    set)
      [ "$#" -eq 6 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    check)
      [ "$#" -eq 4 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    activate)
      [ "$#" -eq 3 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    copy)
      [ "$#" -eq 4 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    resolve)
      [ "$#" -eq 3 ] || [ "$#" -eq 4 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    validate)
      [ "$#" -eq 2 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    migrate)
      [ "$#" -eq 2 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    assert-transaction)
      [ "$#" -eq 2 ] || { usage; exit 1; }
      planning_dir=$(resolve_planning_directory "$2")
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  if [ "$TRANSACTION_ACTIVE" = 1 ]; then
    acquire_config_lock "$planning_dir"
  else
    run_config_transaction "$planning_dir" bash "$0" "$@"
    return
  fi
  case "$command" in
    set) atomic_set_route "$planning_dir" "$3" "$4" "$5" "$6" ;;
    check) check_route_value "$planning_dir" "$3" "$4" ;;
    activate) activate_profile "$planning_dir" "$3" ;;
    copy) copy_profile "$planning_dir" "$3" "$4" ;;
    resolve) resolve_route "$planning_dir" "$3" "${4:-}" ;;
    validate) validate_routing_config "$planning_dir" ;;
    migrate) migrate_routes "$planning_dir" ;;
    assert-transaction) printf '%s\n' "$planning_dir" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
