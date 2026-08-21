#!/usr/bin/env bats

load test_helper

ROUTING="${LBWC_ROUTING_UNDER_TEST:-${SCRIPTS_DIR}/lbwc-routing.sh}"

setup() {
  local temporary_root="${TMPDIR:-/tmp}"
  TEST_TEMP_DIR=$(mktemp -d "${temporary_root%/}/lbwc-routing.XXXXXX")
  export TEST_TEMP_DIR
  export _ORIG_HOME="${HOME:-}"
  export _ORIG_LBWC_PLANNING_DIR="${LBWC_PLANNING_DIR:-}"
  export HOME="$TEST_TEMP_DIR"
  unset LBWC_PLANNING_DIR CLAUDE_SESSION_ID 2>/dev/null || true
  mkdir -p "$TEST_TEMP_DIR/.lbwc-planning"
  ROUTE_BINARY="$TEST_TEMP_DIR/claude-route-fixture"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "fixture"' > "$ROUTE_BINARY"
  chmod +x "$ROUTE_BINARY"
  ROUTE_SHA=$(shasum -a 256 "$ROUTE_BINARY" | awk '{print $1}')
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
  ' "$CONFIG_DIR/settings.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  jq -n \
    --arg binary "$ROUTE_BINARY" \
    --arg sha "$ROUTE_SHA" '
      {
        schema_version: 1,
        source: {
          binary_path: $binary,
          version: "fixture",
          sha256: $sha,
          detected_at: "2035-01-02T03:04:05Z"
        },
        models: [
          {selector: "nova-route", label: "Nova Route", description: "Fixture selector"},
          {selector: "ember-path", label: "Ember Path", description: "Second fixture selector"}
        ],
        reasoning: {
          scope: "global",
          accepted_values: ["deliberate", "swift", "default"],
          model_associations: {"nova-route": ["deliberate"]}
        }
      }
    ' > "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json"
}

teardown() {
  if [ -n "${LOCK_OWNER_PID:-}" ]; then
    [ -z "${LOCK_OWNER_RELEASE:-}" ] || : > "$LOCK_OWNER_RELEASE"
    kill -TERM "$LOCK_OWNER_PID" 2>/dev/null || true
    wait "$LOCK_OWNER_PID" 2>/dev/null || true
  fi
  [ -z "${VAR_TEST_DIR:-}" ] || rm -rf "$VAR_TEST_DIR"
  teardown_temp_dir
}

@test "set stores an exact catalog route" {
  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality architect nova-route '"deliberate"'

  [ "$status" -eq 0 ]
  jq -e '
    .routing.profiles.quality.roles.architect
    == {model: "nova-route", reasoning: "deliberate", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "set stores structural default reasoning as null" {
  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path null

  [ "$status" -eq 0 ]
  jq -e '
    .routing.profiles.balanced.roles.docs
    == {model: "ember-path", reasoning: null, status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "set rejects a selector missing from the catalog without changing config" {
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality architect missing-route '"deliberate"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"not present in the saved capability catalog"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "global reasoning accepts every detected value regardless of model associations" {
  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality architect nova-route '"swift"'

  [ "$status" -eq 0 ]
  jq -e '
    .routing.profiles.quality.roles.architect
    == {model: "nova-route", reasoning: "swift", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "set fails closed after the catalog binary changes" {
  printf '%s\n' 'changed' >> "$ROUTE_BINARY"

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" turbo docs ember-path null

  [ "$status" -ne 0 ]
  [[ "$output" == *"fingerprint differs"* ]]
}

@test "activate and copy persist only the three routing profiles" {
  bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality architect nova-route '"deliberate"' >/dev/null

  run bash "$ROUTING" copy "$TEST_TEMP_DIR/.lbwc-planning" quality turbo
  [ "$status" -eq 0 ]
  run bash "$ROUTING" activate "$TEST_TEMP_DIR/.lbwc-planning" turbo
  [ "$status" -eq 0 ]

  jq -e '
    .routing.active_profile == "turbo"
    and .routing.profiles.turbo.roles == .routing.profiles.quality.roles
    and (.routing.profiles | keys | sort) == ["balanced", "quality", "turbo"]
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "activate rejects profile changes while execution is active" {
  printf '%s\n' '{"status":"executing"}' > "$TEST_TEMP_DIR/.lbwc-planning/.execution-state.json"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" activate "$TEST_TEMP_DIR/.lbwc-planning" turbo

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "resolve emits the exact active route as stable JSON" {
  bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path null >/dev/null

  run bash "$ROUTING" resolve "$TEST_TEMP_DIR/.lbwc-planning" docs

  [ "$status" -eq 0 ]
  [ "$output" = '{"model":"ember-path","profile":"balanced","reasoning":null,"role":"docs"}' ]
}

@test "resolve rejects an absent route" {
  run bash "$ROUTING" resolve "$TEST_TEMP_DIR/.lbwc-planning" docs

  [ "$status" -ne 0 ]
  [[ "$output" == *"route is unresolved or absent"* ]]
}

@test "migrate maps budget routes to turbo and marks removed values unresolved" {
  jq '
    .model_profile = "budget"
    | .routing.active_profile = "budget"
    | .routing.profiles.budget = {
        roles: {
          docs: {model: "ember-path", reasoning: "swift"},
          architect: {model: "removed-route", reasoning: "deliberate"}
        }
      }
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"

  [ "$status" -eq 0 ]
  jq -e '
    .routing.active_profile == "turbo"
    and (.routing.profiles | keys | sort) == ["balanced", "quality", "turbo"]
    and .routing.profiles.turbo.roles.docs
      == {model: "ember-path", reasoning: "swift", status: "resolved"}
    and .routing.profiles.turbo.roles.architect
      == {model: "removed-route", reasoning: "deliberate", status: "unresolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "migrate rejects profile changes while execution is active" {
  jq '.routing.active_profile = "budget"' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  printf '%s\n' '{"status":"executing"}' > "$TEST_TEMP_DIR/.lbwc-planning/.execution-state.json"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"

  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "migrate preserves exact legacy role routes and remains idempotent" {
  jq '
    .routing.active_profile = "quality"
    | .roles = {
        docs: {model: "ember-path", effort: "swift", max_turns: 33},
        architect: {model: "removed-route", effort: "deliberate"}
      }
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -eq 0 ]
  first=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -eq 0 ]
  second=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  [ "$first" = "$second" ]
  jq -e '
    .routing.profiles.quality.roles.docs
      == {model: "ember-path", reasoning: "swift", status: "resolved"}
    and .routing.profiles.quality.roles.architect
      == {model: "removed-route", reasoning: "deliberate", status: "unresolved"}
    and .roles.docs == {max_turns: 33}
    and .roles.architect == {}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "migrate resolves arbitrary global reasoning without model association approval" {
  jq '
    .models += [{selector: "quartz-freeform", label: "Quartz Freeform", description: "Global reasoning fixture"}]
    | .reasoning.accepted_values += ["depth-99"]
    | .reasoning.model_associations["quartz-freeform"] = ["default"]
  ' "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" > "$TEST_TEMP_DIR/.lbwc-planning/catalog.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/catalog.next" "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json"
  jq '
    .routing.profiles.quality.roles.docs = {
      model: "quartz-freeform",
      reasoning: "depth-99",
      status: "resolved"
    }
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -eq 0 ]
  run bash "$ROUTING" resolve "$TEST_TEMP_DIR/.lbwc-planning" docs quality

  [ "$status" -eq 0 ]
  [ "$output" = '{"model":"quartz-freeform","profile":"quality","reasoning":"depth-99","role":"docs"}' ]
}

@test "migrate enforces model associations for explicit non-global reasoning" {
  jq '.reasoning.scope = "model_associated"' \
    "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" > "$TEST_TEMP_DIR/.lbwc-planning/catalog.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/catalog.next" "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json"
  jq '
    .routing.profiles.quality.roles.docs = {
      model: "nova-route",
      reasoning: "swift",
      status: "resolved"
    }
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"

  [ "$status" -eq 0 ]
  jq -e '
    .routing.profiles.quality.roles.docs
    == {model: "nova-route", reasoning: "swift", status: "unresolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "migrate rejects an unknown legacy root role without changing config" {
  jq '
    .roles.intruder = {model: "ember-path", effort: "swift"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" migrate "$TEST_TEMP_DIR/.lbwc-planning"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown routing role"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "validate rejects extra profiles and unresolved routes" {
  bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality docs ember-path '"swift"' >/dev/null
  run bash "$ROUTING" validate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -eq 0 ]

  jq '.routing.profiles.experimental = {roles: {}}' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  run bash "$ROUTING" validate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly quality, balanced, and turbo"* ]]

  jq 'del(.routing.profiles.experimental) | .routing.profiles.quality.roles.docs.status = "unresolved"' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  run bash "$ROUTING" validate "$TEST_TEMP_DIR/.lbwc-planning"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unresolved routing cell"* ]]
}

@test "copy rejects an invalid source route without changing config" {
  jq '.routing.profiles.quality.roles.docs = {model: "removed-route", reasoning: null, status: "resolved"}' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" copy "$TEST_TEMP_DIR/.lbwc-planning" quality turbo

  [ "$status" -ne 0 ]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "set rejects a symlinked configuration without changing its target" {
  external="$TEST_TEMP_DIR/external-config.json"
  printf '%s\n' '{"sentinel":true}' > "$external"
  external_before=$(shasum -a 256 "$external" | awk '{print $1}')
  rm "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  ln -s "$external" "$TEST_TEMP_DIR/.lbwc-planning/config.json"

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  external_after=$(shasum -a 256 "$external" | awk '{print $1}')
  [ "$external_before" = "$external_after" ]
  [ -L "$TEST_TEMP_DIR/.lbwc-planning/config.json" ]
}

@test "set rejects an unknown role without changing config" {
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality unknown-role ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown routing role"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "set rejects a malformed profile table without changing config" {
  jq '.routing.profiles.experimental = {roles: {}}' \
    "$TEST_TEMP_DIR/.lbwc-planning/config.json" > "$TEST_TEMP_DIR/.lbwc-planning/config.next"
  mv "$TEST_TEMP_DIR/.lbwc-planning/config.next" "$TEST_TEMP_DIR/.lbwc-planning/config.json"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" quality docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly quality, balanced, and turbo"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "every command rejects a directory outside the .lbwc-planning boundary" {
  local other="$TEST_TEMP_DIR/not-planning"
  mkdir -p "$other"
  cp "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$other/config.json"
  cp "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" "$other/claude-capabilities.json"

  run bash "$ROUTING" set "$other" quality docs ember-path '"swift"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" copy "$other" quality turbo
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" activate "$other" turbo
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" migrate "$other"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" resolve "$other" docs
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" check "$other" ember-path '"swift"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
  run bash "$ROUTING" validate "$other"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end with .lbwc-planning"* ]]
}

@test "planning boundary rejects traversal and a symlink without changing its target" {
  local target="$TEST_TEMP_DIR/real/.lbwc-planning"
  local linked="$TEST_TEMP_DIR/linked/.lbwc-planning"
  mkdir -p "$target" "$(dirname "$linked")"
  cp "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$target/config.json"
  cp "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" "$target/claude-capabilities.json"
  ln -s "$target" "$linked"
  before=$(shasum -a 256 "$target/config.json" | awk '{print $1}')

  run bash "$ROUTING" validate "$TEST_TEMP_DIR/.lbwc-planning/../.lbwc-planning"
  [ "$status" -ne 0 ]
  [[ "$output" == *"traversal is not allowed"* ]]
  run bash "$ROUTING" set "$linked" quality docs ember-path '"swift"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be a symbolic link"* ]]
  after=$(shasum -a 256 "$target/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "planning boundary accepts the macOS var ancestor alias" {
  [ -L /var ] || skip "macOS /var alias is unavailable"
  VAR_TEST_DIR=$(mktemp -d /private/var/tmp/lbwc-routing-alias.XXXXXX)
  local aliased="/var/tmp/${VAR_TEST_DIR##*/}/.lbwc-planning"
  mkdir -p "$VAR_TEST_DIR/.lbwc-planning"
  cp "$TEST_TEMP_DIR/.lbwc-planning/config.json" "$VAR_TEST_DIR/.lbwc-planning/config.json"
  cp "$TEST_TEMP_DIR/.lbwc-planning/claude-capabilities.json" "$VAR_TEST_DIR/.lbwc-planning/claude-capabilities.json"

  run bash "$ROUTING" validate "$aliased"

  [ "$status" -eq 0 ]
}

@test "concurrent route writers preserve both updates" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local real_jq ready release first_rc second_rc
  real_jq=$(command -v jq)
  ready="$TEST_TEMP_DIR/first-transform-ready"
  release="$TEST_TEMP_DIR/release-first-transform"
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$*" == *'"'"'.routing.profiles[$profile].roles[$role]'"'"'* ]] && [[ " $* " == *'"'"' --arg role docs '"'"'* ]]; then' \
    '  output=$("$REAL_JQ" "$@")' \
    '  : > "$ROUTING_FIRST_READY"' \
    '  while [ ! -e "$ROUTING_FIRST_RELEASE" ]; do sleep 0.01; done' \
    '  printf '"'"'%s\n'"'"' "$output"' \
    'else' \
    '  exec "$REAL_JQ" "$@"' \
    'fi' > "$wrapper_dir/jq"
  chmod +x "$wrapper_dir/jq"

  env PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" ROUTING_FIRST_READY="$ready" ROUTING_FIRST_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' \
    >/dev/null 2>&1 &
  first_pid=$!
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]

  env PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" ROUTING_FIRST_READY="$ready" ROUTING_FIRST_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced architect nova-route '"deliberate"' \
    >/dev/null 2>&1 &
  second_pid=$!
  sleep 0.2
  : > "$release"
  wait "$first_pid"; first_rc=$?
  wait "$second_pid"; second_rc=$?

  [ "$first_rc" -eq 0 ]
  [ "$second_rc" -eq 0 ]
  jq -e '
    .routing.profiles.balanced.roles.docs
      == {model: "ember-path", reasoning: "swift", status: "resolved"}
    and .routing.profiles.balanced.roles.architect
      == {model: "nova-route", reasoning: "deliberate", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "a forged inherited transaction fails closed without changing configuration" {
  local before after planning
  planning=$(cd -P "$TEST_TEMP_DIR/.lbwc-planning" && pwd -P)
  before=$(shasum -a 256 "$planning/config.json" | awk '{print $1}')

  run env \
    LBWC_CONFIG_TRANSACTION_ACTIVE=1 \
    LBWC_CONFIG_TRANSACTION_PLANNING_DIR="$planning" \
    LBWC_CONFIG_TRANSACTION_LOCK_DIR="$planning/.routing.lock" \
    LBWC_CONFIG_TRANSACTION_LOCK_IDENTITY='1:1' \
    LBWC_CONFIG_TRANSACTION_GUARD="$planning/.routing.lock.guard" \
    LBWC_CONFIG_TRANSACTION_FD=999 \
    LBWC_CONFIG_TRANSACTION_OWNER='forged' \
    bash "$ROUTING" set "$planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *'inherited configuration transaction descriptor is unavailable'* ]]
  after=$(shasum -a 256 "$planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "a failed transaction command releases its owned lock" {
  local planning="$TEST_TEMP_DIR/.lbwc-planning"

  run bash "$ROUTING" transaction "$planning" bash -c 'exit 47'

  [ "$status" -eq 47 ]
  [ ! -e "$planning/.routing.lock" ]
}
