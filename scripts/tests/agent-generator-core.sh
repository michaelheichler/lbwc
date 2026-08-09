#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR=$(cd "$TESTS_DIR/.." && pwd)
GENERATOR="$SCRIPTS_DIR/agent-generator.sh"

PASS=0
FAIL=0

check() {
  local description="$1" condition="$2"
  if [ "$condition" -eq 0 ]; then
    printf 'PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n' "$description"
    FAIL=$((FAIL + 1))
  fi
}

new_project() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.lbwc-planning"
  printf '{}\n' > "$dir/.lbwc-planning/config.json"
  printf '%s\n' "$dir"
}

manifest_of() {
  cat "$1/.lbwc-planning/.agent-manifest.json" 2>/dev/null || printf '{"agents":{}}'
}

PROJECT_A=$(new_project)
OUT_A=$(cd "$PROJECT_A" && bash "$GENERATOR" --pair coding-dijkstra --job "add a binary search" --model sonnet 2>&1)
RC_A=$?
check "pair mode exits 0" "$RC_A"

MANIFEST_A=$(manifest_of "$PROJECT_A")
PAIR_COUNT=$(jq '[.agents[] | select(.pair_id != null)] | group_by(.pair_id) | length' <<< "$MANIFEST_A")
ONE_GROUP_OF_TWO=$(jq '[.agents[] | select(.pair_id != null)] | group_by(.pair_id) | map(length) | .[0] // 0' <<< "$MANIFEST_A")
ENGINEER_PRESENT=$(jq '[.agents[] | select(.pair_role == "engineer")] | length' <<< "$MANIFEST_A")
CRITIC_PRESENT=$(jq '[.agents[] | select(.pair_role == "critic")] | length' <<< "$MANIFEST_A")

[ "$PAIR_COUNT" = "1" ]; check "pair mode creates exactly one pair_id group" "$?"
[ "$ONE_GROUP_OF_TWO" = "2" ]; check "the pair_id group has both halves" "$?"
[ "$ENGINEER_PRESENT" = "1" ]; check "one entry is pair_role=engineer" "$?"
[ "$CRITIC_PRESENT" = "1" ]; check "one entry is pair_role=critic" "$?"
grep -q '^ENGINEER: SPAWN_READY' <<< "$OUT_A"; check "prints ENGINEER: SPAWN_READY line" "$?"
grep -q '^CRITIC: SPAWN_READY' <<< "$OUT_A"; check "prints CRITIC: SPAWN_READY line" "$?"

PROJECT_B=$(new_project)
STALE_TS=$(date -u -v-2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
STALE_MANIFEST=$(jq -n --arg ts "$STALE_TS" '
  {agents: (
    ["a","b","c","d"] | map({
      (.): {name: ., role: "lead", project_root: "/tmp", definition_path: "/tmp/x.md",
            state: "registered", created_at: $ts, model: "claude-sonnet-5", effort: "",
            max_turns: "", overrides: {}, pair_id: null, pair_role: null}
    }) | add
  )}
')
printf '%s\n' "$STALE_MANIFEST" > "$PROJECT_B/.lbwc-planning/.agent-manifest.json"
OUT_B=$(cd "$PROJECT_B" && bash "$GENERATOR" lead --job "write a phase plan" 2>&1)
RC_B=$?
check "generation succeeds when the only existing entries are stale (>1h) registered ones" "$RC_B"
grep -q 'SPAWN_READY' <<< "$OUT_B"; check "stale-entry case prints SPAWN_READY" "$?"

PROJECT_B2=$(new_project)
FRESH_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LIVE_MANIFEST=$(jq -n --arg ts "$FRESH_TS" '
  {agents: (
    ["a","b","c","d"] | map({
      (.): {name: ., role: "lead", project_root: "/tmp", definition_path: "/tmp/x.md",
            state: "running", created_at: $ts, model: "claude-sonnet-5", effort: "",
            max_turns: "", overrides: {}, pair_id: null, pair_role: null}
    }) | add
  )}
')
printf '%s\n' "$LIVE_MANIFEST" > "$PROJECT_B2/.lbwc-planning/.agent-manifest.json"
OUT_B2=$(cd "$PROJECT_B2" && bash "$GENERATOR" lead --job "write a phase plan" 2>&1)
RC_B2=$?
[ "$RC_B2" -ne 0 ]; check "generation is refused when 4 agents are already running" "$?"
grep -qi 'cap' <<< "$OUT_B2"; check "cap-refusal message mentions the cap" "$?"

PROJECT_C=$(new_project)
BEFORE_FILES=$(find "$PROJECT_C/.claude/agents" -type f 2>/dev/null | wc -l | tr -d ' ')
OUT_C=$(cd "$PROJECT_C" && bash "$GENERATOR" coding-dijkstra --job "add a sort routine" --model definitely-not-a-registered-model 2>&1)
RC_C=$?
AFTER_FILES=$(find "$PROJECT_C/.claude/agents" -type f 2>/dev/null | wc -l | tr -d ' ')
MANIFEST_C=$(manifest_of "$PROJECT_C")
AGENT_COUNT_C=$(jq '.agents | length' <<< "$MANIFEST_C")

[ "$RC_C" -ne 0 ]; check "unknown model id exits non-zero" "$?"
[ "$BEFORE_FILES" = "$AFTER_FILES" ]; check "unknown model id writes no agent file" "$?"
[ "$AGENT_COUNT_C" = "0" ]; check "unknown model id writes no manifest entry" "$?"
grep -qi 'unknown model' <<< "$OUT_C"; check "error message names the unknown model" "$?"

for alias in luna sol terra kimi3 elonmusk; do
  PROJECT_D=$(new_project)
  OUT_D=$(cd "$PROJECT_D" && bash "$GENERATOR" coding-dijkstra --job "check $alias" --model "$alias" 2>&1)
  RC_D=$?
  [ "$RC_D" -eq 0 ]; check "named model '$alias' resolves cleanly" "$?"
done

PROJECT_E=$(mktemp -d)
mkdir -p "$PROJECT_E/.lbwc-planning"
OUT_E=$(cd "$PROJECT_E" && bash "$GENERATOR" docs --job "write a README" 2>&1)
RC_E=$?
check "docs spawns solo without a pre-existing config.json" "$RC_E"
[ ! -f "$PROJECT_E/.lbwc-planning/config.json" ]; check "agent-generator no longer auto-creates config.json" "$?"

PROJECT_F=$(mktemp -d)
mkdir -p "$PROJECT_F/.lbwc-planning"
OUT_F=$(cd "$PROJECT_F" && bash "$GENERATOR" qa-author --job "write failing tests" 2>&1)
RC_F=$?
check "qa-author spawns solo" "$RC_F"
grep -q 'model: inherit' <<< "$OUT_F"; check "qa-author resolves to the inherit model" "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
