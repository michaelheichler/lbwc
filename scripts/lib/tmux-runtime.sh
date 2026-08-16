#!/usr/bin/env bash

TMUX_RUNTIME_LOCKS=()

tmux_runtime_fail() {
  printf 'tmux runtime error: %s\n' "$1" >&2
  return 1
}

tmux_runtime_helper() {
  [ -n "${TMUX_RUNTIME_HELPER:-}" ] || { tmux_runtime_fail 'private filesystem helper is not configured'; return 1; }
  python3 "$TMUX_RUNTIME_HELPER" "$@"
}

tmux_runtime_valid_token() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

tmux_runtime_valid_target() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9:._-]*$ ]]
}

tmux_runtime_now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'
}

tmux_runtime_deadline_now_ms() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000'
}

tmux_runtime_iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

tmux_runtime_capability() {
  uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]'
}

tmux_runtime_capability_hash() {
  printf '%s' "$1" | shasum -a 256 | cut -d ' ' -f 1
}

tmux_runtime_private_directory() {
  tmux_runtime_helper ensure-directory --path "$1" >/dev/null || { tmux_runtime_fail "cannot create or inspect private directory: $1"; return 1; }
}

tmux_runtime_private_file() {
  tmux_runtime_helper check-file --path "$1" >/dev/null || { tmux_runtime_fail "private file is unavailable: $1"; return 1; }
}

tmux_runtime_existing_private_directory() {
  tmux_runtime_helper check-directory --path "$1" >/dev/null || { tmux_runtime_fail "private directory is unavailable: $1"; return 1; }
}

tmux_runtime_configure() {
  local requested_control_root="$1" control_root
  control_root=$(lbwc_control_root_validate "$requested_control_root" 0) || { tmux_runtime_fail "invalid control root: $requested_control_root"; return 1; }
  TMUX_RUNTIME_CONTROL_ROOT="$control_root"
  TMUX_RUNTIME_ROOT="$control_root/.runtime"
  TMUX_RUNTIME_BUS_ROOT="$TMUX_RUNTIME_ROOT/tmux-bus"
  TMUX_RUNTIME_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/tmux-private-fs.py"
  [ -x "$TMUX_RUNTIME_HELPER" ] || { tmux_runtime_fail "private filesystem helper is unavailable: $TMUX_RUNTIME_HELPER"; return 1; }
}

tmux_runtime_ensure() {
  tmux_runtime_private_directory "$TMUX_RUNTIME_ROOT" || return 1
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT" || return 1
}

tmux_runtime_credential_read() {
  local agent_id="$1"
  tmux_runtime_valid_token "$agent_id" || { tmux_runtime_fail "invalid credential identifier"; return 1; }
  tmux_runtime_helper read-json --root "$TMUX_RUNTIME_BUS_ROOT" --source "credentials/$agent_id.json"
}

tmux_runtime_credential_delete() {
  local agent_id="$1"
  tmux_runtime_valid_token "$agent_id" || { tmux_runtime_fail "invalid credential identifier"; return 1; }
  tmux_runtime_helper delete --root "$TMUX_RUNTIME_BUS_ROOT" --relative "credentials/$agent_id.json"
}

tmux_runtime_bus_parent_path() {
  printf '%s\n' "$TMUX_RUNTIME_ROOT"
}

tmux_runtime_deadline_after() {
  local timeout_ms="$1"
  printf '%s\n' "$(( $(tmux_runtime_deadline_now_ms) + timeout_ms ))"
}

tmux_runtime_deadline_remaining() {
  local deadline="$1"
  printf '%s\n' "$(( deadline - $(tmux_runtime_deadline_now_ms) ))"
}

tmux_runtime_deadline_expired() {
  local deadline="$1"
  [ "$(tmux_runtime_deadline_now_ms)" -ge "$deadline" ]
}

tmux_runtime_configure_existing() {
  tmux_runtime_configure "$1" || return 1
  tmux_runtime_private_directory "$TMUX_RUNTIME_ROOT"
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT"
}

tmux_runtime_path() {
  printf '%s/%s\n' "$TMUX_RUNTIME_BUS_ROOT" "$1"
}

tmux_runtime_atomic_json() {
  local destination="$1" document="$2" relative
  relative="${destination#"$TMUX_RUNTIME_BUS_ROOT"/}"
  [ "$relative" != "$destination" ] || { tmux_runtime_fail "destination is outside the private runtime: $destination"; return 1; }
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$document" || { tmux_runtime_fail "refusing to write a non-object JSON document"; return 1; }
  tmux_runtime_helper write-json --root "$TMUX_RUNTIME_BUS_ROOT" --relative "$relative" --document "$document" || { tmux_runtime_fail "cannot atomically write private file: $destination"; return 1; }
}

tmux_runtime_lock_release() {
  local name="$1" path index attempt compact=()
  path="$TMUX_RUNTIME_BUS_ROOT/locks/$name.lock"
  [ -d "$path" ] && [ ! -L "$path" ] || { tmux_runtime_fail "lock is malformed: $name"; return 1; }
  rm -f "$path/owner.json" || { tmux_runtime_fail "cannot clear lock owner: $name"; return 1; }
  for ((attempt = 0; attempt < 20; attempt++)); do
    rmdir "$path" 2>/dev/null && break
    [ -e "$path/owner.json" ] && { break; }
    sleep 0.005
  done
  if [ -d "$path" ]; then
    [ -e "$path/owner.json" ] || { tmux_runtime_fail "cannot release empty lock: $name"; return 1; }
  fi
  for ((index=0; index < ${#TMUX_RUNTIME_LOCKS[@]}; index++)); do
    [ "${TMUX_RUNTIME_LOCKS[$index]}" = "$name" ] && continue
    compact+=("${TMUX_RUNTIME_LOCKS[$index]}")
  done
  if [ "${#compact[@]}" -eq 0 ]; then
    TMUX_RUNTIME_LOCKS=()
  else
    TMUX_RUNTIME_LOCKS=("${compact[@]}")
  fi
}

tmux_runtime_cleanup_locks() {
  local index
  for ((index=${#TMUX_RUNTIME_LOCKS[@]} - 1; index >= 0; index--)); do
    tmux_runtime_lock_release "${TMUX_RUNTIME_LOCKS[$index]}" >/dev/null 2>&1 || true
  done
}

tmux_runtime_lock_recoverable() {
  local path="$1" owner_name="$2" now owner acquired lease pid
  tmux_runtime_helper check-directory --path "$path" >/dev/null 2>&1 || return 1
  tmux_runtime_helper check-file --path "$path/$owner_name" >/dev/null 2>&1 || return 1
  jq -e '.pid | type == "number" and floor == . and . > 0' "$path/$owner_name" >/dev/null 2>&1 || return 1
  jq -e '.acquired_at_ms | type == "number" and floor == .' "$path/$owner_name" >/dev/null 2>&1 || return 1
  jq -e '.lease_ms | type == "number" and floor == . and . > 0' "$path/$owner_name" >/dev/null 2>&1 || return 1
  owner=$(cat "$path/$owner_name" 2>/dev/null) || return 1
  acquired=$(jq -r '.acquired_at_ms' <<<"$owner")
  lease=$(jq -r '.lease_ms' <<<"$owner")
  pid=$(jq -r '.pid' <<<"$owner")
  now=$(tmux_runtime_deadline_now_ms)
  [ "$now" -ge $((acquired + lease)) ] || return 1
  kill -0 "$pid" >/dev/null 2>&1 && return 1
  rm -f "$path/$owner_name" && rmdir "$path"
}

tmux_runtime_lock_acquire() {
  local name="$1" timeout_ms="$2" lease_ms="$3" path deadline owner
  tmux_runtime_valid_token "$name" || { tmux_runtime_fail "invalid lock name: $name"; return 1; }
  [[ "$timeout_ms" =~ ^[1-9][0-9]*$ ]] || { tmux_runtime_fail "invalid lock timeout"; return 1; }
  [[ "$lease_ms" =~ ^[1-9][0-9]*$ ]] || { tmux_runtime_fail "invalid lock lease"; return 1; }
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/locks"
  path="$TMUX_RUNTIME_BUS_ROOT/locks/$name.lock"
  deadline=$(tmux_runtime_deadline_after "$timeout_ms")
  owner=$(jq -n --argjson pid "$$" --argjson acquired "$(tmux_runtime_deadline_now_ms)" --argjson lease "$lease_ms" '{pid: $pid, acquired_at_ms: $acquired, lease_ms: $lease}')
  while ! tmux_runtime_helper publish-directory --root "$TMUX_RUNTIME_BUS_ROOT" --relative "locks/$name.lock" --document "$owner" 2>/dev/null; do
    [ ! -L "$path" ] || { tmux_runtime_fail "lock path is unsafe: $name"; return 1; }
    if [ -f "$path/owner.json" ] && [ ! -L "$path/owner.json" ]; then
      tmux_runtime_lock_recoverable "$path" owner.json || true
    fi
    ! tmux_runtime_deadline_expired "$deadline" || { tmux_runtime_fail "timed out acquiring lock: $name"; return 1; }
    sleep 0.01
  done
  TMUX_RUNTIME_LOCKS+=("$name")
}

tmux_runtime_registry_valid() {
  local path="$1"
  tmux_runtime_private_file "$path" || return 1
  jq -e '
    def token: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");
    def target: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9:._-]*$");
    def pane: . == null or (type == "string" and test("^%[0-9]+$"));
    def state: IN("registered", "running", "idle", "failed", "shutdown");
    def capability: type == "string" and test("^[0-9a-f]{64}$");
    .schema_version == 2
    and (.main | (type == "object" and (.agent_id | token) and (.session_id | token) and .role == "orchestrator" and (.capability_hash | capability)))
    and (.tmux | type == "object"
      and ((.session == null) or (.session | token))
      and ((.orchestrator_target == null) or (.orchestrator_target | target))
      and ((.orchestrator_pane == null) or (.orchestrator_pane | type == "string" and test("^[0-9]+$")))
      and (.topology | IN("pending", "attached-existing-tmux", "detached-new-session"))
      and (.managed_session | type == "boolean")
      and ((.managed_session and (.ownership_token | token)) or ((.managed_session | not) and .ownership_token == null)))
    and (.agents | type == "array")
    and all(.agents[]; (type == "object" and (.agent_id | token) and (.parent_id | token) and (.contract_id | token) and (.generated_name | token) and (.tmux_target | target) and (.tmux_pane_id | pane) and (.capability_hash | capability) and ((.claude_session_id == null) or (.claude_session_id | token)) and (.state | state) and ((.heartbeat_at_ms == null) or (.heartbeat_at_ms | type == "number" and floor == . and . >= 0)) and ((.failure_reason == null) or (.failure_reason | type == "string")) and ((.watchdog_cleanup_pending == null) or (.watchdog_cleanup_pending | type == "boolean")) and ((.watchdog_failure_reported_at_ms == null) or (.watchdog_failure_reported_at_ms | type == "number" and floor == . and . >= 0))))
    and (([.agents[].agent_id] | length) == ([.agents[].agent_id] | unique | length))
    and (.routes | type == "object")
    and (([.main.agent_id] + [.agents[] | select(.state != "shutdown") | .agent_id] | sort) == (.routes | keys | sort))
    and all(.routes | to_entries[]; . as $route | ($route.key | token) and ($route.value | (type == "object" and .inbox == $route.key and ((.tmux_target == null) or (.tmux_target | target)))))
  ' "$path" >/dev/null 2>&1
}

tmux_runtime_registry_read() {
  local path="$TMUX_RUNTIME_BUS_ROOT/registry.json"
  tmux_runtime_registry_valid "$path" || { tmux_runtime_fail "registry is malformed"; return 1; }
  cat "$path"
}

tmux_runtime_registry_write() {
  local registry="$1" path="$TMUX_RUNTIME_BUS_ROOT/registry.json" temporary
  temporary=$(mktemp "$TMUX_RUNTIME_BUS_ROOT/.registry.XXXXXX") || { tmux_runtime_fail "cannot stage registry"; return 1; }
  chmod 600 "$temporary"
  printf '%s\n' "$registry" > "$temporary"
  tmux_runtime_registry_valid "$temporary" || { rm -f "$temporary"; tmux_runtime_fail "refusing malformed registry"; return 1; }
  rm -f "$temporary"
  tmux_runtime_atomic_json "$path" "$registry"
}

tmux_runtime_write_routing_table() {
  local registry="$1" routing
  routing=$(jq '
    {schema_version: 1, routes: ([{key: .main.agent_id, value: {agent_id: .main.agent_id, session_id: .main.session_id, contract_id: null, inbox: .main.agent_id, tmux_target: .routes[.main.agent_id].tmux_target}}] + [.agents[] | select(.state != "shutdown") | {key: .agent_id, value: {agent_id: .agent_id, session_id: .claude_session_id, contract_id: .contract_id, inbox: .agent_id, tmux_target: .tmux_target}}]) | from_entries}
  ' <<<"$registry") || { tmux_runtime_fail 'cannot build routing table'; return 1; }
  tmux_runtime_atomic_json "$TMUX_RUNTIME_BUS_ROOT/routing-table.json" "$routing"
}

tmux_runtime_write_registry_route_bundle() {
  local registry="$1"
  tmux_runtime_registry_write "$registry" || return 1
  tmux_runtime_write_routing_table "$registry"
}

tmux_runtime_inbox() {
  local agent_id="$1"
  tmux_runtime_valid_token "$agent_id" || { tmux_runtime_fail "invalid agent identifier"; return 1; }
  printf '%s/inboxes/%s\n' "$TMUX_RUNTIME_BUS_ROOT" "$agent_id"
}

tmux_runtime_initialize_inbox() {
  local agent_id="$1" inbox
  inbox=$(tmux_runtime_inbox "$agent_id")
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/inboxes"
  tmux_runtime_private_directory "$inbox"
  tmux_runtime_private_directory "$inbox/acked"
}

tmux_runtime_require_bus() {
  local registry agent_id paths=()
  paths=(
    "$TMUX_RUNTIME_BUS_ROOT/locks"
    "$TMUX_RUNTIME_BUS_ROOT/inboxes"
    "$TMUX_RUNTIME_BUS_ROOT/outbox"
    "$TMUX_RUNTIME_BUS_ROOT/outbox/main"
    "$TMUX_RUNTIME_BUS_ROOT/transactions"
    "$TMUX_RUNTIME_BUS_ROOT/claims"
    "$TMUX_RUNTIME_BUS_ROOT/credentials"
  )
  tmux_runtime_helper check-directories --paths "${paths[@]}" >/dev/null || { tmux_runtime_fail "private directory is unavailable"; return 1; }
  tmux_runtime_private_directory "$TMUX_RUNTIME_BUS_ROOT/heartbeats" || return 1
  registry=$(tmux_runtime_registry_read) || return 1
  paths=()
  while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    paths+=("$(tmux_runtime_inbox "$agent_id")")
    paths+=("$(tmux_runtime_inbox "$agent_id")/acked")
  done < <(jq -r '.routes | keys[]' <<<"$registry")
  if [ "${#paths[@]}" -gt 0 ]; then
    tmux_runtime_helper check-directories --paths "${paths[@]}" >/dev/null || { tmux_runtime_fail "private directory is unavailable"; return 1; }
  fi
}

tmux_runtime_principal_valid() {
  local registry="$1" agent_id="$2" session_id="$3" role="$4" capability="$5" expected_hash
  case "$role" in orchestrator|agent) ;; *) return 1 ;; esac
  expected_hash=$(tmux_runtime_capability_hash "$capability")
  if [ "$role" = 'orchestrator' ]; then
    jq -e --arg agent "$agent_id" --arg session "$session_id" --arg hash "$expected_hash" '.main.agent_id == $agent and .main.session_id == $session and .main.capability_hash == $hash' <<<"$registry" >/dev/null
    return
  fi
  jq -e --arg agent "$agent_id" --arg session "$session_id" --arg hash "$expected_hash" 'any(.agents[]; .agent_id == $agent and .claude_session_id == $session and .capability_hash == $hash and .state != "shutdown")' <<<"$registry" >/dev/null
}
