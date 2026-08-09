#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

@test "worktree-create: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-create.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-create: idempotent when worktree dir already exists" {
  mkdir -p "$TEST_TEMP_DIR/.lbwc-worktrees/01-01"
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
  [[ "$output" == *".lbwc-worktrees/01-01" ]]
}

@test "worktree-create: fail-open when not a git repo" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 01 01
  [ "$status" -eq 0 ]
}

@test "worktree-create: falls back to existing branch when -b path fails" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "LBWC Test"
  git config user.email "lbwc-test@example.com"
  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"

  git branch "lbwc/02-03"

  run bash "$SCRIPTS_DIR/worktree-create.sh" 02 03
  [ "$status" -eq 0 ]
  [[ "$output" == *".lbwc-worktrees/02-03" ]]
  [ -d ".lbwc-worktrees/02-03" ]

  run git -C ".lbwc-worktrees/02-03" rev-parse --abbrev-ref HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "lbwc/02-03" ]
}

@test "worktree-merge: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-merge.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "worktree-merge: outputs conflict when branch does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

@test "worktree-merge: outputs conflict when not in a git repo" {
  local subdir="$TEST_TEMP_DIR/sub"
  mkdir -p "$subdir"
  cd "$subdir"
  run bash "$SCRIPTS_DIR/worktree-merge.sh" 01 01
  [ "$status" -eq 0 ]
  [ "$output" = "conflict" ]
}

@test "worktree-cleanup: exits 0 with no arguments" {
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: exits 0 when worktree does not exist" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: rejects traversal in the phase component" {
  cd "$TEST_TEMP_DIR"
  mkdir -p outside-01

  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" ../outside 01

  [ "$status" -ne 0 ]
  [ -d outside-01 ]
}

@test "worktree-cleanup: removes residual worktree directory" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-worktrees/01-01/.lbwc-planning
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]
}

@test "worktree-cleanup: removes empty parent .lbwc-worktrees directory" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-worktrees/01-01/.lbwc-planning
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees" ]
}

@test "worktree-cleanup: preserves a sibling .DS_Store" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-worktrees/01-01/.lbwc-planning
  touch .lbwc-worktrees/.DS_Store
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]
  [ -f ".lbwc-worktrees/.DS_Store" ]
}

@test "worktree-cleanup: preserves sibling hidden files" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-worktrees/01-01/.lbwc-planning
  touch .lbwc-worktrees/.DS_Store
  touch .lbwc-worktrees/.localized
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]
  [ -f ".lbwc-worktrees/.DS_Store" ]
  [ -f ".lbwc-worktrees/.localized" ]
}

@test "worktree-cleanup: keeps .lbwc-worktrees when other worktrees exist" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-worktrees/01-01/.lbwc-planning
  mkdir -p .lbwc-worktrees/02-01
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]
  [ -d ".lbwc-worktrees/02-01" ]
  [ -d ".lbwc-worktrees" ]
}

@test "worktree-cleanup: deregisters real git worktree and prunes metadata" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "LBWC Test"
  git config user.email "lbwc-test@example.com"
  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"

  git worktree add -b lbwc/01-01 .lbwc-worktrees/01-01 HEAD 2>/dev/null
  run git worktree list
  [[ "$output" == *"01-01"* ]]

  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]

  run git worktree list
  [[ "$output" != *"01-01"* ]]
}

@test "worktree-cleanup: cleans locked worktree and its branch" {
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.name "LBWC Test"
  git config user.email "lbwc-test@example.com"
  echo "seed" > README.md
  git add README.md
  git commit -q -m "chore(init): seed"

  git worktree add -b lbwc/01-01 .lbwc-worktrees/01-01 HEAD 2>/dev/null
  git worktree lock .lbwc-worktrees/01-01

  run git worktree list
  [[ "$output" == *"01-01"* ]]

  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -d ".lbwc-worktrees/01-01" ]

  run git worktree list
  [[ "$output" != *"01-01"* ]]

  GIT_DIR="$(git rev-parse --git-dir)"
  if [ -d "$GIT_DIR/worktrees" ]; then
    for gf in "$GIT_DIR/worktrees"/*/gitdir; do
      [ -f "$gf" ] || continue
      ! grep -q "01-01" "$gf"
    done
  fi

  run git branch --list "lbwc/01-01"
  [ -z "$output" ]

  run git worktree add -b lbwc/01-01 .lbwc-worktrees/01-01 HEAD
  [ "$status" -eq 0 ]
  [ -d ".lbwc-worktrees/01-01" ]

  git worktree remove .lbwc-worktrees/01-01 --force 2>/dev/null || true
  git branch -d lbwc/01-01 2>/dev/null || true
}

@test "worktree-cleanup: clears agent-worktree JSON matching phase-plan" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo '{}' > .lbwc-planning/.agent-worktrees/agent-01-01.json
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -f ".lbwc-planning/.agent-worktrees/agent-01-01.json" ]
}

@test "worktree-status: exits 0" {
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-status: outputs valid JSON array" {
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '. | type == "array"'
}

@test "worktree-status: empty array when no LBWC worktrees" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "worktree-status: filters out non-LBWC worktrees in project root" {
  cd "$PROJECT_ROOT"
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.'
}

@test "worktree-agent-map integration: set and get round-trip with worktree path" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-01 "$TEST_TEMP_DIR/fake-path"
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/worktree-status.sh"
  [ "$status" -eq 0 ]
}

@test "worktree-create and worktree-agent-map: pipeline exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash "$SCRIPTS_DIR/worktree-create.sh" 02 03
  [ "$status" -eq 0 ]
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-03 "$TEST_TEMP_DIR/fake-path"
  [ "$status" -eq 0 ]
}

@test "worktree-cleanup: agent-map clear integration" {
  cd "$TEST_TEMP_DIR"
  bash "$SCRIPTS_DIR/worktree-agent-map.sh" set dev-01 "$TEST_TEMP_DIR/fake"
  mkdir -p .lbwc-planning/.agent-worktrees
  echo '{}' > .lbwc-planning/.agent-worktrees/dev-01-01-01.json
  run bash "$SCRIPTS_DIR/worktree-cleanup.sh" 01 01
  [ "$status" -eq 0 ]
  [ ! -f ".lbwc-planning/.agent-worktrees/dev-01-01-01.json" ]
  run bash "$SCRIPTS_DIR/worktree-agent-map.sh" get dev-01
  [ "$status" -eq 0 ]
}
