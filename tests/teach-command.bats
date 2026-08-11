#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMMAND="$REPO_ROOT/commands/teach.md"
}

@test "teach command keeps the exact six-key LBWC header contract" {
  run awk 'NR == 1 {next} /^---$/ {exit} {print}' "$COMMAND"

  [ "$status" -eq 0 ]
  [ "$output" = "$(cat <<'EOF'
name: lbwc:teach
category: supporting
disable-model-invocation: true
description: View, add, remove, refresh, and reconcile project conventions through the LBWC trusted shell layer.
argument-hint: '["convention text" | remove <id> | refresh | list | group]'
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
EOF
)" ]
}

@test "teach command is LBWC scoped and main-session only" {
  run rg -n 'name: lbwc:teach|# LBWC Teach' "$COMMAND"
  [ "$status" -eq 0 ]
  run rg -n '\.vbw-planning|/vbw:teach|VBW Teach' "$COMMAND"
  [ "$status" -eq 1 ]
  run rg -n 'main session|AskUserQuestion' "$COMMAND"
  [ "$status" -eq 0 ]
}

@test "teach command delegates every artifact transition to the trusted CLI" {
  for operation in list add remove refresh group reconcile; do
    run rg -n "lbwc-conventions\\.sh.*$operation" "$COMMAND"
    [ "$status" -eq 0 ]
  done
  run rg -n 'jq .*conventions\.json|> *\.lbwc-planning/conventions\.json|Write.*conventions\.json|Edit.*conventions\.json' "$COMMAND"
  [ "$status" -eq 1 ]
}

@test "teach command asks before ambiguity and pauses for the answer" {
  run rg -n 'Semantic conflict|Redundancy|Confirm category|remove <id>|Mandatory pause|STOP' "$COMMAND"
  [ "$status" -eq 0 ]
  run rg -n 'Replace existing|Keep both|Cancel|Replace with new version|Add as separate' "$COMMAND"
  [ "$status" -eq 0 ]
}

@test "teach refresh keeps the full extraction and user precedence contract" {
  for source in PATTERNS.md ARCHITECTURE.md STACK.md CONCERNS.md; do
    run rg -n -F "$source" "$COMMAND"
    [ "$status" -eq 0 ]
  done
  run rg -n 'Maximum 15|User-defined always win|high|medium|low' "$COMMAND"
  [ "$status" -eq 0 ]
}

@test "teach command escalates generated-agent requests to the main session" {
  run rg -n 'user_decision_required|Generated agents|must not invoke|must not modify' "$COMMAND"
  [ "$status" -eq 0 ]
}

@test "teach command defines failure recovery and verification" {
  run rg -n '^## Failure and recovery|^## Verification' "$COMMAND"
  [ "$status" -eq 0 ]
  run rg -n 'state unchanged|--json list|compile-context\.sh' "$COMMAND"
  [ "$status" -eq 0 ]
}

@test "teach command requires styled next guidance after completed operations" {
  run rg -n 'End each completed operation with `Next:` guidance' "$COMMAND"

  [ "$status" -eq 0 ]
}
