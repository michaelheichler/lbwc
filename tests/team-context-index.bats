#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  RUN_DIR="$PROJECT_DIR/.temporary-agent-runfiles/runs/run-1"
  mkdir -p "$PROJECT_DIR" "$RUN_DIR"
  SCRIPT="$SCRIPTS_DIR/team-context-index.sh"
}

teardown() {
  teardown_temp_dir
}

run_index() {
  run bash "$SCRIPT" --project-root "$PROJECT_DIR" --run-root "$RUN_DIR" "$@"
}

@test "authoritative index gives explicit plan and instruction precedence" {
  mkdir -p "$PROJECT_DIR/.planning/phases"
  printf '%s\n' '# GSD plan' > "$PROJECT_DIR/.planning/phases/01-PLAN.md"
  printf '%s\n' '# Generic plan' > "$PROJECT_DIR/generic.md"
  explicit="$TEST_TEMP_DIR/explicit.md"
  marker="$TEST_TEMP_DIR/injection-marker"
  printf '%s\n' '# Explicit plan' > "$explicit"

  run_index --plan "$explicit" --instruction "Use this text \$(touch '$marker')"

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  jq -e --arg path "$(cd "$(dirname "$explicit")" && pwd -P)/$(basename "$explicit")" \
    '(.selection.status == "explicit") and
     (.selection.authority == "explicit-plan-and-instruction") and
     (.selection.selected_plan.canonical_path == $path) and
     (.request.instruction | contains("$(touch"))' \
    "$RUN_DIR/plan-index.json" >/dev/null
}

@test "no instruction returns newest candidates without auto-selecting" {
  printf '%s\n' '# Older plan' > "$PROJECT_DIR/older.md"
  printf '%s\n' '# Newer plan' > "$PROJECT_DIR/newer.md"
  touch -t 202601010101 "$PROJECT_DIR/older.md"
  touch -t 202602020202 "$PROJECT_DIR/newer.md"

  run_index

  [ "$status" -eq 0 ]
  jq -e '
    (.selection.status == "needs-user-selection") and
    (.selection.selected_plan == null) and
    ((.selection.display_candidates | length) == 2) and
    (.selection.display_candidates[0].canonical_path | endswith("/newer.md")) and
    (.selection.display_candidates[1].canonical_path | endswith("/older.md"))
  ' "$RUN_DIR/plan-index.json" >/dev/null
}

@test "recognized GSD candidates stay separate from capped generic Markdown" {
  mkdir -p "$PROJECT_DIR/.planning/phases"
  printf '%s\n' '---' 'title: GSD work' '---' '# GSD work' \
    > "$PROJECT_DIR/.planning/phases/01-01-PLAN.md"
  for n in $(seq 1 70); do
    printf '# Generic %s\n' "$n" > "$PROJECT_DIR/generic-$n.md"
  done

  run_index

  [ "$status" -eq 0 ]
  jq -e '
    .caps.generic_max_files == 64 and
    ([.candidates[] | select(.source_system == "gsd" and .trust_tier == "verified-adapter")] | length) == 1 and
    ([.candidates[] | select(.source_system == "markdown" and .trust_tier == "unverified-markdown")] | length) == 64
  ' "$RUN_DIR/plan-index.json" >/dev/null
}

@test "configured plansDirectory is the fallback tier" {
  plans_dir="$TEST_TEMP_DIR/claude-plans"
  mkdir -p "$plans_dir"
  printf '%s\n' '# Claude plan' > "$plans_dir/plan.md"
  settings="$TEST_TEMP_DIR/settings.json"
  jq -n --arg plans "$plans_dir" '{plansDirectory: $plans}' > "$settings"

  run_index --settings "$settings"

  [ "$status" -eq 0 ]
  jq -e --arg path "$(cd "$plans_dir" && pwd -P)/plan.md" '
    .candidates[0].source_system == "claude-code" and
    .candidates[0].precedence_tier == 5 and
    .candidates[0].canonical_path == $path and
    .candidates[0].trust_tier == "unverified-markdown"
  ' "$RUN_DIR/plan-index.json" >/dev/null
}

@test "configured plansDirectory inside the project stays out of generic scanning" {
  plans_dir="$PROJECT_DIR/custom-plans"
  mkdir -p "$plans_dir"
  printf '%s\n' '# Claude plan' > "$plans_dir/plan.md"
  settings="$TEST_TEMP_DIR/settings.json"
  jq -n --arg plans "$plans_dir" '{plansDirectory: $plans}' > "$settings"

  run_index --settings "$settings"

  [ "$status" -eq 0 ]
  jq -e '
    ([.candidates[] | select(.canonical_path | endswith("/custom-plans/plan.md"))] | length) == 1 and
    ([.candidates[] | select(.canonical_path | endswith("/custom-plans/plan.md"))][0].precedence_tier) == 5
  ' "$RUN_DIR/plan-index.json" >/dev/null
}

@test "missing plansDirectory uses the Claude fallback" {
  claude_home="$TEST_TEMP_DIR/home"
  plans_dir="$claude_home/.claude/plans"
  mkdir -p "$plans_dir"
  printf '%s\n' '# Fallback plan' > "$plans_dir/plan.md"

  run env HOME="$claude_home" bash "$SCRIPT" \
    --project-root "$PROJECT_DIR" --run-root "$RUN_DIR"

  [ "$status" -eq 0 ]
  jq -e --arg path "$(cd "$plans_dir" && pwd -P)/plan.md" \
    '(.candidates[0].canonical_path == $path) and
     (.candidates[0].detection_evidence | any(. == "default Claude Code plans directory"))' \
    "$RUN_DIR/plan-index.json" >/dev/null
}

@test "Claude plans fallback is capped and newest-first" {
  claude_home="$TEST_TEMP_DIR/home"
  plans_dir="$claude_home/.claude/plans"
  mkdir -p "$plans_dir"
  for n in $(seq 1 20); do
    printf '# Claude %s\n' "$n" > "$plans_dir/plan-$n.md"
    touch -t "202601$(printf '%02d' "$n")0101" "$plans_dir/plan-$n.md"
  done

  run env HOME="$claude_home" bash "$SCRIPT" \
    --project-root "$PROJECT_DIR" --run-root "$RUN_DIR"

  [ "$status" -eq 0 ]
  jq -e '
    ([.candidates[] | select(.source_system == "claude-code")] | length) == 16 and
    ([.candidates[] | select(.source_system == "claude-code")][0].canonical_path | endswith("/plan-20.md"))
  ' "$RUN_DIR/plan-index.json" >/dev/null
}

@test "indexes contain canonical paths and sha256 digests" {
  printf '%s\n' '# Digest me' > "$PROJECT_DIR/plan.md"
  mkdir -p "$PROJECT_DIR/.lbwc-planning/codebase"
  printf '%s\n' \
    'mapped_at: 2026-01-01T00:00:00Z' \
    'git_hash: 0000000000000000000000000000000000000000' \
    'file_count: 1' \
    > "$PROJECT_DIR/.lbwc-planning/codebase/META.md"
  printf '%s\n' '# Stack' > "$PROJECT_DIR/.lbwc-planning/codebase/STACK.md"

  run_index

  [ "$status" -eq 0 ]
  digest=$(shasum -a 256 "$PROJECT_DIR/plan.md" | awk '{print $1}')
  map_digest=$(shasum -a 256 "$PROJECT_DIR/.lbwc-planning/codebase/META.md" | awk '{print $1}')
  jq -e --arg path "$(cd "$PROJECT_DIR" && pwd -P)/plan.md" --arg digest "sha256:$digest" \
    '.candidates[0].canonical_path == $path and .candidates[0].digest == $digest' \
    "$RUN_DIR/plan-index.json" >/dev/null
  jq -e --arg path "$(cd "$PROJECT_DIR/.lbwc-planning/codebase" && pwd -P)/META.md" \
    --arg digest "sha256:$map_digest" \
    '.artifacts | any(.canonical_path == $path and .digest == $digest and .freshness == "stale")' \
    "$RUN_DIR/codebase-index.json" >/dev/null
}

@test "prompt injection text remains inert data" {
  marker="$TEST_TEMP_DIR/prompt-marker"
  printf '%s\n' '# $(touch '"$marker"')' '!`touch '"$marker"'`' > "$PROJECT_DIR/plan.md"

  run_index

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  jq -e --arg marker "$marker" \
    '.candidates[0].title | contains("$(touch") and contains($marker)' \
    "$RUN_DIR/plan-index.json" >/dev/null
}

@test "authoritative discovery never creates .lbwc-planning" {
  rm -rf "$PROJECT_DIR/.lbwc-planning"
  printf '%s\n' '# Plan' > "$PROJECT_DIR/plan.md"

  run_index

  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT_DIR/.lbwc-planning" ]
  [ -f "$RUN_DIR/plan-index.json" ]
  [ -f "$RUN_DIR/codebase-index.json" ]
}

@test "generic Markdown scanning skips oversized files" {
  dd if=/dev/zero of="$PROJECT_DIR/oversized.md" bs=1048577 count=1 2>/dev/null
  printf '%s\n' '# Small plan' > "$PROJECT_DIR/small.md"

  run_index

  [ "$status" -eq 0 ]
  jq -e '
    .caps.max_file_bytes == 1048576 and
    ([.candidates[] | select(.canonical_path | endswith("/oversized.md"))] | length) == 0 and
    ([.candidates[] | select(.canonical_path | endswith("/small.md"))] | length) == 1
  ' "$RUN_DIR/plan-index.json" >/dev/null
}
