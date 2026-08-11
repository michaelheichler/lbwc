#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/session-start.sh"
  TEST_ROOT="$(mktemp -d)"
  PLANNING_DIR="$TEST_ROOT/.lbwc-planning"
  export CLAUDE_SESSION_ID="session-start-${BATS_TEST_NUMBER}-$$"
  ROOT_LINK="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID}"
  rm -rf "$ROOT_LINK"
}

teardown() {
  rm -rf "$TEST_ROOT" "$ROOT_LINK"
  unset CLAUDE_SESSION_ID
}

run_session_start() {
  (
    cd "$REPO_ROOT"
    LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$SCRIPT"
  )
}

run_session_start_from() {
  local script_dir="$1"
  (
    cd "$REPO_ROOT"
    LBWC_PLANNING_DIR="$PLANNING_DIR" bash "$script_dir/session-start.sh"
  )
}

@test "session-start fails clearly when a required root link cannot be created" {
  local plugin_root="$TEST_ROOT/plugin"
  mkdir -p "$plugin_root"
  cp -R "$REPO_ROOT/scripts" "$plugin_root/scripts"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$plugin_root/scripts/ensure-plugin-root-link.sh"
  chmod +x "$plugin_root/scripts/ensure-plugin-root-link.sh"

  run run_session_start_from "$plugin_root/scripts"

  [ "$status" -eq 1 ]
  [[ "$output" == *"LBWC: SessionStart plugin root link bootstrap failed"* ]]
}

@test "session-start creates the exact session plugin root link" {
  local canonical_root
  canonical_root=$(cd "$REPO_ROOT" && pwd -P)

  run run_session_start

  [ "$status" -eq 0 ]
  [ -L "$ROOT_LINK" ]
  [ "$(readlink "$ROOT_LINK")" = "$canonical_root" ]
}

@test "session-start: cold start with no planning dir exits 0 and reports init needed" {
  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"no ${PLANNING_DIR}/ directory found"* ]]
}

@test "session-start: warm start with an existing project reports a phase brief" {
  mkdir -p "$PLANNING_DIR"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc phase"* ]]
}

@test "session-start: resume brief names the next command for a phase needing a plan" {
  mkdir -p "$PLANNING_DIR/phases/01-test"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"missing PLAN.md"* ]]
  [[ "$output" == *"/plan 01"* ]]
}

@test "session-start: needs_discussion routes to /discuss, not /plan" {
  mkdir -p "$PLANNING_DIR/phases/01-test"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"
  printf '# Roadmap\n\n### Phase 01: Test\n\n| Phase | Status |\n| 01 | pending |\n' > "$PLANNING_DIR/ROADMAP.md"
  printf '{"require_phase_discussion": true}\n' > "$PLANNING_DIR/config.json"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"missing CONTEXT.md"* ]]
  [[ "$output" == *"/discuss 01"* ]]
  [[ "$output" != *"/plan 01"* ]]
}

@test "session-start: phase setup failure is unavailable status, not missing planning" {
  local shim_dir="$TEST_ROOT/scripts-phase-detect-setup-failure"
  cp -R "$REPO_ROOT/scripts" "$shim_dir"
  cat > "$shim_dir/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'phase_detect_error=true' 'phase_detect_reason=setup_failed'
exit 1
EOF
  chmod +x "$shim_dir/phase-detect.sh"

  run run_session_start_from "$shim_dir"

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: phase status unavailable (setup_failed)."* ]]
  [[ "$output" != *"no ${PLANNING_DIR}/ directory found"* ]]
}

@test "session-start: surfaces a malformed agent manifest" {
  mkdir -p "$PLANNING_DIR"
  printf 'A real project description.\n' > "$PLANNING_DIR/PROJECT.md"
  printf '{not valid json\n' > "$PLANNING_DIR/.agent-manifest.json"

  run run_session_start

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: agent manifest status malformed."* ]]
}

@test "session-start: surfaces an unavailable agent manifest" {
  local shim_dir="$TEST_ROOT/scripts-agent-manifest-unavailable"
  cp -R "$REPO_ROOT/scripts" "$shim_dir"
  cat > "$shim_dir/agent-lifecycle.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'agent_manifest_status=unavailable'
exit 1
EOF
  chmod +x "$shim_dir/agent-lifecycle.sh"

  run run_session_start_from "$shim_dir"

  [ "$status" -eq 0 ]
  echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
  [[ "$output" == *"lbwc: agent manifest status unavailable."* ]]
}
