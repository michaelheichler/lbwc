#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export LBWC_PLANNING_DIR="$TEST_TEMP_DIR/.lbwc-planning"
  export EVIDENCE_SCRIPT="$SCRIPTS_DIR/agent-routing-evidence.sh"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

run_evidence() {
  local command="$1" input="$2"
  run bash -c 'printf "%s\n" "$1" | LBWC_PLANNING_DIR="$2" bash "$3" "$4"' \
    _ "$input" "$LBWC_PLANNING_DIR" "$EVIDENCE_SCRIPT" "$command"
}

@test "routing evidence records a resolved route and transcript match" {
  local script_dir="$TEST_TEMP_DIR/scripts" transcript record
  mkdir -p "$script_dir"
  cp "$SCRIPTS_DIR/agent-routing-evidence.sh" "$script_dir/agent-routing-evidence.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "{\"model\":\"claude-sonnet-5\",\"reasoning\":\"high\",\"role\":\"dev\"}"' > "$script_dir/lbwc-routing.sh"
  chmod +x "$script_dir/lbwc-routing.sh"
  export EVIDENCE_SCRIPT="$script_dir/agent-routing-evidence.sh"
  transcript="$TEST_TEMP_DIR/subagent.jsonl"
  printf '%s\n' '{"type":"assistant","effort":"high","message":{"model":"claude-sonnet-5","content":[]}}' > "$transcript"

  run_evidence start '{"agent_type":"dev","agent_id":"agent-1"}'
  [ "$status" -eq 0 ]
  run_evidence stop "{\"agent_type\":\"dev\",\"agent_id\":\"agent-1\",\"agent_transcript_path\":\"$transcript\"}"
  [ "$status" -eq 0 ]

  record=$(jq -s '[.[] | select(.event == "stop")][0]' "$LBWC_PLANNING_DIR/.agent-routing-evidence.jsonl")
  [ "$(jq -r '.verdict.model' <<< "$record")" = "pass" ]
  [ "$(jq -r '.verdict.effort' <<< "$record")" = "pass" ]
}

@test "routing evidence reports a transcript model mismatch" {
  local script_dir="$TEST_TEMP_DIR/scripts" transcript
  mkdir -p "$script_dir"
  cp "$SCRIPTS_DIR/agent-routing-evidence.sh" "$script_dir/agent-routing-evidence.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "{\"model\":\"claude-sonnet-5\",\"reasoning\":null,\"role\":\"dev\"}"' > "$script_dir/lbwc-routing.sh"
  chmod +x "$script_dir/lbwc-routing.sh"
  export EVIDENCE_SCRIPT="$script_dir/agent-routing-evidence.sh"
  transcript="$TEST_TEMP_DIR/subagent.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","content":[]}}' > "$transcript"

  run_evidence start '{"agent_type":"dev","agent_id":"agent-1"}'
  run_evidence stop "{\"agent_type\":\"dev\",\"agent_id\":\"agent-1\",\"agent_transcript_path\":\"$transcript\"}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent routing evidence mismatch for dev"* ]]
}
