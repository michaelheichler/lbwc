#!/usr/bin/env bash
set -u

command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
EVIDENCE_FILE="$PLANNING_DIR/.agent-routing-evidence.jsonl"
COMMAND="${1:-}"
INPUT=$(cat 2>/dev/null || true)

case "$COMMAND" in
  start|stop|check) ;;
  *) exit 0 ;;
esac

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date
}

agent_name() {
  printf '%s' "$INPUT" | jq -r '
    first(
      .agent_type, .agentType, .subagent_type, .subagentType,
      .name, .agent_name, .agentName,
      .tool_input.agent_type, .tool_input.agentType,
      .tool_input.subagent_type, .tool_input.subagentType,
      .tool_input.name, .tool_input.agent_name,
      .agent_id, .agentId
      | select(type == "string" and length > 0)
    ) // ""
  ' 2>/dev/null || printf ''
}

transcript_path() {
  printf '%s' "$INPUT" | jq -r '
    if (.agent_transcript_path? | type) == "string" then .agent_transcript_path
    elif (.agentTranscriptPath? | type) == "string" then .agentTranscriptPath
    else (.transcript_path // "") end
  ' 2>/dev/null || printf ''
}

transcript_path_field() {
  printf '%s' "$INPUT" | jq -r '
    if (.agent_transcript_path? | type) == "string" then "agent_transcript_path"
    elif (.agentTranscriptPath? | type) == "string" then "agentTranscriptPath"
    elif (.transcript_path? | type) == "string" then "transcript_path"
    else "" end
  ' 2>/dev/null || printf ''
}

config_hash() {
  local path="$PLANNING_DIR/config.json"
  [ -f "$path" ] || { printf 'missing'; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" 2>/dev/null | awk '{print $1}'
  else
    cksum "$path" 2>/dev/null | awk '{print $1}'
  fi
}

resolved_route() {
  local role="$1" route
  route=$(bash "$SCRIPT_DIR/lbwc-routing.sh" resolve "$PLANNING_DIR" "$role" 2>/dev/null) || route='{}'
  jq -c 'if type == "object" then . else {} end' <<< "$route" 2>/dev/null || printf '{}'
}

read_transcript_evidence() {
  local transcript="$1" models='[]' efforts='[]'
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    models=$(jq -s '[.[] | select(.type == "assistant") | .message.model? | strings] | unique' "$transcript" 2>/dev/null || printf '[]')
    efforts=$(jq -s '[.[] | [.effort?, .message.effort?][] | select((type == "string" and length > 0) or type == "number") | tostring] | unique' "$transcript" 2>/dev/null || printf '[]')
  fi
  jq -cn --argjson models "$models" --argjson efforts "$efforts" '{models:$models,efforts:$efforts}'
}

model_verdict() {
  local expected="$1" models="$2" override="$3"
  [ "$override" = true ] && { printf 'env_override'; return; }
  [ -n "$expected" ] || { printf 'unknown'; return; }
  [ "$(jq 'length' <<< "$models")" -eq 1 ] || { printf 'unknown'; return; }
  jq -e --arg expected "$expected" '.[0] == $expected or (.[0] | startswith($expected + "-"))' <<< "$models" >/dev/null 2>&1 && printf 'pass' || printf 'mismatch'
}

effort_verdict() {
  local expected="$1" efforts="$2" override="$3"
  [ "$override" = true ] && { printf 'env_override'; return; }
  [ -n "$expected" ] || { printf 'unknown'; return; }
  [ "$(jq 'length' <<< "$efforts")" -eq 1 ] || { printf 'unknown'; return; }
  jq -e --arg expected "$expected" '.[0] == $expected' <<< "$efforts" >/dev/null 2>&1 && printf 'pass' || printf 'mismatch'
}

start_evidence() {
  local name route record model_override=false effort_override=false
  name=$(agent_name)
  [ -n "$name" ] || return 0
  [ "${CLAUDE_CODE_SUBAGENT_MODEL+x}" = x ] && model_override=true
  [ "${CLAUDE_CODE_EFFORT_LEVEL+x}" = x ] && effort_override=true
  route=$(resolved_route "$name")
  record=$(jq -cn \
    --arg timestamp "$(now_iso)" \
    --arg name "$name" \
    --arg hash "$(config_hash)" \
    --argjson route "$route" \
    --argjson model_override "$model_override" \
    --argjson effort_override "$effort_override" \
    '{event:"start",timestamp:$timestamp,name:$name,requested:{requested_model:($route.model // null),requested_effort:($route.reasoning // null),route:$route,config_hash:$hash,env_override_model:$model_override,env_override_effort:$effort_override}}') || return 0
  mkdir -p "$PLANNING_DIR" 2>/dev/null || return 0
  printf '%s\n' "$record" >> "$EVIDENCE_FILE" 2>/dev/null || true
}

latest_start() {
  local name="$1"
  [ -f "$EVIDENCE_FILE" ] || { printf '{}'; return 0; }
  jq -sc --arg name "$name" '[.[] | select(.event == "start" and .name == $name) | .requested] | last // {}' "$EVIDENCE_FILE" 2>/dev/null || printf '{}'
}

build_stop_record() {
  local name="$1" agent_id="$2" transcript="$3" path_field="$4" requested="$5" models="$6" efforts="$7" model_result="$8" effort_result="$9"
  jq -cn \
    --arg timestamp "$(now_iso)" \
    --arg name "$name" \
    --arg agent_id "$agent_id" \
    --arg transcript "$transcript" \
    --arg transcript_field "$path_field" \
    --argjson requested "$requested" \
    --argjson models "$models" \
    --argjson efforts "$efforts" \
    --arg model_result "$model_result" \
    --arg effort_result "$effort_result" \
    '{event:"stop",timestamp:$timestamp,name:$name,agent_id:($agent_id | if length > 0 then . else null end),transcript_path:($transcript | if length > 0 then . else null end),transcript_path_field:($transcript_field | if length > 0 then . else null end),requested:$requested,observed:{models:$models,efforts:$efforts},verdict:{model:$model_result,effort:$effort_result}}'
}

stop_evidence() {
  local name start transcript path_field observed models efforts model_result effort_result record agent_id
  name=$(agent_name)
  [ -n "$name" ] || return 0
  start=$(latest_start "$name")
  transcript=$(transcript_path)
  path_field=$(transcript_path_field)
  observed=$(read_transcript_evidence "$transcript") || observed='{"models":[],"efforts":[]}'
  models=$(jq -c '.models' <<< "$observed")
  efforts=$(jq -c '.efforts' <<< "$observed")
  model_result=$(model_verdict "$(jq -r '.requested_model // empty' <<< "$start")" "$models" "$(jq -r '.env_override_model // false' <<< "$start")")
  effort_result=$(effort_verdict "$(jq -r '.requested_effort // empty' <<< "$start")" "$efforts" "$(jq -r '.env_override_effort // false' <<< "$start")")
  agent_id=$(printf '%s' "$INPUT" | jq -r '.agent_id // .agentId // ""' 2>/dev/null || true)
  record=$(build_stop_record "$name" "$agent_id" "$transcript" "$path_field" "$start" "$models" "$efforts" "$model_result" "$effort_result") || return 0
  mkdir -p "$PLANNING_DIR" 2>/dev/null || return 0
  printf '%s\n' "$record" >> "$EVIDENCE_FILE" 2>/dev/null || true
  case "$model_result:$effort_result" in
    mismatch:*|*:mismatch) jq -cn --arg context "Agent routing evidence mismatch for $name. Model=$model_result, effort=$effort_result." '{hookSpecificOutput:{hookEventName:"SubagentStop",additionalContext:$context}}' ;;
  esac
}

check_evidence() {
  local records model_count effort_count
  if [ ! -s "$EVIDENCE_FILE" ]; then
    printf 'Agent routing evidence: no records.\n'
    return 0
  fi
  records=$(jq -s '[.[] | select(.event == "stop")]' "$EVIDENCE_FILE" 2>/dev/null || printf '[]')
  printf 'Agent routing evidence: %s records\n' "$(jq 'length' <<< "$records")"
  for verdict in pass mismatch env_override unknown; do
    model_count=$(jq --arg verdict "$verdict" '[.[] | select(.verdict.model == $verdict)] | length' <<< "$records")
    effort_count=$(jq --arg verdict "$verdict" '[.[] | select(.verdict.effort == $verdict)] | length' <<< "$records")
    printf '  %-12s model=%s effort=%s\n' "$verdict" "$model_count" "$effort_count"
  done
}

case "$COMMAND" in
  start) start_evidence ;;
  stop) stop_evidence ;;
  check) check_evidence ;;
esac
