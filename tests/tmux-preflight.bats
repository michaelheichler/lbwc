#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SCRIPT="$REPO_ROOT/scripts/tmux-preflight.sh"
  TEST_ROOT="$(mktemp -d)"
  PROJECT_ROOT="$TEST_ROOT/project"
  CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
  BIN_DIR="$TEST_ROOT/bin"
  mkdir -p "$CONTROL_ROOT" "$BIN_DIR"
  printf '%s\n' '{}' > "$CONTROL_ROOT/config.json"
  cat > "$BIN_DIR/tmux" <<'SCRIPT'
#!/usr/bin/env bash
[ "$1" = '-V' ] && { printf '%s\n' 'tmux 3.5'; exit 0; }
[ "$1" = 'has-session' ] && exit 1
exit 1
SCRIPT
  cat > "$BIN_DIR/claude" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$BIN_DIR/tmux" "$BIN_DIR/claude"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "preflight probes a missing runtime parent without leaving runtime state" {
  run env -u TMUX -u TMUX_PANE PATH="$BIN_DIR:$PATH" bash "$SCRIPT" --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" --main-id main-session

  [ "$status" -eq 0 ]
  [ ! -e "$CONTROL_ROOT/.runtime" ]
}

@test "failed runtime parent probe removes the parent it created" {
  cat > "$BIN_DIR/python3" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "$BIN_DIR/python3"

  run env -u TMUX -u TMUX_PANE PATH="$BIN_DIR:$PATH" bash "$SCRIPT" --project-root "$PROJECT_ROOT" --control-root "$CONTROL_ROOT" --main-id main-session

  [ "$status" -ne 0 ]
  [ ! -e "$CONTROL_ROOT/.runtime" ]
}
