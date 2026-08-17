#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  SESSION=session-cancel
}

teardown() {
  teardown_temp_dir
}

guard() {
  local mode="$1"
  (cd "$PROJECT_ROOT" && python3 -m hooks.user_question_guard "$mode")
}

question_json() {
  jq -cn --arg cwd "$TEST_TEMP_DIR" --arg session "$SESSION" '{
    session_id:$session,
    cwd:$cwd,
    tool_name:"AskUserQuestion",
    tool_input:{
      questions:[{
        header:"Review pace",
        question:"Which review pace should this project use?",
        options:[
          {label:"Fast", description:"Finish the review sooner."},
          {label:"Careful", description:"Check each change in detail."}
        ]
      }]
    }
  }'
}

agent_json() {
  jq -cn --arg cwd "$TEST_TEMP_DIR" --arg session "$SESSION" '{
    session_id:$session,
    cwd:$cwd,
    tool_name:"Agent",
    tool_input:{subagent_type:"qa"}
  }'
}

@test "pending decision blocks orchestration and mutation" {
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(question_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(agent_json)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"A user decision is pending"* ]]
  [[ "$output" == *"orchestration"* ]]
}

@test "killed AskUserQuestion clears pending and resumes normally" {
  bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(question_json)" >/dev/null
  killed=$(question_json | jq '.tool_input = {} | .is_error = true')
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard posttool' _ "$PROJECT_ROOT" <<<"$killed"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(agent_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "killing QA after cancel leaves Agent unblocked" {
  bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(question_json)" >/dev/null
  bash -c 'cd "$1" && python3 -m hooks.user_question_guard stop' _ "$PROJECT_ROOT" <<<"$(jq -cn --arg cwd "$TEST_TEMP_DIR" --arg session "$SESSION" '{session_id:$session,cwd:$cwd}')" >/dev/null
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(agent_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard stop' _ "$PROJECT_ROOT" <<<"$(jq -cn --arg cwd "$TEST_TEMP_DIR" --arg session "$SESSION" '{session_id:$session,cwd:$cwd}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash -c 'cd "$1" && python3 -m hooks.user_question_guard pretool' _ "$PROJECT_ROOT" <<<"$(agent_json)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "question guard PreToolUse matcher covers Agent Skill and SendMessage" {
  matcher=$(jq -r '.hooks.PreToolUse[0].matcher' "$PROJECT_ROOT/hooks/hooks.json")
  [[ "$matcher" == *Agent* ]]
  [[ "$matcher" == *Skill* ]]
  [[ "$matcher" == *SendMessage* ]]
}
