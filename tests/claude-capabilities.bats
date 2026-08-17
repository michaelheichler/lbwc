#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SCRIPT="$REPO_ROOT/scripts/claude-capabilities.sh"
  test_root="$(mktemp -d)"
  TEST_ROOT="$(cd "$test_root" && pwd -P)"
  PLANNING_DIR="$TEST_ROOT/project/.lbwc-planning"
  INVOCATION_MARKER="$TEST_ROOT/model-invoked"
  mkdir -p "$PLANNING_DIR"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

make_claude_fixture() {
  local binary="$1"
  write_claude_fixture \
    "$binary" \
    '91.7.3 (Fixture Code)' \
    'careful, brisk, exhaustive' \
    '[{id:"claude-amber-route",family:"amber",display_name:"Amber Route"},{id:"claude-violet-route",family:"violet",display_name:"Violet Route"}]' \
    '' \
    '' \
    '' \
    '["amber","violet"]'
}

write_claude_fixture() {
  local binary="$1" version="$2" efforts="$3" models_json="$4" associations="$5" unrelated_table="${6:-}" inspection_marker="${7:-}" host_enum="${8:-}"
  mkdir -p "$(dirname "$binary")"
  cat > "$binary" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -n '$inspection_marker' ]; then
  printf '%s\n' used > '$inspection_marker'
fi
case "\${1:-}" in
  --version)
    printf '%s\n' '$version'
    ;;
  --help)
    printf '%s\n' '  --effort <level>  Session reasoning' '                      ($efforts)'
    ;;
  *)
    printf '%s\n' invoked > "$INVOCATION_MARKER"
    exit 97
    ;;
esac
exit 0
: 'models:$models_json'
: '$unrelated_table'
: '$associations'
: '$host_enum'
EOF
  chmod +x "$binary"
}

extract_init_bootstrap() {
  # Extract the executable bootstrap block: the fenced bash block that invokes
  # lbwc-config.sh, not the earlier Context template-expansion blocks.
  awk '
    /^[[:space:]]*```bash$/ { capture = 1; block = ""; next }
    capture && /^[[:space:]]*```$/ {
      if (block ~ /lbwc-config\.sh/) { printf "%s", block; exit }
      capture = 0
      next
    }
    capture { sub(/^[[:space:]]{3}/, ""); block = block $0 "\n" }
  ' "$REPO_ROOT/commands/init.md"
}

@test "refresh saves exact binary-derived models and global reasoning values" {
  local binary="$TEST_ROOT/fixture bin/claude"
  make_claude_fixture "$binary"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ -f "$PLANNING_DIR/claude-capabilities.json" ]
  run jq -e --arg binary "$(realpath "$binary")" '
    .schema_version == 1
    and .source.binary_path == $binary
    and .source.version == "91.7.3 (Fixture Code)"
    and (.source.sha256 | test("^[[:xdigit:]]{64}$"))
    and (.source.detected_at | type == "string" and length > 0)
    and .models == [
      {selector:"claude-amber-route", label:"Amber Route", description:"Amber Route"},
      {selector:"claude-violet-route", label:"Violet Route", description:"Violet Route"},
      {selector:"amber", label:"amber", description:"amber"},
      {selector:"violet", label:"violet", description:"violet"}
    ]
    and .host_agent_enum == ["amber", "violet"]
    and .agent_model_ids == {
      "claude-amber-route":"amber",
      "claude-violet-route":"violet",
      "amber":"amber",
      "violet":"violet"
    }
    and .reasoning.scope == "global"
    and .reasoning.accepted_values == ["careful", "brisk", "exhaustive"]
    and .reasoning.model_associations == {}
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
  [ ! -e "$INVOCATION_MARKER" ]
}

@test "refresh keeps first-seen exact values while deduplicating selectors" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '5.4.3 (Arbitrary Fixture)' \
    'reflective, rapid, reflective, expansive' \
    '[{id:"claude-copper-one",family:"copper",display_name:"Copper One"},{id:"claude-copper-one",family:"copper",display_name:"Replacement"},{id:"claude-silver-two",family:"silver",display_name:"Silver Two"}]' \
    ''

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .models == [
      {selector:"claude-copper-one", label:"Copper One", description:"Copper One"},
      {selector:"claude-silver-two", label:"Silver Two", description:"Silver Two"},
      {selector:"copper", label:"copper", description:"copper"},
      {selector:"silver", label:"silver", description:"silver"}
    ]
    and .reasoning.accepted_values == ["reflective", "rapid", "expansive"]
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "refresh records exposed model-to-reasoning associations without restrictions" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '8.2.1 (Association Fixture)' \
    'measured, nimble, exhaustive' \
    '[{id:"claude-cedar",family:"cedar",display_name:"Cedar"},{id:"claude-birch",family:"birch",display_name:"Birch"}]' \
    'modelReasoningEfforts:{"claude-cedar":["measured","exhaustive"]}'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .reasoning.scope == "global"
    and .reasoning.accepted_values == ["measured", "nimble", "exhaustive"]
    and .reasoning.model_associations == {"claude-cedar":["measured", "exhaustive"]}
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "refresh changes provenance when executable bytes change" {
  local binary="$TEST_ROOT/claude" first_fingerprint
  make_claude_fixture "$binary"
  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  first_fingerprint=$(jq -r '.source.sha256' "$PLANNING_DIR/claude-capabilities.json")
  write_claude_fixture \
    "$binary" \
    '91.7.4 (Fixture Code)' \
    'patient, direct' \
    '[{id:"claude-indigo",family:"indigo",display_name:"Indigo"}]' \
    ''

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e --arg previous "$first_fingerprint" '
    .source.sha256 != $previous
    and .source.version == "91.7.4 (Fixture Code)"
    and [.models[].selector] == ["claude-indigo", "indigo"]
    and .reasoning.accepted_values == ["patient", "direct"]
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "failed extraction preserves the prior catalog byte for byte" {
  local binary="$TEST_ROOT/claude" before after temp_dir="$TEST_ROOT/capability-temp"
  mkdir -p "$temp_dir"
  make_claude_fixture "$binary"
  run env TMPDIR="$temp_dir" CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  before=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  write_claude_fixture "$binary" '91.7.5 (Broken Fixture)' 'patient, direct' '[]' ''

  run env TMPDIR="$temp_dir" CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"no validated model catalog"* ]]
  after=$(shasum -a 256 "$PLANNING_DIR/claude-capabilities.json" | awk '{print $1}')
  [ "$before" = "$after" ]
  run find "$PLANNING_DIR" -maxdepth 1 -name '.claude-capabilities.json.tmp.*' -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run find "$temp_dir" -mindepth 1 -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "refresh omits model entries whose id/family/display_name triple is incomplete" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '11.2.3 (Native Schema Fixture)' \
    'steady, swift' \
    '[{id:"claude-maple",family:"maple",display_name:"Maple"},{id:"claude-incomplete",family:"incomplete"}]' \
    ''

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '
    .models == [
      {selector:"claude-maple", label:"Maple", description:"Maple"},
      {selector:"maple", label:"maple", description:"maple"}
    ]
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "refresh ignores metadata from an unrelated binary UI table" {
  local binary="$TEST_ROOT/claude"
  write_claude_fixture \
    "$binary" \
    '12.4.6 (Metadata Boundary Fixture)' \
    'steady, swift' \
    '[{id:"claude-maple",family:"maple",display_name:"Maple"}]' \
    '' \
    'ui:[{id:"maple",label:"Unrelated Maple",description:"Unrelated UI choice"}]'

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e '.models == [{selector:"claude-maple", label:"Maple", description:"Maple"},{selector:"maple", label:"maple", description:"maple"}]' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "refresh rejects traversal components before path normalization" {
  local binary="$TEST_ROOT/claude" traversal
  make_claude_fixture "$binary"
  mkdir -p "$TEST_ROOT/project/unused"
  traversal="$TEST_ROOT/project/unused/../.lbwc-planning"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$traversal"

  [ "$status" -ne 0 ]
  [[ "$output" == *"traversal"* ]]
  [ ! -e "$PLANNING_DIR/claude-capabilities.json" ]
}

@test "refresh rejects a symlink at the state directory boundary" {
  local binary="$TEST_ROOT/claude" external="$TEST_ROOT/external" linked_parent="$TEST_ROOT/linked-project"
  make_claude_fixture "$binary"
  mkdir -p "$external" "$linked_parent"
  ln -s "$external" "$linked_parent/.lbwc-planning"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$linked_parent/.lbwc-planning"

  [ "$status" -ne 0 ]
  [[ "$output" == *"state directory boundary"* ]]
  [ ! -e "$external/claude-capabilities.json" ]
}

@test "refresh accepts the macOS var ancestor symlink" {
  local binary="$TEST_ROOT/claude" logical_planning
  [[ "$PLANNING_DIR" == /private/var/* ]] || skip 'temporary directory is not under /private/var'
  make_claude_fixture "$binary"
  logical_planning="/var/${PLANNING_DIR#/private/var/}"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$logical_planning"

  [ "$status" -eq 0 ]
  [ -f "$PLANNING_DIR/claude-capabilities.json" ]
}

@test "explicit executable path takes precedence over PATH discovery" {
  local selected="$TEST_ROOT/selected/claude" fallback="$TEST_ROOT/fallback/claude" fallback_marker="$TEST_ROOT/fallback-used"
  make_claude_fixture "$selected"
  write_claude_fixture \
    "$fallback" \
    '1.0.0 (Fallback Fixture)' \
    'fallback-only' \
    '[{id:"claude-fallback",family:"fallback",display_name:"Fallback"}]' \
    '' \
    '' \
    "$fallback_marker"

  run env PATH="$(dirname "$fallback"):$PATH" CLAUDE_CODE_EXECPATH="$selected" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e --arg selected "$(realpath "$selected")" '.source.binary_path == $selected' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
  [ ! -e "$fallback_marker" ]
}

@test "refresh records a new detection timestamp on regeneration" {
  local binary="$TEST_ROOT/claude" first_detected second_detected
  make_claude_fixture "$binary"
  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  first_detected=$(jq -r '.source.detected_at' "$PLANNING_DIR/claude-capabilities.json")
  sleep 1

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  second_detected=$(jq -r '.source.detected_at' "$PLANNING_DIR/claude-capabilities.json")
  [ "$first_detected" != "$second_detected" ]
}

@test "init bootstrap stops on configuration failure before transactional model refresh" {
  local plugin_root="$TEST_ROOT/plugin" project="$TEST_ROOT/init-project" bootstrap
  mkdir -p "$plugin_root/scripts" "$project/.lbwc-planning"
  cat > "$plugin_root/scripts/lbwc-config.sh" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-config:%s\n' "$*" >> "$INIT_TRACE"
exit "${FAIL_CONFIG:-0}"
EOF
  cat > "$plugin_root/scripts/lbwc-model" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-model:%s\n' "$*" >> "$INIT_TRACE"
exit 0
EOF
  bootstrap=$(extract_init_bootstrap)
  [ -n "$bootstrap" ]

  run env CLAUDE_PLUGIN_ROOT="$plugin_root" INIT_TRACE="$TEST_ROOT/init-trace" FAIL_CONFIG=31 bash -c "cd \"$project\" && $bootstrap"

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/init-trace")" = 'lbwc-config:init .lbwc-planning' ]
}

@test "init bootstrap stops after transactional model refresh failure" {
  local plugin_root="$TEST_ROOT/plugin" project="$TEST_ROOT/init-project" bootstrap
  mkdir -p "$plugin_root/scripts" "$project/.lbwc-planning"
  cat > "$plugin_root/scripts/lbwc-config.sh" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-config:%s\n' "$*" >> "$INIT_TRACE"
exit 0
EOF
  cat > "$plugin_root/scripts/lbwc-model" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-model:%s\n' "$*" >> "$INIT_TRACE"
exit "${FAIL_MODEL_REFRESH:-0}"
EOF
  bootstrap=$(extract_init_bootstrap)
  [ -n "$bootstrap" ]

  run env CLAUDE_PLUGIN_ROOT="$plugin_root" INIT_TRACE="$TEST_ROOT/init-trace" FAIL_MODEL_REFRESH=47 bash -c "cd \"$project\" && $bootstrap"

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/init-trace")" = $'lbwc-config:init .lbwc-planning\nlbwc-model:refresh .lbwc-planning' ]
  [[ "$output" == *'LBWC model catalog and routing refresh failed.'* ]]
}

@test "init bootstrap initializes configuration then runs one transactional model refresh" {
  local plugin_root="$TEST_ROOT/plugin" project="$TEST_ROOT/init-project" bootstrap
  mkdir -p "$plugin_root/scripts" "$project/.lbwc-planning"
  cat > "$plugin_root/scripts/lbwc-config.sh" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-config:%s\n' "$*" >> "$INIT_TRACE"
exit 0
EOF
  cat > "$plugin_root/scripts/lbwc-model" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-model:%s\n' "$*" >> "$INIT_TRACE"
exit 0
EOF
  bootstrap=$(extract_init_bootstrap)
  [ -n "$bootstrap" ]

  run env CLAUDE_PLUGIN_ROOT="$plugin_root" INIT_TRACE="$TEST_ROOT/init-trace" bash -c "cd \"$project\" && $bootstrap"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_ROOT/init-trace")" = $'lbwc-config:init .lbwc-planning\nlbwc-model:refresh .lbwc-planning' ]
}

@test "init bootstrap fails closed when the bundled model CLI is unavailable" {
  local plugin_root="$TEST_ROOT/plugin" project="$TEST_ROOT/init-project" bootstrap
  mkdir -p "$plugin_root/scripts" "$project/.lbwc-planning"
  cat > "$plugin_root/scripts/lbwc-config.sh" <<'EOF'
#!/usr/bin/env bash
printf 'lbwc-config:%s\n' "$*" >> "$INIT_TRACE"
exit 0
EOF
  bootstrap=$(extract_init_bootstrap)
  [ -n "$bootstrap" ]

  run env CLAUDE_PLUGIN_ROOT="$plugin_root" INIT_TRACE="$TEST_ROOT/init-trace" bash -c "cd \"$project\" && $bootstrap"

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/init-trace")" = 'lbwc-config:init .lbwc-planning' ]
  [[ "$output" == *'LBWC model catalog and routing refresh failed.'* ]]
}

@test "refresh accepts an executable symlink and records its physical target" {
  local target="$TEST_ROOT/physical/claude" link="$TEST_ROOT/bin/claude"
  make_claude_fixture "$target"
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link"

  run env CLAUDE_CODE_EXECPATH="$link" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e --arg target "$(realpath "$target")" '.source.binary_path == $target' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}

@test "refresh rejects a symlinked planning directory without writing its target" {
  local binary="$TEST_ROOT/claude" external="$TEST_ROOT/external" linked="$TEST_ROOT/linked-planning"
  make_claude_fixture "$binary"
  mkdir -p "$external"
  ln -s "$external" "$linked"

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$linked"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ ! -e "$external/claude-capabilities.json" ]
}

@test "refresh rejects a symlinked catalog without changing its target" {
  local binary="$TEST_ROOT/claude" external="$TEST_ROOT/external.json" before after
  make_claude_fixture "$binary"
  printf '%s\n' 'external sentinel' > "$external"
  ln -s "$external" "$PLANNING_DIR/claude-capabilities.json"
  before=$(shasum -a 256 "$external" | awk '{print $1}')

  run env CLAUDE_CODE_EXECPATH="$binary" bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  after=$(shasum -a 256 "$external" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "validate rejects a malformed catalog schema" {
  local catalog="$TEST_ROOT/malformed.json"
  printf '%s\n' '{"schema_version":1,"source":{},"models":[],"reasoning":{}}' > "$catalog"

  run bash "$SCRIPT" validate "$catalog"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid Claude Code capability catalog"* ]]
}

@test "installed Claude Code yields a validated catalog without a model call" {
  local installed
  installed=$(command -v claude 2>/dev/null || true)
  [ -n "$installed" ] || skip 'Claude Code is not installed'

  run env -u CLAUDE_CODE_EXECPATH bash "$SCRIPT" refresh "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  run jq -e --arg binary "$(realpath "$installed")" '
    .source.binary_path == $binary
    and (.source.version | length > 0)
    and (.models | length > 0)
    and (.reasoning.accepted_values | length > 0)
  ' "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" validate "$PLANNING_DIR/claude-capabilities.json"
  [ "$status" -eq 0 ]
}
