#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS_DIR=$(cd "$TESTS_DIR/.." && pwd)
PLUGIN_ROOT=$(cd "$SCRIPTS_DIR/.." && pwd)
WORK_ROOT=$(mktemp -d)
PLUGIN_FIXTURE="$WORK_ROOT/plugin"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

mkdir -p "$PLUGIN_FIXTURE"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/config" "$PLUGIN_FIXTURE/"

GENERATOR="$PLUGIN_FIXTURE/scripts/agent-generator.sh"
TASK_CONTRACT="$PLUGIN_FIXTURE/scripts/task-contract.sh"
ROLE_DEFAULTS="$PLUGIN_FIXTURE/templates/agent-roles/defaults.json"
GENERATOR_BASH=""
for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash \
  "$(command -v bash 2>/dev/null || true)"; do
  if [ -x "$candidate" ] && "$candidate" -uc 'declare -A test=()' >/dev/null 2>&1; then
    GENERATOR_BASH="$candidate"
    break
  fi
done
[ -n "$GENERATOR_BASH" ] || { printf 'Bash 4+ is required to run agent-generator.sh\n' >&2; exit 1; }
PASS=0
FAIL=0
CONTRACT_SEQUENCE=0
RUN_OUTPUT=""
RUN_RC=0

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

check_test() {
  local description="$1"
  shift
  if test "$@"; then
    check "$description" 0
  else
    check "$description" 1
  fi
}

new_project() {
  local dir binary sha
  dir=$(mktemp -d "$WORK_ROOT/project.XXXXXX")
  mkdir -p "$dir/.lbwc-planning"
  binary="$dir/claude-generator-fixture"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "fixture"' > "$binary"
  chmod +x "$binary"
  sha=$(shasum -a 256 "$binary" | awk '{print $1}')
  jq -n --arg binary "$binary" --arg sha "$sha" '
    {
      schema_version: 1,
      source: {binary_path: $binary, version: "fixture", sha256: $sha, detected_at: "2035-01-02T03:04:05Z"},
      models: [
        {selector: "nova-route", label: "Nova Route", description: "Fixture selector"},
        {selector: "ember-path", label: "Ember Path", description: "Second fixture selector"}
      ],
      reasoning: {
        scope: "global",
        accepted_values: ["deliberate", "swift"],
        model_associations: {"nova-route": ["deliberate"]}
      }
    }
  ' > "$dir/.lbwc-planning/claude-capabilities.json"
  jq --slurpfile defaults "$ROLE_DEFAULTS" '
    . + {
      schema_version: 1,
      routing: {
        active_profile: "balanced",
        profiles: {
          quality: {roles: {}},
          balanced: {
            roles: ($defaults[0] | keys | map({key: ., value: {model: "nova-route", reasoning: "deliberate", status: "resolved"}}) | from_entries)
          },
          turbo: {roles: {}}
        }
      }
    }
  ' "$PLUGIN_FIXTURE/config/settings.json" > "$dir/.lbwc-planning/config.json"
  printf '%s\n' "$dir"
}

manifest_of() {
  jq -c '.' "$1/.lbwc-planning/.agent-manifest.json" 2>/dev/null || printf '{"agents":{}}\n'
}

run_generator() {
  local project="$1" mode="$2" role="$3" job="$4" contract task_id
  local -a generator_args=()
  shift 4
  CONTRACT_SEQUENCE=$((CONTRACT_SEQUENCE + 1))
  task_id="core-$CONTRACT_SEQUENCE"
  contract=$(bash "$TASK_CONTRACT" issue "$project" "$task_id" \
    --command integration-test --role "$role" --team "$mode" --job "$job")
  case "$mode" in
    pair) generator_args+=(--pair) ;;
    trio) generator_args+=(--trio) ;;
  esac
  generator_args+=("$role" --job "$job" \
    --contract "$contract" --task-id "$(basename "$contract" .json)" "$@")
  RUN_OUTPUT=$(cd "$project" && PATH="$(dirname "$GENERATOR_BASH"):$PATH" \
    LBWC_AGENT_RANDOM_SEED="$CONTRACT_SEQUENCE" \
    "$GENERATOR_BASH" "$GENERATOR" "${generator_args[@]}" 2>&1)
  RUN_RC=$?
}

check_test "legacy model-pricing.json is absent from the integration fixture" ! -e "$PLUGIN_FIXTURE/config/model-pricing.json"
check_test "legacy model-profiles.json is absent from the integration fixture" ! -e "$PLUGIN_FIXTURE/config/model-profiles.json"

PROJECT_A=$(new_project)
run_generator "$PROJECT_A" pair coding-dijkstra "add a binary search"
check "pair mode exits 0 with catalog-backed routing" "$RUN_RC"
MANIFEST_A=$(manifest_of "$PROJECT_A")
PAIR_COUNT=$(jq '[.agents[] | select(.pair_id != null)] | group_by(.pair_id) | length' <<< "$MANIFEST_A")
ONE_GROUP_OF_TWO=$(jq '[.agents[] | select(.pair_id != null)] | group_by(.pair_id) | map(length) | .[0] // 0' <<< "$MANIFEST_A")
ENGINEER_PRESENT=$(jq '[.agents[] | select(.pair_role == "engineer")] | length' <<< "$MANIFEST_A")
CRITIC_PRESENT=$(jq '[.agents[] | select(.pair_role == "critic")] | length' <<< "$MANIFEST_A")
check_test "pair mode creates exactly one pair_id group" "$PAIR_COUNT" = "1"
check_test "the pair_id group has both halves" "$ONE_GROUP_OF_TWO" = "2"
check_test "one entry is pair_role=engineer" "$ENGINEER_PRESENT" = "1"
check_test "one entry is pair_role=critic" "$CRITIC_PRESENT" = "1"
grep -q '^ENGINEER: SPAWN_READY' <<< "$RUN_OUTPUT"; check "prints ENGINEER: SPAWN_READY line" "$?"
grep -q '^CRITIC: SPAWN_READY' <<< "$RUN_OUTPUT"; check "prints CRITIC: SPAWN_READY line" "$?"

PROJECT_B=$(new_project)
STALE_TS=$(date -u -v-2H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ")
STALE_MANIFEST=$(jq -n --arg ts "$STALE_TS" '
  {agents: (
    ["a","b","c","d"] | map({
      (.): {name: ., role: "lead", project_root: "/tmp", definition_path: "/tmp/x.md",
            state: "registered", created_at: $ts, model: "nova-route", effort: "deliberate",
            max_turns: "", overrides: {}, pair_id: null, pair_role: null}
    }) | add
  )}
')
printf '%s\n' "$STALE_MANIFEST" > "$PROJECT_B/.lbwc-planning/.agent-manifest.json"
run_generator "$PROJECT_B" solo lead "write a phase plan"
check "generation succeeds when only stale registered entries exist" "$RUN_RC"
grep -q 'SPAWN_READY' <<< "$RUN_OUTPUT"; check "stale-entry case prints SPAWN_READY" "$?"

PROJECT_B2=$(new_project)
FRESH_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LIVE_MANIFEST=$(jq -n --arg ts "$FRESH_TS" '
  {agents: (
    ["a","b","c","d"] | map({
      (.): {name: ., role: "lead", project_root: "/tmp", definition_path: "/tmp/x.md",
            state: "running", created_at: $ts, model: "nova-route", effort: "deliberate",
            max_turns: "", overrides: {}, pair_id: null, pair_role: null}
    }) | add
  )}
')
printf '%s\n' "$LIVE_MANIFEST" > "$PROJECT_B2/.lbwc-planning/.agent-manifest.json"
run_generator "$PROJECT_B2" solo lead "write a phase plan"
check_test "generation is refused when 4 agents are already running" "$RUN_RC" -ne 0
grep -qi 'cap' <<< "$RUN_OUTPUT"; check "cap-refusal message mentions the cap" "$?"

PROJECT_C=$(new_project)
BEFORE_FILES=$(find "$PROJECT_C/.claude/agents" -type f 2>/dev/null | wc -l | tr -d ' ')
run_generator "$PROJECT_C" solo coding-dijkstra "add a sort routine" --model definitely-not-a-registered-model
AFTER_FILES=$(find "$PROJECT_C/.claude/agents" -type f 2>/dev/null | wc -l | tr -d ' ')
MANIFEST_C=$(manifest_of "$PROJECT_C")
AGENT_COUNT_C=$(jq '.agents | length' <<< "$MANIFEST_C")
check_test "unknown model id exits non-zero" "$RUN_RC" -ne 0
check_test "unknown model id writes no agent file" "$BEFORE_FILES" = "$AFTER_FILES"
check_test "unknown model id writes no manifest entry" "$AGENT_COUNT_C" = "0"
grep -qi 'not present' <<< "$RUN_OUTPUT"; check "error message names the missing catalog selector" "$?"

for selector in nova-route ember-path; do
  PROJECT_D=$(new_project)
  run_generator "$PROJECT_D" solo docs "check $selector" --model "$selector" --reasoning swift
  check_test "catalog selector '$selector' resolves cleanly" "$RUN_RC" -eq 0
  jq -e --arg model "$selector" '.agents[] | .model == $model and .effort == "swift"' \
    "$PROJECT_D/.lbwc-planning/.agent-manifest.json" >/dev/null
  check "catalog selector '$selector' preserves exact reasoning" "$?"
done

PROJECT_E=$(new_project)
rm "$PROJECT_E/.lbwc-planning/config.json"
run_generator "$PROJECT_E" solo docs "write without routing config"
check_test "generation fails closed without routing config" "$RUN_RC" -ne 0
check_test "agent-generator does not auto-create config.json" ! -f "$PROJECT_E/.lbwc-planning/config.json"

PROJECT_F=$(new_project)
jq '.routing.profiles.balanced.roles.architect = {model: "ember-path", reasoning: "swift", status: "resolved"}' \
  "$PROJECT_F/.lbwc-planning/config.json" > "$PROJECT_F/.lbwc-planning/config.next"
mv "$PROJECT_F/.lbwc-planning/config.next" "$PROJECT_F/.lbwc-planning/config.json"
run_generator "$PROJECT_F" solo architect "preserve exact routing"
check "catalog-backed generation succeeds for exact route" "$RUN_RC"
NAME_F=$(jq -r '.agents | keys[0]' "$PROJECT_F/.lbwc-planning/.agent-manifest.json")
jq -e --arg name "$NAME_F" '.agents[$name].model == "ember-path" and .agents[$name].effort == "swift"' \
  "$PROJECT_F/.lbwc-planning/.agent-manifest.json" >/dev/null
check "manifest preserves the exact selector and effort" "$?"
grep -F 'model: "ember-path"' "$PROJECT_F/.claude/agents/$NAME_F.md" >/dev/null
check "generated frontmatter preserves the exact selector" "$?"
grep -F 'effort: "swift"' "$PROJECT_F/.claude/agents/$NAME_F.md" >/dev/null
check "generated frontmatter preserves the exact effort" "$?"

PROJECT_G=$(new_project)
jq '.routing.profiles.balanced.roles.docs.reasoning = null' \
  "$PROJECT_G/.lbwc-planning/config.json" > "$PROJECT_G/.lbwc-planning/config.next"
mv "$PROJECT_G/.lbwc-planning/config.next" "$PROJECT_G/.lbwc-planning/config.json"
run_generator "$PROJECT_G" solo docs "omit structural default reasoning"
check "catalog-backed generation accepts null reasoning" "$RUN_RC"
NAME_G=$(jq -r '.agents | keys[0]' "$PROJECT_G/.lbwc-planning/.agent-manifest.json")
! grep -q '^effort:' "$PROJECT_G/.claude/agents/$NAME_G.md"
check "generated frontmatter omits null effort" "$?"
jq -e --arg name "$NAME_G" '.agents[$name].effort == null' \
  "$PROJECT_G/.lbwc-planning/.agent-manifest.json" >/dev/null
check "manifest stores structural default reasoning as null" "$?"

PROJECT_H=$(new_project)
CONTROL_ROOT_H="$PROJECT_H/.temporary-agent-runfiles/runs/tmux-selection"
mkdir -p "$CONTROL_ROOT_H"
CONTRACT_H=$(bash "$TASK_CONTRACT" issue "$PROJECT_H" core-tmux-selection \
  --command integration-test --role web-engineer --team solo --job "run in tmux" \
  --control-root "$CONTROL_ROOT_H" --requested-backend tmux --resolved-backend tmux \
  --write-capability directory:src/web)
RUN_OUTPUT=$(cd "$PROJECT_H" && PATH="$(dirname "$GENERATOR_BASH"):$PATH" \
  LBWC_AGENT_RANDOM_SEED=42 \
  "$GENERATOR_BASH" "$GENERATOR" web-engineer --job "run in tmux" \
    --contract "$CONTRACT_H" --task-id "$(basename "$CONTRACT_H" .json)" \
    --control-root "$CONTROL_ROOT_H" --write-capability directory:src/web \
    --execution-backend tmux 2>&1)
RUN_RC=$?
check "schema 3 tmux runtime selection generates an agent" "$RUN_RC"
NAME_H=$(jq -r '.agents | keys[0] // empty' "$CONTROL_ROOT_H/agent-manifest.json" 2>/dev/null)
jq -e --arg name "$NAME_H" '
  .agents[$name].execution.requested_backend == "tmux"
  and .agents[$name].execution.resolved_backend == "tmux"
  and .agents[$name].execution.role == .agents[$name].role
  and .agents[$name].execution.model == .agents[$name].model
  and .agents[$name].execution.effort == .agents[$name].effort
  and .agents[$name].execution.max_turns == .agents[$name].max_turns
  and .agents[$name].execution.contract_id == .agents[$name].contract_id
  and .agents[$name].execution.contract_digest == .agents[$name].contract_digest
  and .agents[$name].execution.task_identity == .agents[$name].task_identity
  and .agents[$name].execution.tmux_bootstrap.child_identity == $name
  and .agents[$name].execution.tmux_bootstrap.contract_id == .agents[$name].contract_id
  and .agents[$name].execution.tmux_bootstrap.control_root == .agents[$name].control_root
' "$CONTROL_ROOT_H/agent-manifest.json" >/dev/null
check "schema 3 tmux metadata and bootstrap have no drift" "$?"
grep -q '## TMUX bus loop' "$PROJECT_H/.claude/agents/$NAME_H.md"
check "schema 3 tmux definition includes the bus loop" "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
