#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

run_guard() {
  local command="$1" agent_id="${2:-}"
  payload "tool_input.command=$command" "agent_id=$agent_id" | bash "$SCRIPTS_DIR/bash-guard.sh"
}

@test "allows an innocuous command" {
  run run_guard "ls -la"
  [ "$status" -eq 0 ]
}

@test "blocks a destructive command from the config list" {
  run run_guard "rm -rf /var/lib/mysql"
  [ "$status" -eq 2 ]
  [[ "$output" == *"destructive command detected"* ]]
}

@test "blocks git push --force" {
  run run_guard "git push --force origin main"
  [ "$status" -eq 2 ]
  [[ "$output" == *"destructive command detected"* ]]
}

@test "allows git push without force" {
  run run_guard "git push origin main"
  [ "$status" -eq 0 ]
}

@test "LBWC_ALLOW_DESTRUCTIVE overrides the blocklist" {
  run env LBWC_ALLOW_DESTRUCTIVE=1 bash -c "echo '{\"tool_input\":{\"command\":\"rm -rf /var/lib/mysql\"}}' | bash '$SCRIPTS_DIR/bash-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "scout role is blocked from writing via redirection" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  run run_guard "echo hi > out.txt" "scout-1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "scout role may run read-only git status" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  run run_guard "git status" "scout-1"
  [ "$status" -eq 0 ]
}

@test "scout role is blocked from command substitution" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  run run_guard 'echo $(whoami)' "scout-1"
  [ "$status" -eq 2 ]
}

@test "scout role does not trip on a quoted > inside an argument" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  run run_guard 'grep ">" file.txt' "scout-1"
  [ "$status" -eq 0 ]
}

@test "qa role is blocked from filesystem mutation commands" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"qa-1":{"role":"qa"}}}'
  run run_guard "mkdir newdir" "qa-1"
  [ "$status" -eq 2 ]
}

@test "python-engineer role is not subject to the read-only restriction" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"dev-1":{"role":"python-engineer"}}}'
  run run_guard "echo hi > out.txt" "dev-1"
  [ "$status" -eq 0 ]
}

@test "registered worker retains template-granted Bash" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-python-engineer-a\":{\"role\":\"python-engineer\",\"state\":\"registered\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[\"src/allowed.py\"]}}}"
  run run_guard "printf x" "lbwc-python-engineer-a"
  [ "$status" -eq 0 ]
}

@test "generated implementation roles deny Bash by default" {
  run jq -e '
    . as $defaults
    | ["debugger", "coding-dijkstra", "python-engineer", "web-engineer", "qa-author", "test-dev"]
    | all(.[]; ($defaults[.].disallowedTools | split(", ") | index("Bash")) != null)
  ' "$PROJECT_ROOT/templates/agent-roles/defaults.json"
  [ "$status" -eq 0 ]
}

@test "LBWC_ALLOW_DESTRUCTIVE does not bypass the scout read-only check" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" '{"agents":{"scout-1":{"role":"scout"}}}'
  local json
  json=$(payload "tool_input.command=echo hi > out.txt" "agent_id=scout-1")
  run env LBWC_ALLOW_DESTRUCTIVE=1 bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/bash-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "active generated agent cannot invoke Git through command wrappers" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for command in "git status" "\\git status" "\"git\" status" "g\\it status" "rtk git status" "rtk proxy git status" "rtk proxy \"git\" status" "command git status" "env GIT_DIR=. git status" "/usr/bin/git status"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Git is reserved for the main session"* ]]
  done
}

@test "active generated agent cannot hide Git in shell expansion" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"
  for command in "bash -c 'git status'" "sh -c \"rtk git status\"" "env CI=1 zsh -c 'git status'" "bash\${IFS}-c\${IFS}'git status'"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"shell execution route"* ]]
  done
}

@test "active generated agent cannot invoke nested shell interpreters" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for command in "bash\${IFS}-c\${IFS}'printf ready'" "bash \$IFS-c 'printf ready'" "bash scripts/wrapper-that-runs-git.sh" "sh scripts/wrapper-that-runs-git.sh" "rtk proxy bash scripts/wrapper-that-runs-git.sh" "rtk proxy sh scripts/wrapper-that-runs-git.sh"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"shell execution route"* ]]
  done
}

@test "active generated agent cannot use source or shell stdin execution" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for command in "source payload.sh" ". payload.sh" "bash < payload.sh" "printf x | sh" "bash <<< 'git status'"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"shell execution route"* ]]
  done
}

@test "active generated agent cannot target the critical execution policy" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for command in "cat config/subagent-critical-execution.txt" "printf x > config/subagent-critical-execution.txt"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"protected control path"* ]]
  done
}

@test "active generated agent cannot target protected control paths from Python" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for path in "config/subagent-critical-execution.txt" ".lbwc-planning/config.json" "scripts/bash-guard.sh" "scripts/task-contract.sh" "scripts/agent-lifecycle.sh" ".lbwc-planning/.agent-manifest.json" ".lbwc-planning/.contracts/tasks/forged.json" ".claude/agents/forged.md"; do
    run run_guard "python3 -c \"open('$path', 'w')\"" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"protected control path"* ]]
  done

  run run_guard "python3 -c \"from pathlib import Path; Path('config') / 'subagent-critical-execution.txt'\"" "lbwc-docs-a"
  [ "$status" -eq 2 ]
  [[ "$output" == *"protected control path"* ]]
}

@test "active generated agent cannot bypass Git policy with destructive override" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"
  local json
  json=$(payload "tool_input.command=git status" "agent_id=lbwc-docs-a")

  run env LBWC_ALLOW_DESTRUCTIVE=1 bash -c "printf '%s' '$json' | bash '$SCRIPTS_DIR/bash-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Git is reserved for the main session"* ]]
}

@test "forged generated agent identity fails closed for Git" {
  run run_guard "git status" "lbwc-forged-agent"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Git is reserved for the main session"* ]]
}

@test "active generated agent cannot invoke configured critical execution" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"

  for command in "claude --version" "npm install example" "curl https://example.com" "c\\url https://example.com" "sudo true" "kill 123"; do
    run run_guard "$command" "lbwc-docs-a"
    [ "$status" -eq 2 ]
    [[ "$output" == *"critical execution command"* ]]
  done
}

@test "active generated agent can run ordinary template-granted Bash" {
  write_manifest "$TEST_TEMP_DIR/.lbwc-planning" "{\"agents\":{\"lbwc-docs-a\":{\"role\":\"docs\",\"state\":\"running\",\"project_root\":\"$TEST_TEMP_DIR\",\"write_allowances\":[]}}}"
  run run_guard "printf '%s\\n' ready" "lbwc-docs-a"
  [ "$status" -eq 0 ]
}

@test "missing jq fails closed" {
  run env PATH="/usr/bin:/bin" bash -c "command -v jq >/dev/null 2>&1 && exit 77; echo '{}' | bash '$SCRIPTS_DIR/bash-guard.sh'"
  if [ "$status" -eq 77 ]; then
    skip "jq present on minimal PATH, cannot exercise the missing-jq path"
  fi
  [ "$status" -eq 2 ]
}
