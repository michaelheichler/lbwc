#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REAL_SCRIPT="$REPO_ROOT/scripts/lbwc-skills.sh"
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lbwc-skills.XXXXXX")
  PLUGIN_ROOT="$TEST_ROOT/plugin"
  PROJECT_ROOT="$TEST_ROOT/project"
  PLANNING_DIR="$PROJECT_ROOT/.lbwc-planning"
  DETECTOR_RESPONSE="$TEST_ROOT/detector.json"
  DETECTOR_TRACE="$TEST_ROOT/detector.trace"
  mkdir -p "$PLUGIN_ROOT/scripts" "$PLANNING_DIR"
  if [ -f "$REAL_SCRIPT" ]; then
    cp "$REAL_SCRIPT" "$PLUGIN_ROOT/scripts/lbwc-skills.sh"
  fi
  SCRIPT="$PLUGIN_ROOT/scripts/lbwc-skills.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$1" >> "$LBWC_DETECTOR_TRACE"' \
    'cat "$LBWC_DETECTOR_RESPONSE"' \
    > "$PLUGIN_ROOT/scripts/detect-stack.sh"
  chmod +x "$PLUGIN_ROOT/scripts/detect-stack.sh"
  write_config true false true
  write_detector '[]' '[]' '[]' '[]' '[]'
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_config() {
  local suggestions="$1" auto_install="$2" questions="$3"
  jq -n \
    --argjson suggestions "$suggestions" \
    --argjson auto_install "$auto_install" \
    --argjson questions "$questions" '
      {
        skill_suggestions: $suggestions,
        auto_install_skills: $auto_install,
        discovery_questions: $questions
      }
    ' > "$PLANNING_DIR/config.json"
}

write_detector() {
  local stack="$1" global="$2" project="$3" recommended="$4" suggestions="$5"
  jq -n \
    --argjson stack "$stack" \
    --argjson global "$global" \
    --argjson project "$project" \
    --argjson recommended "$recommended" \
    --argjson suggestions "$suggestions" '
      {
        detected_stack: $stack,
        installed: {global: $global, project: $project},
        recommended_skills: $recommended,
        suggestions: $suggestions,
        global_skills_dir: "/fixture/global/skills"
      }
    ' > "$DETECTOR_RESPONSE"
}

run_skills() {
  run env \
    LBWC_DETECTOR_RESPONSE="$DETECTOR_RESPONSE" \
    LBWC_DETECTOR_TRACE="$DETECTOR_TRACE" \
    bash "$SCRIPT" "$@"
}

@test "list returns a stable empty discovery result when no stack is detected" {
  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [ "$output" = '{"candidate_count":0,"candidates":[],"config":{"auto_install_skills":false,"discovery_questions":true,"skill_suggestions":true},"detected_stack":[],"installed":{"global":[],"project":[]},"operation":"list","question_mode":"none","schema_version":1}' ]
  expected_root=$(cd -P "$PROJECT_ROOT" && pwd -P)
  [ "$(cat "$DETECTOR_TRACE")" = "$expected_root" ]
}

@test "one candidate selects the single-question mode" {
  write_detector '["python"]' '[]' '[]' '["skill-z"]' '["skill-z"]'

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  run jq -e '
    .candidate_count == 1
    and .question_mode == "single"
    and .candidates == ["skill-z"]
  ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "two to four candidates select bounded questions and stable ordering" {
  write_detector '["typescript"]' '[]' '[]' '["skill-c","skill-a","skill-b"]' '["skill-c","skill-a","skill-b","skill-a"]'

  run_skills --json refresh "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  compact=$(jq -cS . <<< "$output")
  [ "$output" = "$compact" ]
  run jq -e '
    .operation == "refresh"
    and .candidate_count == 3
    and .question_mode == "bounded"
    and .candidates == ["skill-a","skill-b","skill-c"]
  ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "more than four candidates select validated freeform questions" {
  write_detector '["rust"]' '[]' '[]' '[]' '["skill-5","skill-2","skill-1","skill-4","skill-3"]'

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  run jq -e '
    .candidate_count == 5
    and .question_mode == "freeform"
    and .candidates == ["skill-1","skill-2","skill-3","skill-4","skill-5"]
  ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "disabled discovery suppresses candidates and question flow" {
  write_config false true false
  write_detector '["go"]' '["global-skill"]' '["project-skill"]' '["skill-a"]' '["skill-a"]'

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  run jq -e '
    .config == {
      auto_install_skills: true,
      discovery_questions: false,
      skill_suggestions: false
    }
    and .detected_stack == ["go"]
    and .installed.global == ["global-skill"]
    and .installed.project == ["project-skill"]
    and .candidates == []
    and .candidate_count == 0
    and .question_mode == "disabled"
  ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "human output names skill suggestions when only suggestions are disabled" {
  write_config false false true
  write_detector '["go"]' '[]' '[]' '[]' '["skill-a"]'

  run_skills list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Skill suggestions are disabled. No installation decision is requested.'* ]]
  [[ "$output" != *'Discovery questions are disabled.'* ]]
}

@test "human output names discovery questions when only questions are disabled" {
  write_config true false false
  write_detector '["go"]' '[]' '[]' '[]' '["skill-a"]'

  run_skills list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Discovery questions are disabled. No installation decision is requested.'* ]]
  [[ "$output" != *'Skill suggestions are disabled.'* ]]
}

@test "search filters discovered candidates without a registry or network request" {
  write_detector '["python"]' '[]' '[]' '[]' '["lint-python","python-tests","rust-tests"]'

  run_skills --json search "$PROJECT_ROOT" 'PYTHON'

  [ "$status" -eq 0 ]
  run jq -e '
    .operation == "search"
    and .query == "PYTHON"
    and .candidates == ["lint-python","python-tests"]
    and .candidate_count == 2
    and .question_mode == "bounded"
  ' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "malformed detector output fails closed" {
  printf '%s\n' '{"suggestions":"not-an-array"}' > "$DETECTOR_RESPONSE"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'detector output is not a valid LBWC stack result'* ]]
}

@test "invalid JSON configuration fails closed" {
  printf '%s\n' '{' > "$PLANNING_DIR/config.json"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'skill discovery configuration is invalid'* ]]
}

@test "non-object configuration fails closed" {
  printf '%s\n' '[]' > "$PLANNING_DIR/config.json"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'skill discovery configuration is invalid'* ]]
}

@test "non-boolean discovery setting fails closed" {
  printf '%s\n' '{"skill_suggestions":"yes"}' > "$PLANNING_DIR/config.json"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'skill discovery configuration is invalid'* ]]
}

@test "symbolic link configuration fails closed" {
  external_config="$TEST_ROOT/external-config.json"
  mv "$PLANNING_DIR/config.json" "$external_config"
  ln -s "$external_config" "$PLANNING_DIR/config.json"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'configuration must not be a symbolic link'* ]]
}

@test "dangling symbolic link configuration fails closed before defaults" {
  rm "$PLANNING_DIR/config.json"
  ln -s "$TEST_ROOT/missing-config.json" "$PLANNING_DIR/config.json"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'configuration must not be a symbolic link'* ]]
}

@test "symbolic link detector fails closed" {
  external_detector="$TEST_ROOT/external-detector.sh"
  mv "$PLUGIN_ROOT/scripts/detect-stack.sh" "$external_detector"
  ln -s "$external_detector" "$PLUGIN_ROOT/scripts/detect-stack.sh"

  run_skills --json list "$PROJECT_ROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *'stack detector must not be a symbolic link'* ]]
}

@test "symbolic project argument is resolved before detector use" {
  linked_project="$TEST_ROOT/project-link"
  ln -s "$PROJECT_ROOT" "$linked_project"
  expected_root=$(cd -P "$PROJECT_ROOT" && pwd -P)

  run_skills --json list "$linked_project"

  [ "$status" -eq 0 ]
  [ "$(cat "$DETECTOR_TRACE")" = "$expected_root" ]
}

@test "explicit install validates the candidate and refuses noninteractive mutation" {
  write_detector '["python"]' '[]' '[]' '["safe-skill"]' '["safe-skill"]'

  run_skills --json install "$PROJECT_ROOT" safe-skill

  [ "$status" -ne 0 ]
  [ "$output" = '{"candidate":"safe-skill","operation":"install","reason":"external_installation_not_authorized","status":"blocked"}' ]
  [ ! -e "$PROJECT_ROOT/.claude/skills" ]
}

@test "install rejects a value that was not discovered" {
  write_detector '["python"]' '[]' '[]' '[]' '["safe-skill"]'

  run_skills --json install "$PROJECT_ROOT" other-skill

  [ "$status" -ne 0 ]
  [[ "$output" == *'skill is not an exact discovered candidate: other-skill'* ]]
  [ ! -e "$PROJECT_ROOT/.claude/skills" ]
}

@test "human tables preserve ordinary text and escape control and table characters" {
  write_detector \
    '["letter-u"]' \
    '[]' \
    '[]' \
    '[]' \
    '["safe|name","letter-u","\u001b]0;owned\u0007"]'

  run_skills list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *'| Detected stack | letter-u |'* ]]
  [[ "$output" == *'| 2 | letter-u |'* ]]
  [[ "$output" == *'| 3 | safe\|name |'* ]]
  [[ "$output" == *'| 1 | ?]0;owned? |'* ]]
  [[ "$output" != *$'\e'* ]]
  [[ "$output" != *$'\a'* ]]
}

@test "human tables replace embedded LF and CR without creating extra rows" {
  write_detector \
    '["line\nbreak","carriage\rreturn"]' \
    '[]' \
    '[]' \
    '[]' \
    '["line\nbreak","carriage\rreturn"]'

  run_skills list "$PROJECT_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *'carriage?return'* ]]
  [[ "$output" == *'line?break'* ]]
  [[ "$output" != *$'carriage\rreturn'* ]]
  [[ "$output" != *$'line\nbreak'* ]]
}

@test "skills command keeps installation consent in the main session" {
  COMMAND="$REPO_ROOT/commands/skills.md"

  run grep -F 'name: lbwc:skills' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F 'allowed-tools:' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '  - Read' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '  - AskUserQuestion' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '  - Bash("${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" *)' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F 'main session only' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F 'A generated agent or subagent must not run this flow' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '`category` is LBWC project metadata' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F 'Options:' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '1. Skip all' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F '2. Show the table again' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -F 'Use native Other to type comma-separated numbers' "$COMMAND"
  [ "$status" -eq 0 ]
  run grep -E 'npx skills add|allowed-tools:.*(WebFetch|WebSearch|Agent)|bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/lbwc-skills\.sh"|\.vbw-planning' "$COMMAND"
  [ "$status" -ne 0 ]
}
