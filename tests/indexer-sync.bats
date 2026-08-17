#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$REPO_ROOT/scripts/indexer-sync.sh"
  TEST_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
  PROJECT_DIR="$TEST_ROOT/project"
  FAKE_BIN="$TEST_ROOT/bin"
  PLUGIN_ROOT="$TEST_ROOT/plugin"
  PLUGIN_DIR="$PLUGIN_ROOT/scripts"
  NODE_LOG="$TEST_ROOT/node.log"
  mkdir -p "$PROJECT_DIR" "$FAKE_BIN" "$PLUGIN_DIR/lib"

  git -C "$PROJECT_DIR" init -q
  git -C "$PROJECT_DIR" config user.email "test@test.com"
  git -C "$PROJECT_DIR" config user.name "Test"
  printf '%s\n' 'initial' > "$PROJECT_DIR/source.txt"
  git -C "$PROJECT_DIR" add source.txt
  git -C "$PROJECT_DIR" commit -qm "init"
  CURRENT_COMMIT="$(git -C "$PROJECT_DIR" rev-parse --short HEAD)"

  cp "$SCRIPT" "$PLUGIN_DIR/indexer-sync.sh"
  cp "$REPO_ROOT/scripts/ensure-plugin-root-link.sh" "$PLUGIN_DIR/ensure-plugin-root-link.sh"
  cp "$REPO_ROOT/scripts/resolve-plugin-root.sh" "$PLUGIN_DIR/resolve-plugin-root.sh"
  cp "$REPO_ROOT/scripts/lib/lbwc-control-root.sh" "$PLUGIN_DIR/lib/lbwc-control-root.sh"
  cp "$REPO_ROOT/scripts/lib/lbwc-target-root.sh" "$PLUGIN_DIR/lib/lbwc-target-root.sh"
  cat > "$PLUGIN_DIR/probe-map-tools.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --argjson available "${PROBE_GITNEXUS_AVAILABLE:-false}" \
  --argjson indexed "${PROBE_GITNEXUS_INDEXED:-false}" \
  --arg route "${PROBE_ROUTE:-grep-only}" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:({gitnexus:{available:$available,indexed:$indexed},recommended_route:$route} | tostring)}}'
EOF
  chmod +x "$PLUGIN_DIR/probe-map-tools.sh"

  cat > "$FAKE_BIN/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$NODE_LOG"
  case "${2:-}" in
  analyze)
    printf '%s\n' \
      'Repository indexed successfully (6.6s)' \
      '6,864 nodes | 8,200 edges | 138 clusters | 90 flows' \
      '/Users/michael/dev/skills/lbwc'
    ;;
  status)
    if [ "${INDEXER_STATUS_MODE:-fresh}" = "fresh" ]; then
      printf 'Repository: %s\nBranch: main\nIndexed: 8/14/2026, 2:32:25 PM\nIndexed commit: %s\nCurrent commit: %s\nStatus: ✅ up-to-date\n' \
        "$PROJECT_DIR" "$INDEXED_COMMIT" "$CURRENT_COMMIT"
    else
      printf 'Repository: %s\nBranch: main\nIndexed: 8/13/2026, 11:08:53 AM\nIndexed commit: 0000000\nCurrent commit: %s\nStatus: ⚠️ stale (re-run gitnexus analyze)\n' \
        "$PROJECT_DIR" "$CURRENT_COMMIT"
    fi
    ;;
  *)
    printf 'unexpected node arguments: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/node"
  COMMAND_SESSION_ID="indexer-sync-${BATS_TEST_NUMBER}-$$"
  ROOT_LINK="/tmp/.lbwc-plugin-root-link-${COMMAND_SESSION_ID}"
  rm -rf "$ROOT_LINK"
  export NODE_LOG PROJECT_DIR CURRENT_COMMIT INDEXED_COMMIT="$CURRENT_COMMIT" COMMAND_SESSION_ID ROOT_LINK
}

teardown() {
  rm -rf "$TEST_ROOT"
  rm -rf "$ROOT_LINK"
}

write_index() {
  mkdir -p "$PROJECT_DIR/.gitnexus"
  printf '%s\n' 'fixture' > "$PROJECT_DIR/.gitnexus/run.cjs"
}

set_probe() {
  PROBE_GITNEXUS_AVAILABLE="$1"
  PROBE_GITNEXUS_INDEXED="$2"
  PROBE_ROUTE="$3"
  export PROBE_GITNEXUS_AVAILABLE PROBE_GITNEXUS_INDEXED PROBE_ROUTE
}

initialize_planning() {
  mkdir -p "$PROJECT_DIR/.lbwc-planning"
  printf '%s\n' '{}' > "$PROJECT_DIR/.lbwc-planning/config.json"
}

extract_gate() {
  local command_name="$1"
  awk '
    /^## Index freshness gate$/ { in_gate=1; next }
    in_gate && /^## / { exit }
    in_gate && /^[[:space:]]*bash .*indexer-sync\.sh/ { print; exit }
  ' "$REPO_ROOT/commands/$command_name.md"
}

run_command_gate() {
  local command_name="$1" gate
  gate="$(extract_gate "$command_name")"
  gate="${gate//\{LINK\}/$PLUGIN_ROOT}"
  gate="${gate//\{PROJECT_ROOT\}/$PROJECT_DIR}"
  run bash -c "cd \"$PROJECT_DIR\" && $gate"
}

resolve_build_context() {
  local directive
  directive="$(awk '/^!`/{sub(/^!`/,""); sub(/`$/,""); print; exit}' "$REPO_ROOT/commands/build.md")"
  [ -n "$directive" ] || return 1

  run env -u LINK -u PROJECT_ROOT \
    CLAUDE_SESSION_ID="$COMMAND_SESSION_ID" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash -c "cd \"$PROJECT_DIR\" && $directive"
  [ "$status" -eq 0 ] || return "$status"

  RESOLVED_LINK="$(printf '%s\n' "$output" | awk -F': ' '/^Plugin root: /{print $2; exit}')"
  RESOLVED_PROJECT_ROOT="$(printf '%s\n' "$output" | awk -F': ' '/^Project root: /{print $2; exit}')"
  [ "$RESOLVED_LINK" = "$PLUGIN_ROOT" ]
  [ "$RESOLVED_PROJECT_ROOT" = "$PROJECT_DIR" ]
}

run_resolved_build_gate() {
  local gate
  resolve_build_context || return $?
  gate="$(extract_gate build)"
  gate="${gate//\{LINK\}/$RESOLVED_LINK}"
  gate="${gate//\{PROJECT_ROOT\}/$RESOLVED_PROJECT_ROOT}"
  [[ "$gate" != *'{'* ]] || return 1

  run env \
    PATH="$FAKE_BIN:$PATH" \
    LBWC_PLANNING_DIR="$PROJECT_DIR/.lbwc-planning" \
    bash -c "cd \"$PROJECT_DIR\" && $gate"
}

@test "indexer-sync leaves a fresh project uninitialized when grep-only mapping is selected" {
  set_probe false false grep-only

  run_sync

  [ "$status" -eq 0 ]
  [ ! -e "$PROJECT_DIR/.lbwc-planning" ]
  [ ! -e "$NODE_LOG" ]
}

@test "indexer-sync does not persist probe state in an uninitialized planning directory" {
  mkdir -p "$PROJECT_DIR/.lbwc-planning"
  set_probe false false grep-only

  run_sync

  [ "$status" -eq 0 ]
  [ -d "$PROJECT_DIR/.lbwc-planning" ]
  [ ! -e "$PROJECT_DIR/.lbwc-planning/MAP-TOOLS.json" ]
  [ ! -e "$PROJECT_DIR/.lbwc-planning/.runtime" ]
}

run_sync() {
  run env \
    PATH="$FAKE_BIN:$PATH" \
    LBWC_PLANNING_DIR="$PROJECT_DIR/.lbwc-planning" \
    bash "$PLUGIN_DIR/indexer-sync.sh" --project-root "$PROJECT_DIR" "$@"
}

@test "indexer-sync refreshes and records a fresh configured GitNexus index" {
  initialize_planning
  write_index
  set_probe true true gitnexus

  run_sync

  [ "$status" -eq 0 ]
  grep -F -- '.gitnexus/run.cjs analyze' "$NODE_LOG"
  grep -F -- '.gitnexus/run.cjs status' "$NODE_LOG"
  jq -e --arg commit "$CURRENT_COMMIT" \
    '.map_route == "gitnexus" and (.gitnexus | contains("up-to-date")) and .indexed_commit == $commit' \
    "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync blocks a configured GitNexus route when the index is missing" {
  initialize_planning
  set_probe true false gitnexus

  run_sync

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitNexus index is missing"* ]]
  [ ! -e "$NODE_LOG" ]
  jq -e '.map_route == "gitnexus" and .gitnexus == "missing"' \
    "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync blocks a stale GitNexus status after refresh" {
  initialize_planning
  write_index
  set_probe true true gitnexus
  INDEXER_STATUS_MODE=stale
  export INDEXER_STATUS_MODE

  run_sync

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitNexus index is stale"* ]]
  grep -F -- '.gitnexus/run.cjs analyze' "$NODE_LOG"
  grep -F -- '.gitnexus/run.cjs status' "$NODE_LOG"
  jq -e '.map_route == "gitnexus" and (.gitnexus | contains("stale"))' \
    "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync accepts an unavailable GitNexus when the map route is grep-only" {
  initialize_planning
  set_probe false false grep-only

  run_sync

  [ "$status" -eq 0 ]
  [ ! -e "$NODE_LOG" ]
  jq -e '.map_route == "grep-only" and .gitnexus == "unavailable"' \
    "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync exposes an explicit Serena refresh capability gap" {
  initialize_planning
  set_probe false false serena

  run_sync

  [ "$status" -eq 0 ]
  [[ "$output" == *"Serena route selected"* ]]
  [[ "$output" == *"serena-refresh-unsupported"* ]]
  [ ! -e "$NODE_LOG" ]
  jq -e '
    .map_route == "serena"
    and .gitnexus == "not-selected"
    and .capability_gap == {
      status: "unsupported",
      code: "serena-refresh-unsupported",
      route: "serena"
    }
  ' "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync rejects an unknown map route" {
  initialize_planning
  set_probe false false unknown

  run_sync

  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported map route"* ]]
  [[ "$output" == *"unknown"* ]]
  jq -e '
    .map_route == "unknown"
    and .capability_gap == {
      status: "unsupported",
      code: "unknown-map-route",
      route: "unknown"
    }
  ' "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "indexer-sync can require GitNexus explicitly" {
  initialize_planning
  set_probe false false grep-only

  run_sync --require-gitnexus

  [ "$status" -eq 1 ]
  [[ "$output" == *"GitNexus index is required"* ]]
}

@test "indexer-sync reports missing jq as a tooling failure" {
  initialize_planning
  write_index
  set_probe true true gitnexus
  cat > "$FAKE_BIN/jq" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "$FAKE_BIN/jq"

  run_sync

  [ "$status" -eq 2 ]
  [[ "$output" == *"jq"* ]]
}

@test "indexer-sync fails clearly when the map-tools probe is unavailable" {
  rm -f "$PLUGIN_DIR/probe-map-tools.sh"

  run_sync

  [ "$status" -eq 2 ]
  [[ "$output" == *"required map-tools probe is unavailable"* ]]
  [ ! -e "$PROJECT_DIR/.lbwc-planning" ]
}

@test "indexer-sync accepts the current GitNexus status output format" {
  initialize_planning
  write_index
  set_probe true true gitnexus

  run_sync

  [ "$status" -eq 0 ]
  jq -e --arg commit "$CURRENT_COMMIT" \
    '.map_route == "gitnexus" and .gitnexus == "up-to-date" and .indexed_commit == $commit' \
    "$PROJECT_DIR/.lbwc-planning/.runtime/indexer-sync.json" >/dev/null
}

@test "vibe and team execute the indexer gate before their workflows" {
  set_probe false false grep-only

  for command_name in vibe team; do
    run_command_gate "$command_name"
    [ "$status" -eq 0 ]
  done
  [ ! -e "$PROJECT_DIR/.lbwc-planning" ]
}

@test "vibe and team stop when their indexer gate fails" {
  rm -f "$PLUGIN_DIR/probe-map-tools.sh"

  for command_name in vibe team; do
    run_command_gate "$command_name"
    [ "$status" -eq 2 ]
    [[ "$output" == *"required map-tools probe is unavailable"* ]]
  done
  [ ! -e "$PROJECT_DIR/.lbwc-planning" ]
}

@test "build resolves its context and invokes the mandatory indexer helper" {
  set_probe false false grep-only

  run grep -c '^!`' "$REPO_ROOT/commands/build.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run_resolved_build_gate

  [ "$status" -eq 0 ]
  [ "$RESOLVED_LINK" = "$PLUGIN_ROOT" ]
  [ "$RESOLVED_PROJECT_ROOT" = "$PROJECT_DIR" ]
  [ ! -e "$PROJECT_DIR/.lbwc-planning" ]
}

@test "build stops when its resolved mandatory indexer helper fails" {
  rm -f "$PLUGIN_DIR/probe-map-tools.sh"

  run_resolved_build_gate

  [ "$status" -eq 2 ]
  [[ "$output" == *"required map-tools probe is unavailable"* ]]
}

@test "team runs the indexer gate before agent teams enablement and preflight" {
  local gate_line enable_line preflight_line catalog_line
  gate_line="$(grep -n 'indexer-sync.sh' "$REPO_ROOT/commands/team.md" | cut -d: -f1)"
  catalog_line="$(grep -n 'lbwc-model" refresh' "$REPO_ROOT/commands/team.md" | cut -d: -f1)"
  enable_line="$(grep -n 'agent-teams-enable --approved' "$REPO_ROOT/commands/team.md" | cut -d: -f1)"
  preflight_line="$(grep -n '\*\*Preflight (read-only)\.\*\*' "$REPO_ROOT/commands/team.md" | cut -d: -f1)"

  [ "$gate_line" -lt "$enable_line" ]
  [ "$gate_line" -lt "$preflight_line" ]
  [ "$gate_line" -lt "$catalog_line" ]
  [ "$catalog_line" -lt "$preflight_line" ]
}

@test "build runs the indexer gate before phase and plan state reads" {
  local gate_line phase_line plan_line
  gate_line="$(grep -n 'bash "{LINK}/scripts/indexer-sync.sh"' "$REPO_ROOT/commands/build.md" | cut -d: -f1)"
  phase_line="$(grep -n 'phase-detect.sh' "$REPO_ROOT/commands/build.md" | cut -d: -f1)"
  plan_line="$(grep -n 'Read the selected root' "$REPO_ROOT/commands/build.md" | cut -d: -f1)"

  [ "$gate_line" -lt "$phase_line" ]
  [ "$gate_line" -lt "$plan_line" ]
}
