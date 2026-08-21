#!/usr/bin/env bats

load test_helper

ROUTING="${LBWC_ROUTING_UNDER_TEST:-${SCRIPTS_DIR}/lbwc-routing.sh}"

system_platform() {
  if [ -x /usr/bin/uname ]; then
    /usr/bin/uname -s
  else
    /bin/uname -s
  fi
}

create_routing_failure_fixture() {
  local mode="$1"
  local fixture_root="$TEST_TEMP_DIR/routing-$mode"
  local fixture="$fixture_root/scripts/lbwc-routing.sh"
  local denied="$fixture_root/unavailable"
  mkdir -p "$fixture_root/scripts" "$fixture_root/templates/agent-roles"
  awk -v mode="$mode" -v denied="$denied" '
    mode == "entropy" { gsub("/dev/urandom", denied) }
    mode == "unsupported" && /^  platform=\$\(system_name\)/ {
      print "  platform=UnsupportedFixture"
      next
    }
    mode == "missing" {
      gsub("/usr/bin/lockf", denied)
      gsub("/usr/bin/flock /bin/flock", denied " " denied)
    }
    { print }
  ' "$ROUTING" > "$fixture"
  cp "$PROJECT_ROOT/templates/agent-roles/defaults.json" "$fixture_root/templates/agent-roles/defaults.json"
  chmod +x "$fixture"
  printf '%s\n' "$fixture"
}

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

@test "Linux and macOS select descriptor lock backends with the correct arguments" {
  local fake_tool="$TEST_TEMP_DIR/fake-lock-tool"
  printf '%s\n' '#!/usr/bin/env bash' 'printf '"'"'%s\n'"'"' "$*"' > "$fake_tool"
  chmod +x "$fake_tool"

  run bash -c 'source "$1"; lock_backend_for_system Darwin' _ "$ROUTING"
  [ "$status" -eq 0 ]
  [ "$output" = lockf ]
  run bash -c 'source "$1"; lock_backend_for_system Linux' _ "$ROUTING"
  [ "$status" -eq 0 ]
  [ "$output" = flock ]
  run bash -c 'source "$1"; invoke_lock_backend lockf "$2" 9' _ "$ROUTING" "$fake_tool"
  [ "$status" -eq 0 ]
  [ "$output" = '-s -t 0 9' ]
  run bash -c 'source "$1"; invoke_lock_backend flock "$2" 9' _ "$ROUTING" "$fake_tool"
  [ "$status" -eq 0 ]
  [ "$output" = '-n 9' ]
  run bash -c 'source "$1"; lock_backend_for_system Windows' _ "$ROUTING"
  [ "$status" -ne 0 ]
}

@test "the real platform descriptor backend holds the guard for the owning shell lifetime" {
  local platform guard ready backend expected_backend
  platform=$(system_platform)
  case "$platform" in
    Darwin) expected_backend=/usr/bin/lockf ;;
    Linux)
      if [ -x /usr/bin/flock ]; then
        expected_backend=/usr/bin/flock
      else
        expected_backend=/bin/flock
      fi
      ;;
    *) skip "descriptor lock runtime is unsupported on $platform" ;;
  esac
  [ -x "$expected_backend" ]

  guard="$TEST_TEMP_DIR/platform.guard"
  ready="$TEST_TEMP_DIR/platform-owner-ready"
  backend="$TEST_TEMP_DIR/platform-backend"
  LOCK_OWNER_RELEASE="$TEST_TEMP_DIR/platform-owner-release"
  export LOCK_OWNER_RELEASE

  bash -c '
    set -euo pipefail
    source "$1"
    configure_platform_tools
    exec {LOCK_FD}>> "$2"
    invoke_lock_backend "$LOCK_BACKEND" "$LOCK_TOOL" "$LOCK_FD"
    printf "%s\n" "$LOCK_TOOL" > "$3"
    : > "$4"
    while [ ! -e "$5" ]; do sleep 0.01; done
  ' _ "$ROUTING" "$guard" "$backend" "$ready" "$LOCK_OWNER_RELEASE" &
  LOCK_OWNER_PID=$!
  export LOCK_OWNER_PID
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done

  [ -e "$ready" ]
  [ "$(<"$backend")" = "$expected_backend" ]
  run bash -c '
    set -euo pipefail
    source "$1"
    configure_platform_tools
    exec {LOCK_FD}>> "$2"
    invoke_lock_backend "$LOCK_BACKEND" "$LOCK_TOOL" "$LOCK_FD"
  ' _ "$ROUTING" "$guard"
  [ "$status" -ne 0 ]

  : > "$LOCK_OWNER_RELEASE"
  wait "$LOCK_OWNER_PID"
  unset LOCK_OWNER_PID
  run bash -c '
    set -euo pipefail
    source "$1"
    configure_platform_tools
    exec {LOCK_FD}>> "$2"
    invoke_lock_backend "$LOCK_BACKEND" "$LOCK_TOOL" "$LOCK_FD"
  ' _ "$ROUTING" "$guard"
  [ "$status" -eq 0 ]
}

@test "lock owner records use a 128-bit hexadecimal token" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local real_jq ready release lock owner_record owner_pid created token
  real_jq=$(command -v jq)
  ready="$TEST_TEMP_DIR/token-transform-ready"
  release="$TEST_TEMP_DIR/release-token-transform"
  lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$*" == *'"'"'.routing.profiles[$profile].roles[$role]'"'"'* ]]; then' \
    '  output=$("$REAL_JQ" "$@")' \
    '  : > "$ROUTING_TOKEN_READY"' \
    '  while [ ! -e "$ROUTING_TOKEN_RELEASE" ]; do sleep 0.01; done' \
    '  printf '"'"'%s\n'"'"' "$output"' \
    'else' \
    '  exec "$REAL_JQ" "$@"' \
    'fi' > "$wrapper_dir/jq"
  chmod +x "$wrapper_dir/jq"

  env PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" ROUTING_TOKEN_READY="$ready" ROUTING_TOKEN_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' \
    >/dev/null 2>&1 &
  writer_pid=$!
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  owner_record=$(<"$lock/owner")
  IFS=$'\t' read -r owner_pid created token <<< "$owner_record"
  : > "$release"
  wait "$writer_pid"

  [ "$owner_pid" = "$writer_pid" ]
  [[ "$created" =~ ^[1-9][0-9]*$ ]]
  [[ "$token" =~ ^[0-9a-f]{32}$ ]]
}

@test "cleanup rejects a recreated lock with a forged predictable owner record" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local real_jq ready release lock bash_env original created forged before after writer_rc
  real_jq=$(command -v jq)
  ready="$TEST_TEMP_DIR/forgery-transform-ready"
  release="$TEST_TEMP_DIR/release-forgery-transform"
  lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  bash_env="$TEST_TEMP_DIR/bash-env"
  printf '%s\n' 'unset RANDOM' 'RANDOM=7' > "$bash_env"
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$*" == *'"'"'.routing.profiles[$profile].roles[$role]'"'"'* ]]; then' \
    '  output=$("$REAL_JQ" "$@")' \
    '  : > "$ROUTING_FORGERY_READY"' \
    '  while [ ! -e "$ROUTING_FORGERY_RELEASE" ]; do sleep 0.01; done' \
    '  printf '"'"'%s\n'"'"' "$output"' \
    'else' \
    '  exec "$REAL_JQ" "$@"' \
    'fi' > "$wrapper_dir/jq"
  chmod +x "$wrapper_dir/jq"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  env BASH_ENV="$bash_env" PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" \
    ROUTING_FORGERY_READY="$ready" ROUTING_FORGERY_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' \
    >/dev/null 2>&1 &
  writer_pid=$!
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  original=$(<"$lock/owner")
  IFS=$'\t' read -r _ created _ <<< "$original"
  forged="$writer_pid"$'\t'"$created"$'\t'"$writer_pid-$created-7"
  rm "$lock/owner"
  rmdir "$lock"
  mkdir "$lock"
  printf '%s\n' "$forged" > "$lock/owner"

  : > "$release"
  wait "$writer_pid" || writer_rc=$?

  [ "${writer_rc:-0}" -ne 0 ]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  [ -d "$lock" ]
  [ "$(<"$lock/owner")" = "$forged" ]
}

@test "a genuine owner record replay cannot persist or clean up a recreated lock" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local real_jq ready release lock original before after writer_rc
  real_jq=$(command -v jq)
  ready="$TEST_TEMP_DIR/replay-transform-ready"
  release="$TEST_TEMP_DIR/release-replay-transform"
  lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$*" == *'"'"'.routing.profiles[$profile].roles[$role]'"'"'* ]]; then' \
    '  output=$("$REAL_JQ" "$@")' \
    '  : > "$ROUTING_REPLAY_READY"' \
    '  while [ ! -e "$ROUTING_REPLAY_RELEASE" ]; do sleep 0.01; done' \
    '  printf '"'"'%s\n'"'"' "$output"' \
    'else' \
    '  exec "$REAL_JQ" "$@"' \
    'fi' > "$wrapper_dir/jq"
  chmod +x "$wrapper_dir/jq"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  env PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" \
    ROUTING_REPLAY_READY="$ready" ROUTING_REPLAY_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' \
    >/dev/null 2>&1 &
  writer_pid=$!
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  original=$(<"$lock/owner")
  rm "$lock/owner"
  rmdir "$lock"
  mkdir "$TEST_TEMP_DIR/replay-inode-hold"
  mkdir "$lock"
  printf '%s\n' "$original" > "$lock/owner"

  : > "$release"
  wait "$writer_pid" || writer_rc=$?

  [ "${writer_rc:-0}" -ne 0 ]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  [ -d "$lock" ]
  [ "$(<"$lock/owner")" = "$original" ]
}

@test "mutations ignore short failing and valid-length od programs on PATH" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local operation behavior marker
  local -a args
  mkdir -p "$wrapper_dir"

  for operation in set copy activate migrate; do
    case "$operation" in
      set) args=(set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"') ;;
      copy) args=(copy "$TEST_TEMP_DIR/.lbwc-planning" balanced turbo) ;;
      activate) args=(activate "$TEST_TEMP_DIR/.lbwc-planning" turbo) ;;
      migrate) args=(migrate "$TEST_TEMP_DIR/.lbwc-planning") ;;
    esac
    for behavior in short failing valid; do
      marker="$TEST_TEMP_DIR/od-$operation-$behavior-called"
      printf '%s\n' \
        '#!/usr/bin/env bash' \
        ': > "$ROUTING_OD_CALLED"' \
        'case "$ROUTING_OD_BEHAVIOR" in' \
        '  short) printf '"'"'%s\n'"'"' '"'"'00112233445566778899aabbccddee'"'"' ;;' \
        '  failing) exit 1 ;;' \
        '  valid) printf '"'"'%s\n'"'"' '"'"'00112233445566778899aabbccddeeff'"'"' ;;' \
        'esac' > "$wrapper_dir/od"
      chmod +x "$wrapper_dir/od"

      run env PATH="$wrapper_dir:$PATH" ROUTING_OD_CALLED="$marker" ROUTING_OD_BEHAVIOR="$behavior" \
        bash "$ROUTING" "${args[@]}"

      [ "$status" -eq 0 ]
      [ ! -e "$marker" ]
      [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock" ]
    done
  done
}

@test "entropy denial precedes every routing mutation on Linux and macOS" {
  local operation before after fixture
  local -a args
  fixture=$(create_routing_failure_fixture entropy)

  for operation in set copy activate migrate; do
    case "$operation" in
      set) args=(set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"') ;;
      copy) args=(copy "$TEST_TEMP_DIR/.lbwc-planning" balanced turbo) ;;
      activate) args=(activate "$TEST_TEMP_DIR/.lbwc-planning" turbo) ;;
      migrate) args=(migrate "$TEST_TEMP_DIR/.lbwc-planning") ;;
    esac
    before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

    run bash "$fixture" "${args[@]}"

    [ "$status" -ne 0 ]
    [[ "$output" == *"could not create secure routing lock owner token: "*"exited 1"* ]]
    [[ "$output" == *"No such file or directory"* ]]
    after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
    [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock" ]
    [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock.guard" ]
  done
}

@test "a silently failing od still names the failure with no output captured" {
  local wrapper_dir="$TEST_TEMP_DIR/silent-od-bin"
  local fixture_root="$TEST_TEMP_DIR/routing-silent"
  local fixture="$fixture_root/scripts/lbwc-routing.sh"
  local before after
  mkdir -p "$wrapper_dir" "$fixture_root/scripts" "$fixture_root/templates/agent-roles"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$wrapper_dir/od"
  chmod +x "$wrapper_dir/od"
  awk -v od_path="$wrapper_dir/od" '
    /^  OD_TOOL=\$\(first_executable \/usr\/bin\/od \/bin\/od\)/ {
      print "  OD_TOOL=$(first_executable \"" od_path "\")"
      next
    }
    { print }
  ' "$ROUTING" > "$fixture"
  cp "$PROJECT_ROOT/templates/agent-roles/defaults.json" "$fixture_root/templates/agent-roles/defaults.json"
  chmod +x "$fixture"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run bash "$fixture" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not create secure routing lock owner token: "*"exited 1"* ]]
  [[ "$output" == *"(no output captured)"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock" ]
  [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock.guard" ]
}

@test "od stdout and captured stderr land in their own labelled diagnostic field" {
  local wrapper_dir="$TEST_TEMP_DIR/labelled-od-bin"
  local fixture_root="$TEST_TEMP_DIR/routing-labelled"
  local fixture="$fixture_root/scripts/lbwc-routing.sh"
  mkdir -p "$wrapper_dir" "$fixture_root/scripts" "$fixture_root/templates/agent-roles"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\\n' ZZSTDOUTZZ" \
    "printf '%s\\n' ZZSTDERRZZ >&2" \
    'exit 1' > "$wrapper_dir/od"
  chmod +x "$wrapper_dir/od"
  awk -v od_path="$wrapper_dir/od" '
    /^  OD_TOOL=\$\(first_executable \/usr\/bin\/od \/bin\/od\)/ {
      print "  OD_TOOL=$(first_executable \"" od_path "\")"
      next
    }
    { print }
  ' "$ROUTING" > "$fixture"
  cp "$PROJECT_ROOT/templates/agent-roles/defaults.json" "$fixture_root/templates/agent-roles/defaults.json"
  chmod +x "$fixture"

  run bash "$fixture" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"(od stdout: ZZSTDOUTZZ)"* ]]
  [[ "$output" == *"(captured stderr: ZZSTDERRZZ)"* ]]
  [[ "$output" != *"(od stdout: ZZSTDERRZZ)"* ]]
  [[ "$output" != *"(captured stderr: ZZSTDOUTZZ)"* ]]
}

@test "od success with a benign stderr warning still completes the routing mutation" {
  local wrapper_dir="$TEST_TEMP_DIR/warn-od-bin"
  local fixture_root="$TEST_TEMP_DIR/routing-warn"
  local fixture="$fixture_root/scripts/lbwc-routing.sh"
  mkdir -p "$wrapper_dir" "$fixture_root"
  cp -R "$PROJECT_ROOT/scripts" "$fixture_root/scripts"
  mkdir -p "$fixture_root/templates/agent-roles"
  cp "$PROJECT_ROOT/templates/agent-roles/defaults.json" "$fixture_root/templates/agent-roles/defaults.json"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\\n' '00112233445566778899aabbccddeeff'" \
    "printf '%s\\n' 'od: warning: benign notice' >&2" \
    'exit 0' > "$wrapper_dir/od"
  chmod +x "$wrapper_dir/od"
  awk -v od_path="$wrapper_dir/od" '
    /^  OD_TOOL=\$\(first_executable \/usr\/bin\/od \/bin\/od\)/ {
      print "  OD_TOOL=$(first_executable \"" od_path "\")"
      next
    }
    { print }
  ' "$PROJECT_ROOT/scripts/lbwc-routing.sh" > "$fixture"
  chmod +x "$fixture"

  run bash "$fixture" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -eq 0 ]
  jq -e '
    .routing.profiles.balanced.roles.docs
    == {model: "ember-path", reasoning: "swift", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "unsupported and missing platform backends fail before routing mutation" {
  local mode fixture before after

  for mode in unsupported missing; do
    fixture=$(create_routing_failure_fixture "$mode")
    before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

    run bash "$fixture" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

    [ "$status" -ne 0 ]
    after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
    [ "$before" = "$after" ]
    [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock" ]
    [ ! -e "$TEST_TEMP_DIR/.lbwc-planning/.routing.lock.guard" ]
  done
}

@test "a live lock times out without changing configuration" {
  local lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  local owner before after
  sleep 30 &
  owner_pid=$!
  owner="$owner_pid"$'\t'"$(($(date +%s) - 120))"$'\t'"live-owner"
  mkdir "$lock"
  printf '%s\n' "$owner" > "$lock/owner"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run env LBWC_ROUTING_LOCK_WAIT_ATTEMPTS=3 \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not acquire routing lock"* ]]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  [ "$(<"$lock/owner")" = "$owner" ]
  kill -TERM "$owner_pid"
  wait "$owner_pid" 2>/dev/null || true
}

@test "a dead stale lock is reclaimed before updating configuration" {
  local lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  sleep 30 &
  owner_pid=$!
  kill -TERM "$owner_pid"
  wait "$owner_pid" 2>/dev/null || true
  mkdir "$lock"
  printf '%s\t%s\t%s\n' "$owner_pid" "$(($(date +%s) - 120))" "dead-owner" > "$lock/owner"

  run bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -eq 0 ]
  [ ! -e "$lock" ]
  jq -e '
    .routing.profiles.balanced.roles.docs
    == {model: "ember-path", reasoning: "swift", status: "resolved"}
  ' "$TEST_TEMP_DIR/.lbwc-planning/config.json" >/dev/null
}

@test "a malformed lock fails closed without changing configuration" {
  local lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  local before after
  mkdir "$lock"
  printf '%s\n' 'not owner metadata' > "$lock/owner"
  before=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')

  run env LBWC_ROUTING_LOCK_WAIT_ATTEMPTS=3 \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  after=$(shasum -a 256 "$TEST_TEMP_DIR/.lbwc-planning/config.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  [ "$(<"$lock/owner")" = 'not owner metadata' ]
}

@test "only the owning writer removes its lock during cleanup" {
  local wrapper_dir="$TEST_TEMP_DIR/bin"
  local real_jq ready release lock waiter_rc owner_record
  real_jq=$(command -v jq)
  ready="$TEST_TEMP_DIR/owner-transform-ready"
  release="$TEST_TEMP_DIR/release-owner-transform"
  lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  mkdir -p "$wrapper_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$*" == *'"'"'.routing.profiles[$profile].roles[$role]'"'"'* ]] && [[ " $* " == *'"'"' --arg role docs '"'"'* ]]; then' \
    '  output=$("$REAL_JQ" "$@")' \
    '  : > "$ROUTING_OWNER_READY"' \
    '  while [ ! -e "$ROUTING_OWNER_RELEASE" ]; do sleep 0.01; done' \
    '  printf '"'"'%s\n'"'"' "$output"' \
    'else' \
    '  exec "$REAL_JQ" "$@"' \
    'fi' > "$wrapper_dir/jq"
  chmod +x "$wrapper_dir/jq"

  env PATH="$wrapper_dir:$PATH" REAL_JQ="$real_jq" ROUTING_OWNER_READY="$ready" ROUTING_OWNER_RELEASE="$release" \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' \
    >/dev/null 2>&1 &
  owner_pid=$!
  for _ in {1..300}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  owner_record=$(<"$lock/owner")

  env LBWC_ROUTING_LOCK_WAIT_ATTEMPTS=3 \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced architect nova-route '"deliberate"' \
    >/dev/null 2>&1 || waiter_rc=$?

  [ "${waiter_rc:-0}" -ne 0 ]
  [ -d "$lock" ]
  [ "$(<"$lock/owner")" = "$owner_record" ]
  : > "$release"
  wait "$owner_pid"
  [ ! -e "$lock" ]
}

@test "an unowned lock is never reclaimed" {
  local lock="$TEST_TEMP_DIR/.lbwc-planning/.routing.lock"
  mkdir "$lock"

  run env LBWC_ROUTING_LOCK_WAIT_ATTEMPTS=3 \
    bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"'

  [ "$status" -ne 0 ]
  [ -d "$lock" ]
}

@test "repeated resolution always builds a lock owner token" {
  local attempt failures=0
  bash "$ROUTING" set "$TEST_TEMP_DIR/.lbwc-planning" balanced docs ember-path '"swift"' >/dev/null

  for ((attempt = 0; attempt < 100; attempt++)); do
    bash "$ROUTING" resolve "$TEST_TEMP_DIR/.lbwc-planning" docs >/dev/null 2>&1 \
      || failures=$((failures + 1))
  done

  [ "$failures" -eq 0 ]
}
