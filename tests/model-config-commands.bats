#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MODELS="$REPO_ROOT/commands/models.md"
  CONFIG="$REPO_ROOT/commands/config.md"
}

line_number() {
  local pattern="$1" file="$2"
  rg -n -m 1 "$pattern" "$file" | cut -d: -f1
}

# Anchored to the body so a frontmatter edit (e.g. widening allowed-tools)
# can never coincidentally match first and silently retarget this ordering
# assertion onto the wrong line.
body_line_number() {
  local pattern="$1" file="$2"
  local body_start relative_line
  body_start=$(awk '/^---$/{n++; if (n == 2) {print NR; exit}}' "$file")
  relative_line=$(tail -n "+$((body_start + 1))" "$file" | rg -n -m 1 "$pattern" | cut -d: -f1)
  [ -n "$relative_line" ] && echo $((body_start + relative_line))
}

@test "models command refreshes before display and routes every write through lbwc-model" {
  [ -f "$MODELS" ]
  refresh_line=$(body_line_number 'lbwc-model.*refresh' "$MODELS")
  show_line=$(body_line_number 'lbwc-model.*show' "$MODELS")
  question_line=$(body_line_number 'Use native AskUserQuestion' "$MODELS")
  [ "$refresh_line" -lt "$show_line" ]
  [ "$show_line" -lt "$question_line" ]
  run rg -n 'lbwc-model.*(activate|set|copy|validate)' "$MODELS"
  [ "$status" -eq 0 ]
  run rg -n 'main session' "$MODELS"
  [ "$status" -eq 0 ]
}

@test "models command exposes deterministic machine arguments without prose writes" {
  run rg -n '\$ARGUMENTS|--json|<operation>|activate|set|copy|validate|catalog' "$MODELS"
  [ "$status" -eq 0 ]
  run rg -n 'jq .*config\.json|printf .*>.*config\.json|> *\.lbwc-planning/config\.json' "$MODELS"
  [ "$status" -eq 1 ]
}

@test "config command refreshes before presentation and delegates routes" {
  [ -f "$CONFIG" ]
  refresh_line=$(line_number 'lbwc-model.*refresh' "$CONFIG")
  present_line=$(line_number 'lbwc-config\.sh.*get|Present' "$CONFIG")
  [ "$refresh_line" -lt "$present_line" ]
  run rg -n 'lbwc-model.*activate' "$CONFIG"
  [ "$status" -eq 0 ]
  run rg -n 'lbwc-config\.sh.*set' "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "config command names every currently writable setting and deterministic value form" {
  while IFS= read -r setting; do
    run rg -n -F "$setting" "$CONFIG"
    if [ "$status" -ne 0 ]; then
      printf 'missing setting: %s\n' "$setting" >&3
      return 1
    fi
  done <<'SETTINGS'
effort
autonomy
auto_commit
planning_tracking
auto_push
verification_tier
context_compiler
max_tasks_per_plan
prefer_teams
auto_uat
require_phase_discussion
rolling_summary
metrics
caveman_style
caveman_commit
caveman_review
max_uat_remediation_rounds
routing.active_profile
SETTINGS
  run rg -n '<setting> <value>|\$ARGUMENTS' "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "config command does not claim unavailable parity settings" {
  run rg -ni 'future parity|VBW parity|coming soon|not yet present' "$CONFIG"
  [ "$status" -eq 1 ]
}
