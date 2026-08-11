#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/lbwc-model"
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lbwc-model.XXXXXX")
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  mkdir -p "$PLANNING_DIR"

  CLAUDE_FIXTURE="$TEST_ROOT/claude-fixture"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  --version) printf "%s\\n" "fixture-version" ;;' \
    '  --help) printf "%s\\n" "  --effort <level> effort (depth-99, default)" ;;' \
    '  *) printf "%s\\n" "fixture" ;;' \
    'esac' \
    'exit 0' \
    '# models:[{id:"claude-quartz-route",family:"quartz",display_name:"Quartz Route"},{id:"claude-ember-path",family:"ember",display_name:"Ember Path"}]' \
    > "$CLAUDE_FIXTURE"
  chmod +x "$CLAUDE_FIXTURE"
  CLAUDE_SHA=$(shasum -a 256 "$CLAUDE_FIXTURE" | awk '{print $1}')

  jq '
    . + {
      schema_version: 1,
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {roles: {}},
          turbo: {roles: {}}
        }
      }
    }
  ' "$REPO_ROOT/config/settings.json" > "$PLANNING_DIR/config.json"

  jq -n \
    --arg binary "$CLAUDE_FIXTURE" \
    --arg sha "$CLAUDE_SHA" '
      {
        schema_version: 1,
        source: {
          binary_path: $binary,
          version: "fixture",
          sha256: $sha,
          detected_at: "2035-01-02T03:04:05Z"
        },
        models: [
          {selector: "quartz|route", label: "Quartz | Route\nLine\u001b]0;owned\u0007", description: "Arbitrary fixture"},
          {selector: "ember-path", label: null, description: null}
        ],
        reasoning: {
          scope: "global",
          accepted_values: ["depth-99", "default"],
          model_associations: {}
        }
      }
    ' > "$PLANNING_DIR/claude-capabilities.json"
}

config_sha() {
  shasum -a 256 "$PLANNING_DIR/config.json" | awk '{print $1}'
}

make_traced_cli() {
  local fixture_root="$TEST_ROOT/traced-plugin"
  mkdir -p "$fixture_root/scripts" "$fixture_root/templates/agent-roles"
  cp "$SCRIPT" "$fixture_root/scripts/lbwc-model"
  cp "$REPO_ROOT/templates/agent-roles/defaults.json" "$fixture_root/templates/agent-roles/defaults.json"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "capabilities:%s:%s\\n" "$1" "$2" >> "$LBWC_MODEL_TRACE"' \
    'exec "$REAL_CAPABILITIES" "$@"' > "$fixture_root/scripts/claude-capabilities.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "routing:%s:%s\\n" "$1" "$2" >> "$LBWC_MODEL_TRACE"' \
    'exec "$REAL_ROUTING" "$@"' > "$fixture_root/scripts/lbwc-routing.sh"
  chmod +x "$fixture_root/scripts/"*
  printf '%s\n' "$fixture_root/scripts/lbwc-model"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "catalog emits stable JSON from an arbitrary capability fixture" {
  expected=$(jq -cS . "$PLANNING_DIR/claude-capabilities.json")

  run bash "$SCRIPT" --json catalog "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "show JSON is stable and includes every role in all three profiles" {
  run bash "$SCRIPT" --json show "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  compact=$(jq -cS . <<< "$output")
  [ "$output" = "$compact" ]
  run jq -e \
    --slurpfile defaults "$REPO_ROOT/templates/agent-roles/defaults.json" '
      .schema_version == 1
      and .active_profile == "balanced"
      and .structural_default == null
      and (.models | map(.selector)) == ["quartz|route", "ember-path"]
      and .reasoning.accepted_values == ["depth-99", "default"]
      and ([.profiles | to_entries[] | .key] | sort) == ["balanced", "quality", "turbo"]
      and (all(.profiles[];
        (.roles | keys | sort) == ($defaults[0] | keys | map(select(. != "oracles" and . != "trios")) | sort)
        and all(.roles[]; . == null)
      ))
    ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "human show escapes table cells and distinguishes both defaults" {
  run bash "$SCRIPT" show "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Detected models"* ]]
  [[ "$output" == *'Quartz \| Route Line?]0;owned?'* ]]
  [[ "$output" != *$'\e'* ]]
  [[ "$output" != *$'\a'* ]]
  [[ "$output" == *"Detected reasoning"* ]]
  [[ "$output" == *"Claude Code default"* ]]
  [[ "$output" == *'| default | Detected value |'* ]]
  [[ "$output" == *"Routing profiles"* ]]
  while IFS= read -r role; do
    for profile in quality balanced turbo; do
      [[ "$output" == *"| $profile | $role |"* ]]
    done
  done < <(jq -r 'keys[] | select(. != "oracles" and . != "trios")' "$REPO_ROOT/templates/agent-roles/defaults.json")
}

@test "set and refresh reject an unknown saved role without changing either state file" {
  jq '
    .routing.profiles.quality.roles.bogus = {
      model: "ember-path",
      reasoning: null,
      status: "resolved"
    }
  ' "$PLANNING_DIR/config.json" > "$PLANNING_DIR/config.next"
  mv "$PLANNING_DIR/config.next" "$PLANNING_DIR/config.json"
  config_before=$(config_sha)
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')

  run bash "$SCRIPT" set "$PLANNING_DIR" balanced docs ember-path null
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown routing role: bogus"* ]]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]

  run env CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown routing role: bogus"* ]]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
}

@test "set preserves exact selectors and reasoning values" {
  run bash "$SCRIPT" --json set "$PLANNING_DIR" quality architect 'quartz|route' '"depth-99"'

  [ "$status" -eq 0 ]
  [ "$output" = '{"model":"quartz|route","operation":"set","profile":"quality","reasoning":"depth-99","role":"architect","status":"ok"}' ]
  jq -e '
    .routing.profiles.quality.roles.architect
      == {model:"quartz|route",reasoning:"depth-99",status:"resolved"}
  ' "$PLANNING_DIR/config.json" >/dev/null
}

@test "set keeps structural null separate from a detected default value" {
  run bash "$SCRIPT" set "$PLANNING_DIR" balanced docs ember-path null
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" set "$PLANNING_DIR" turbo docs ember-path '"default"'
  [ "$status" -eq 0 ]

  jq -e '
    .routing.profiles.balanced.roles.docs.reasoning == null
    and .routing.profiles.turbo.roles.docs.reasoning == "default"
  ' "$PLANNING_DIR/config.json" >/dev/null
}

@test "activate and copy use the routing writer and emit stable mutation JSON" {
  bash "$SCRIPT" set "$PLANNING_DIR" quality architect 'quartz|route' '"depth-99"' >/dev/null

  run bash "$SCRIPT" --json copy "$PLANNING_DIR" quality turbo
  [ "$status" -eq 0 ]
  [ "$output" = '{"destination_profile":"turbo","operation":"copy","source_profile":"quality","status":"ok"}' ]
  run bash "$SCRIPT" --json activate "$PLANNING_DIR" turbo
  [ "$status" -eq 0 ]
  [ "$output" = '{"active_profile":"turbo","operation":"activate","status":"ok"}' ]
  jq -e '
    .routing.active_profile == "turbo"
    and .routing.profiles.turbo.roles == .routing.profiles.quality.roles
  ' "$PLANNING_DIR/config.json" >/dev/null
}

@test "validate emits stable JSON only after trusted validation succeeds" {
  run bash "$SCRIPT" --json validate "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$output" = '{"operation":"validate","status":"ok"}' ]
}

@test "refresh invokes capability generation before route migration and validation" {
  traced_cli=$(make_traced_cli)
  trace="$TEST_ROOT/refresh-trace"

  run env \
    LBWC_MODEL_TRACE="$trace" \
    REAL_CAPABILITIES="$REPO_ROOT/scripts/claude-capabilities.sh" \
    REAL_ROUTING="$REPO_ROOT/scripts/lbwc-routing.sh" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$traced_cli" --json refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$trace")" = "routing:transaction:$PLANNING_DIR" ]
  [ "$(sed -n '2p' "$trace")" = "routing:assert-transaction:$PLANNING_DIR" ]
  [[ "$(sed -n '3p' "$trace")" == capabilities:refresh:*'/.lbwc-planning' ]]
  [[ "$(sed -n '4p' "$trace")" == routing:migrate:*'/.lbwc-planning' ]]
  [[ "$(sed -n '5p' "$trace")" == routing:validate:*'/.lbwc-planning' ]]
  [ "$(sed -n '6p' "$trace")" = "routing:validate:$(cd -P "$PLANNING_DIR" && pwd -P)" ]
  [ "$(wc -l < "$trace" | tr -d ' ')" -eq 6 ]
  [ "$output" = '{"operation":"refresh","status":"ok"}' ]
}

@test "refresh preserves a concurrent trusted configuration update" {
  local wrapper_dir="$TEST_ROOT/race-bin"
  local config_wrapper_dir="$TEST_ROOT/config-race-bin"
  local config_ready="$TEST_ROOT/config-setter-ready"
  local ready="$TEST_ROOT/refresh-read-ready"
  local release="$TEST_ROOT/refresh-read-release"
  local refresh_output="$TEST_ROOT/refresh-output"
  local config_output="$TEST_ROOT/config-output"
  local config_pid config_status=0 physical_config refresh_pid refresh_status=0 real_bash real_cp
  bash "$REPO_ROOT/scripts/lbwc-config.sh" init "$PLANNING_DIR" >/dev/null
  real_bash=$(command -v bash)
  real_cp=$(command -v cp)
  physical_config="$(cd -P "$PLANNING_DIR" && pwd -P)/.config.json"
  mkdir -p "$wrapper_dir" "$config_wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_path=${1:-}' \
    'destination=${2:-}' \
    '"$REAL_CP" "$@"' \
    'if [[ "$source_path" == */.lbwc-model-refresh.pending/config.after ]] &&' \
    '  [[ "$destination" == "$MODEL_RACE_CONFIG".model-refresh.* ]]; then' \
    '  : > "$MODEL_RACE_READY"' \
    '  while [ ! -e "$MODEL_RACE_RELEASE" ]; do sleep 0.01; done' \
    'fi' > "$wrapper_dir/cp"
  chmod +x "$wrapper_dir/cp"
  printf '%s\n' \
    "#!$real_bash" \
    'set -euo pipefail' \
    'if [ "${1:-}" = "$MODEL_RACE_ROUTING" ] && [ "${2:-}" = transaction ]; then' \
    '  : > "$MODEL_CONFIG_SETTER_READY"' \
    'fi' \
    'exec "$REAL_BASH" "$@"' > "$config_wrapper_dir/bash"
  chmod +x "$config_wrapper_dir/bash"

  env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    MODEL_RACE_CONFIG="$physical_config" \
    MODEL_RACE_READY="$ready" \
    MODEL_RACE_RELEASE="$release" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR" > "$refresh_output" 2>&1 &
  refresh_pid=$!
  for _ in {1..500}; do
    [ -e "$ready" ] && break
    sleep 0.01
  done
  [ -e "$ready" ] || {
    cat "$refresh_output" >&3
    return 1
  }

  env \
    PATH="$config_wrapper_dir:$PATH" \
    REAL_BASH="$real_bash" \
    MODEL_RACE_ROUTING="$REPO_ROOT/scripts/lbwc-routing.sh" \
    MODEL_CONFIG_SETTER_READY="$config_ready" \
    "$real_bash" "$REPO_ROOT/scripts/lbwc-config.sh" set "$PLANNING_DIR" effort '"turbo"' \
    > "$config_output" 2>&1 &
  config_pid=$!
  for _ in {1..500}; do
    [ -e "$config_ready" ] && break
    sleep 0.01
  done
  [ -e "$config_ready" ]
  : > "$release"
  wait "$refresh_pid" || refresh_status=$?
  wait "$config_pid" || config_status=$?

  [ "$refresh_status" -eq 0 ]
  [ "$config_status" -eq 0 ]
  jq -e '.effort == "turbo"' "$PLANNING_DIR/config.json" >/dev/null
}

@test "refresh restores both files when the second commit rename fails" {
  local catalog_before catalog_after config_before config_after fail_marker physical_config real_mv wrapper_dir
  wrapper_dir="$TEST_ROOT/commit-failure-bin"
  fail_marker="$TEST_ROOT/commit-mv-failed"
  physical_config="$(cd -P "$PLANNING_DIR" && pwd -P)/config.json"
  real_mv=$(command -v mv)
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'destination=${!#}' \
    'if [ "$destination" = "$MODEL_COMMIT_CONFIG" ] && [ ! -e "$MODEL_COMMIT_FAIL_MARKER" ]; then' \
    '  : > "$MODEL_COMMIT_FAIL_MARKER"' \
    '  exit 73' \
    'fi' \
    'exec "$REAL_MV" "$@"' > "$wrapper_dir/mv"
  chmod +x "$wrapper_dir/mv"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run env \
    PATH="$wrapper_dir:$PATH" \
    REAL_MV="$real_mv" \
    MODEL_COMMIT_CONFIG="$physical_config" \
    MODEL_COMMIT_FAIL_MARKER="$fail_marker" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  catalog_after=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_after=$(config_sha)
  [ "$catalog_before" = "$catalog_after" ]
  [ "$config_before" = "$config_after" ]
  [ ! -e "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
}

@test "refresh restores both files after a catchable interruption" {
  local catalog_before child_pid child_pid_path config_before physical_prefix ready real_cp release
  local refresh_pid refresh_status=0 wrapper_dir
  wrapper_dir="$TEST_ROOT/interrupt-bin"
  ready="$TEST_ROOT/interrupt-ready"
  release="$TEST_ROOT/interrupt-release"
  child_pid_path="$TEST_ROOT/interrupt-child-pid"
  physical_prefix="$(cd -P "$PLANNING_DIR" && pwd -P)/.config.json"
  real_cp=$(command -v cp)
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_path=${1:-}' \
    'destination=${2:-}' \
    '"$REAL_CP" "$@"' \
    'if [[ "$source_path" == */.lbwc-model-refresh.pending/config.after ]] &&' \
    '  [[ "$destination" == "$MODEL_INTERRUPT_PREFIX".model-refresh.* ]]; then' \
    '  printf '\''%s\n'\'' "$PPID" > "$MODEL_INTERRUPT_CHILD_PID"' \
    '  : > "$MODEL_INTERRUPT_READY"' \
    '  while [ ! -e "$MODEL_INTERRUPT_RELEASE" ]; do sleep 0.01; done' \
    'fi' > "$wrapper_dir/cp"
  chmod +x "$wrapper_dir/cp"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    MODEL_INTERRUPT_PREFIX="$physical_prefix" \
    MODEL_INTERRUPT_CHILD_PID="$child_pid_path" \
    MODEL_INTERRUPT_READY="$ready" \
    MODEL_INTERRUPT_RELEASE="$release" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR" >/dev/null 2>&1 &
  refresh_pid=$!
  for _ in {1..500}; do
    [ -e "$ready" ] && break
    sleep 0.01
  done
  [ -e "$ready" ]
  child_pid=$(<"$child_pid_path")
  kill -TERM "$child_pid"
  : > "$release"
  wait "$refresh_pid" || refresh_status=$?

  [ "$refresh_status" -ne 0 ]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
  [ ! -e "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
  [ ! -e "$PLANNING_DIR/.routing.lock" ]
}

@test "refresh rejects a swapped published journal without changing either state file" {
  local attacker catalog_before config_before external_catalog external_sha marker original_pending
  local pending physical_config real_cp real_mv wrapper_dir
  wrapper_dir="$TEST_ROOT/journal-directory-swap-bin"
  attacker="$TEST_ROOT/attacker-journal"
  external_catalog="$TEST_ROOT/external-catalog"
  marker="$TEST_ROOT/journal-directory-swapped"
  original_pending="$TEST_ROOT/original-journal"
  pending="$(cd -P "$PLANNING_DIR" && pwd -P)/.lbwc-model-refresh.pending"
  physical_config="$(cd -P "$PLANNING_DIR" && pwd -P)/.config.json"
  real_cp=$(command -v cp)
  real_mv=$(command -v mv)
  mkdir -p "$wrapper_dir" "$attacker"
  cp "$PLANNING_DIR/config.json" "$attacker/config.before"
  jq '.effort = "turbo"' "$PLANNING_DIR/config.json" > "$attacker/config.after"
  cp "$PLANNING_DIR/claude-capabilities.json" "$attacker/catalog.before"
  cp "$PLANNING_DIR/claude-capabilities.json" "$external_catalog"
  ln -s "$external_catalog" "$attacker/catalog.after"
  : > "$attacker/catalog.was-present"
  external_sha=$(shasum -a 256 "$external_catalog" | awk '{print $1}')
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_path=${1:-}' \
    'destination=${2:-}' \
    'if [[ "$source_path" == "$MODEL_SWAP_PENDING/config.after" ]] &&' \
    '  [[ "$destination" == "$MODEL_SWAP_CONFIG".model-refresh.* ]] &&' \
    '  [ ! -e "$MODEL_SWAP_MARKER" ]; then' \
    '  "$REAL_MV" "$MODEL_SWAP_PENDING" "$MODEL_SWAP_ORIGINAL"' \
    '  "$REAL_MV" "$MODEL_SWAP_ATTACKER" "$MODEL_SWAP_PENDING"' \
    '  : > "$MODEL_SWAP_MARKER"' \
    'fi' \
    'exec "$REAL_CP" "$@"' > "$wrapper_dir/cp"
  chmod +x "$wrapper_dir/cp"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    REAL_MV="$real_mv" \
    MODEL_SWAP_PENDING="$pending" \
    MODEL_SWAP_ORIGINAL="$original_pending" \
    MODEL_SWAP_ATTACKER="$attacker" \
    MODEL_SWAP_CONFIG="$physical_config" \
    MODEL_SWAP_MARKER="$marker" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ -e "$marker" ]
  [ "$status" -ne 0 ]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
  [ "$external_sha" = "$(shasum -a 256 "$external_catalog" | awk '{print $1}')" ]
  [ -e "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
}

@test "refresh rejects a symlink swapped onto the published journal boundary" {
  local attacker attacker_sha catalog_before config_before marker original_pending pending
  local physical_config real_cp real_ln real_mv wrapper_dir
  wrapper_dir="$TEST_ROOT/journal-symlink-swap-bin"
  attacker="$TEST_ROOT/external-journal"
  marker="$TEST_ROOT/journal-symlink-swapped"
  original_pending="$TEST_ROOT/original-symlink-journal"
  pending="$(cd -P "$PLANNING_DIR" && pwd -P)/.lbwc-model-refresh.pending"
  physical_config="$(cd -P "$PLANNING_DIR" && pwd -P)/.config.json"
  real_cp=$(command -v cp)
  real_ln=$(command -v ln)
  real_mv=$(command -v mv)
  mkdir -p "$wrapper_dir" "$attacker"
  cp "$PLANNING_DIR/config.json" "$attacker/config.before"
  jq '.effort = "turbo"' "$PLANNING_DIR/config.json" > "$attacker/config.after"
  cp "$PLANNING_DIR/claude-capabilities.json" "$attacker/catalog.before"
  cp "$PLANNING_DIR/claude-capabilities.json" "$attacker/catalog.after"
  : > "$attacker/catalog.was-present"
  attacker_sha=$(shasum -a 256 "$attacker/config.after" | awk '{print $1}')
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_path=${1:-}' \
    'destination=${2:-}' \
    'if [[ "$source_path" == "$MODEL_SWAP_PENDING/config.after" ]] &&' \
    '  [[ "$destination" == "$MODEL_SWAP_CONFIG".model-refresh.* ]] &&' \
    '  [ ! -e "$MODEL_SWAP_MARKER" ]; then' \
    '  "$REAL_MV" "$MODEL_SWAP_PENDING" "$MODEL_SWAP_ORIGINAL"' \
    '  "$REAL_LN" -s "$MODEL_SWAP_ATTACKER" "$MODEL_SWAP_PENDING"' \
    '  : > "$MODEL_SWAP_MARKER"' \
    'fi' \
    'exec "$REAL_CP" "$@"' > "$wrapper_dir/cp"
  chmod +x "$wrapper_dir/cp"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    REAL_LN="$real_ln" \
    REAL_MV="$real_mv" \
    MODEL_SWAP_PENDING="$pending" \
    MODEL_SWAP_ORIGINAL="$original_pending" \
    MODEL_SWAP_ATTACKER="$attacker" \
    MODEL_SWAP_CONFIG="$physical_config" \
    MODEL_SWAP_MARKER="$marker" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [ -e "$marker" ]
  [ -L "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
  [ "$attacker_sha" = "$(shasum -a 256 "$attacker/config.after" | awk '{print $1}')" ]
}

@test "refresh rejects a swapped after image without changing either state file" {
  local catalog_before config_before external_config external_sha marker pending real_cp real_mv wrapper_dir
  wrapper_dir="$TEST_ROOT/journal-after-swap-bin"
  external_config="$TEST_ROOT/external-config-after"
  marker="$TEST_ROOT/journal-after-swapped"
  pending="$(cd -P "$PLANNING_DIR" && pwd -P)/.lbwc-model-refresh.pending"
  real_cp=$(command -v cp)
  real_mv=$(command -v mv)
  mkdir -p "$wrapper_dir"
  jq '.effort = "turbo"' "$PLANNING_DIR/config.json" > "$external_config"
  external_sha=$(shasum -a 256 "$external_config" | awk '{print $1}')
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_path=${1:-}' \
    'if [ "$source_path" = "$MODEL_SWAP_AFTER" ] && [ ! -e "$MODEL_SWAP_MARKER" ]; then' \
    '  "$REAL_MV" "$source_path" "$source_path.original"' \
    '  "$REAL_CP" "$MODEL_SWAP_EXTERNAL" "$source_path"' \
    '  : > "$MODEL_SWAP_MARKER"' \
    'fi' \
    'exec "$REAL_CP" "$@"' > "$wrapper_dir/cp"
  chmod +x "$wrapper_dir/cp"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    REAL_MV="$real_mv" \
    MODEL_SWAP_AFTER="$pending/config.after" \
    MODEL_SWAP_EXTERNAL="$external_config" \
    MODEL_SWAP_MARKER="$marker" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [ -e "$marker" ]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
  [ "$external_sha" = "$(shasum -a 256 "$external_config" | awk '{print $1}')" ]
  [ -e "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
}

@test "refresh rejects a swapped before image during rollback without changing either state file" {
  local catalog_before config_before external_config external_sha marker pending physical_catalog real_cp real_mv
  local wrapper_dir
  wrapper_dir="$TEST_ROOT/journal-before-swap-bin"
  external_config="$TEST_ROOT/external-config-before"
  marker="$TEST_ROOT/journal-before-swapped"
  pending="$(cd -P "$PLANNING_DIR" && pwd -P)/.lbwc-model-refresh.pending"
  physical_catalog="$(cd -P "$PLANNING_DIR" && pwd -P)/claude-capabilities.json"
  real_cp=$(command -v cp)
  real_mv=$(command -v mv)
  mkdir -p "$wrapper_dir"
  jq '.effort = "turbo"' "$PLANNING_DIR/config.json" > "$external_config"
  external_sha=$(shasum -a 256 "$external_config" | awk '{print $1}')
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'destination=${!#}' \
    'if [ "$destination" = "$MODEL_SWAP_CATALOG" ] &&' \
    '  [ ! -e "$MODEL_SWAP_MARKER" ]; then' \
    '  "$REAL_MV" "$MODEL_SWAP_BEFORE" "$MODEL_SWAP_BEFORE.original"' \
    '  "$REAL_CP" "$MODEL_SWAP_EXTERNAL" "$MODEL_SWAP_BEFORE"' \
    '  : > "$MODEL_SWAP_MARKER"' \
    '  exit 73' \
    'fi' \
    'exec "$REAL_MV" "$@"' > "$wrapper_dir/mv"
  chmod +x "$wrapper_dir/mv"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run env \
    PATH="$wrapper_dir:$PATH" \
    REAL_CP="$real_cp" \
    REAL_MV="$real_mv" \
    MODEL_SWAP_BEFORE="$pending/config.before" \
    MODEL_SWAP_EXTERNAL="$external_config" \
    MODEL_SWAP_CATALOG="$physical_catalog" \
    MODEL_SWAP_MARKER="$marker" \
    CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [ -e "$marker" ]
  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
  [ "$external_sha" = "$(shasum -a 256 "$external_config" | awk '{print $1}')" ]
  [ -e "$PLANNING_DIR/.lbwc-model-refresh.pending" ]
}

@test "a surviving refresh marker blocks every model writer in a fresh process" {
  local catalog_before config_before
  mkdir "$PLANNING_DIR/.lbwc-model-refresh.pending"
  catalog_before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  config_before=$(config_sha)

  run bash "$SCRIPT" set "$PLANNING_DIR" quality docs ember-path null
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run bash "$SCRIPT" activate "$PLANNING_DIR" turbo
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run bash "$SCRIPT" copy "$PLANNING_DIR" quality turbo
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run env CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]

  [ "$config_before" = "$(config_sha)" ]
  [ "$catalog_before" = "$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')" ]
}

@test "a surviving refresh marker blocks every trusted state entry point" {
  mkdir "$PLANNING_DIR/.lbwc-model-refresh.pending"

  run bash "$SCRIPT" show "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run bash "$REPO_ROOT/scripts/lbwc-config.sh" set "$PLANNING_DIR" effort '"turbo"'
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run bash "$REPO_ROOT/scripts/lbwc-routing.sh" validate "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run env CLAUDE_CODE_EXECPATH="$CLAUDE_FIXTURE" \
    bash "$REPO_ROOT/scripts/claude-capabilities.sh" refresh "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
  run bash "$REPO_ROOT/scripts/claude-capabilities.sh" \
    validate "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *'pending model refresh requires recovery'* ]]
}

@test "bad options and a missing set route fail without changing configuration" {
  before=$(config_sha)

  run bash "$SCRIPT" --unknown show "$PLANNING_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
  run bash "$SCRIPT" set "$PLANNING_DIR" quality architect
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ "$before" = "$(config_sha)" ]
}

@test "stale catalogs fail before mutation" {
  before=$(config_sha)
  printf '%s\n' changed >> "$CLAUDE_FIXTURE"

  run bash "$SCRIPT" activate "$PLANNING_DIR" turbo

  [ "$status" -ne 0 ]
  [[ "$output" == *"fingerprint differs"* ]]
  [ "$before" = "$(config_sha)" ]
}

@test "invalid profiles and malformed reasoning JSON fail atomically" {
  before=$(config_sha)

  run bash "$SCRIPT" activate "$PLANNING_DIR" impossible
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown routing profile"* ]]
  run bash "$SCRIPT" set "$PLANNING_DIR" quality docs ember-path '"broken'
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ "$before" = "$(config_sha)" ]
}

@test "unknown selectors fail atomically" {
  before=$(config_sha)

  run bash "$SCRIPT" set "$PLANNING_DIR" quality docs absent-selector null

  [ "$status" -ne 0 ]
  [[ "$output" == *"not present in the saved capability catalog"* ]]
  [ "$before" = "$(config_sha)" ]
}

@test "the CLI reads no static model pricing profile or settings source" {
  run rg -n 'model-pricing\.json|model-profiles\.json|reasoning-profiles\.json|config/settings\.json' "$SCRIPT"

  [ "$status" -eq 1 ]
}
