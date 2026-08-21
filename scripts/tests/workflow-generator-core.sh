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

AGENT_GENERATOR="$PLUGIN_FIXTURE/scripts/agent-generator.sh"
WORKFLOW_GENERATOR="$PLUGIN_FIXTURE/scripts/workflow-generator.sh"
TASK_CONTRACT="$PLUGIN_FIXTURE/scripts/task-contract.sh"

GENERATOR_BASH=""
for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash \
  "$(command -v bash 2>/dev/null || true)"; do
  if [ -x "$candidate" ] && "$candidate" -uc 'declare -A test=()' >/dev/null 2>&1; then
    GENERATOR_BASH="$candidate"
    break
  fi
done
[ -n "$GENERATOR_BASH" ] || { printf 'Bash 4+ is required to run workflow-generator.sh\n' >&2; exit 1; }

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
  local dir
  dir=$(mktemp -d "$WORK_ROOT/project.XXXXXX")
  mkdir -p "$dir/.lbwc-planning"
  printf '%s\n' "$dir"
}

new_control_root() {
  local project="$1" run_id="$2" control_root roles_json
  shift 2
  control_root="$project/.temporary-agent-runfiles/runs/$run_id"
  mkdir -p "$control_root"
  roles_json='{}'
  while [ "$#" -ge 3 ]; do
    roles_json=$(jq -c --arg r "$1" --arg m "$2" --arg e "$3" '. + {($r): {model:$m, reasoning:$e, status:"resolved"}}' <<< "$roles_json")
    shift 3
  done
  jq -n --argjson roles "$roles_json" '{schema_version:1, routing_source:"temporary-control-root", routing:{active_profile:"balanced", profiles:{balanced:{roles:$roles}}}}' \
    > "$control_root/routing.json"
  jq -n '{workflow_execution:{enabled:true}}' > "$control_root/config.json"
  jq -n '{workflow:{available:true, unavailable_reasons:[]}}' > "$control_root/claude-capabilities.json"
  printf '%s\n' "$control_root"
}

run_with_modern_bash() {
  PATH="$(dirname "$GENERATOR_BASH"):$PATH" "$GENERATOR_BASH" "$@"
}

engineer_name_from_output() {
  printf '%s\n' "$1" | grep '^ENGINEER: SPAWN_READY' | awk '{print $3}'
}

critic_name_from_output() {
  printf '%s\n' "$1" | grep '^CRITIC: SPAWN_READY' | awk '{print $3}'
}

nth_spawn_ready_name() {
  printf '%s\n' "$1" | grep 'SPAWN_READY' | sed -n "${2}p" | awk '{print $NF}'
}

forbidden_token_confined_to_known_lines() {
  local file="$1" forbidden="$2" leaked
  leaked=$(grep -Fn "$forbidden" "$file" | grep -v '^1:' | grep -v 'const JOB = ')
  [ -z "$leaked" ]
}

ADVERSARIAL_JOB=$'evil "job" with \\ backslash\nnewline `backtick` ${evil} and */ close-comment mentions import and require( and Date.now and Math.random too @@JOB@@'

PROJECT_A=$(new_project)
CONTROL_ROOT_A=$(new_control_root "$PROJECT_A" wf-pair \
  web-engineer nova-route balanced \
  web-code-critic nova-route fast)

CONTRACT_A=$(bash "$TASK_CONTRACT" issue "$PROJECT_A" pair-1 \
  --command integration-test --role web-engineer --team pair --job "$ADVERSARIAL_JOB" \
  --group fixed \
  --control-root "$CONTROL_ROOT_A" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:src)
TASK_ID_A=$(basename "$CONTRACT_A" .json)

AGEN_OUTPUT_A=$(LBWC_AGENT_RANDOM_SEED=101 run_with_modern_bash "$AGENT_GENERATOR" --pair web-engineer \
  --job "$ADVERSARIAL_JOB" --contract "$CONTRACT_A" --task-id "$TASK_ID_A" \
  --control-root "$CONTROL_ROOT_A" --write-capability directory:src \
  --execution-backend workflow 2>&1)
AGEN_RC_A=$?
check "agent-generator mints a real workflow-backend pair" "$AGEN_RC_A"

ENGINEER_A=$(engineer_name_from_output "$AGEN_OUTPUT_A")
CRITIC_A=$(critic_name_from_output "$AGEN_OUTPUT_A")
check_test "SPAWN_READY output names an engineer" -n "$ENGINEER_A"
check_test "SPAWN_READY output names a critic" -n "$CRITIC_A"

WGEN_OUTPUT_A=$(run_with_modern_bash "$WORKFLOW_GENERATOR" pair web-engineer \
  --job "$ADVERSARIAL_JOB" --contract "$CONTRACT_A" --task-id "$TASK_ID_A" \
  --control-root "$CONTROL_ROOT_A" --autonomy standard \
  --engineer-name "$ENGINEER_A" --critic-name "$CRITIC_A" 2>&1)
WGEN_RC_A=$?
check "workflow-generator accepts the fed SPAWN_READY names" "$WGEN_RC_A"
grep -q '^WORKFLOW_READY' <<< "$WGEN_OUTPUT_A"; check "prints a WORKFLOW_READY line" "$?"

SCRIPT_A="$CONTROL_ROOT_A/workflows/$TASK_ID_A.js"
check_test "the rendered workflow script exists" -f "$SCRIPT_A"

META_LINE_A=$(head -n1 "$SCRIPT_A")
META_JSON_A=${META_LINE_A#"export const meta = "}
META_JSON_A=${META_JSON_A%";"}
jq -e . <<< "$META_JSON_A" >/dev/null 2>&1
check "line 1 parses as JSON through jq -e" "$?"

BODY_PHASES_A=$(tail -n +2 "$SCRIPT_A" | grep -oE 'phase\("[^"]*"\)' | sed -E 's/^phase\("//; s/"\)$//' | jq -Rcs 'split("\n") | map(select(length > 0))')
META_PHASES_A=$(jq -c '.phases' <<< "$META_JSON_A")
check_test "every phase() title matches meta.phases" "$BODY_PHASES_A" = "$META_PHASES_A"

for forbidden in import 'require(' 'Date.now' 'Math.random'; do
  grep -qF "$forbidden" "$SCRIPT_A"
  check "adversarial job mentioning '$forbidden' still lets generation succeed" "$?"
done
check_test "adversarial job round-trips through the JOB constant, forbidden words included" \
  "$(grep -c 'mentions import and require( and Date.now and Math.random too' "$SCRIPT_A")" -ge 1

for forbidden in import 'require(' 'Date.now' 'Math.random'; do
  forbidden_token_confined_to_known_lines "$SCRIPT_A" "$forbidden"
  check "forbidden token '$forbidden' appears only inside the JOB constant or the meta line" "$?"
done

if command -v node >/dev/null 2>&1; then
  SYNTAX_WRAP="$WORK_ROOT/syntax-check.mjs"
  { printf '(async () => {\n'; tail -n +2 "$SCRIPT_A"; printf '\n})\n'; } > "$SYNTAX_WRAP"
  node --check --input-type=module - < "$SYNTAX_WRAP" >/dev/null 2>&1
  check "the rendered script passes node --check" "$?"
fi

WORKFLOW_MANIFEST_A="$CONTROL_ROOT_A/workflow-manifest.json"
REGISTERED_ARGS_DIGEST_A=$(jq -r --arg id "$TASK_ID_A" '.workflows[$id].args_digest // empty' "$WORKFLOW_MANIFEST_A")
EXPECTED_ARGS_DIGEST=$(printf 'null' | shasum -a 256 | awk '{print $1}')
check_test "the registered args_digest is pinned to sha256(\"null\")" "$REGISTERED_ARGS_DIGEST_A" = "$EXPECTED_ARGS_DIGEST"

WGEN_UNREGISTERED=$(run_with_modern_bash "$WORKFLOW_GENERATOR" pair web-engineer \
  --job "$ADVERSARIAL_JOB" --contract "$CONTRACT_A" --task-id "$TASK_ID_A" \
  --control-root "$CONTROL_ROOT_A" --autonomy standard \
  --engineer-name "lbwc-web-engineer-bogus-bogus-bogus" --critic-name "$CRITIC_A" 2>&1)
check_test "a name absent from the manifest is refused" "$?" -ne 0
grep -qi 'not registered' <<< "$WGEN_UNREGISTERED"; check "the refusal names the missing manifest entry" "$?"

WGEN_TAMPERED=$(run_with_modern_bash "$WORKFLOW_GENERATOR" pair web-engineer \
  --job "tampered job text, not what the contract was issued for" --contract "$CONTRACT_A" --task-id "$TASK_ID_A" \
  --control-root "$CONTROL_ROOT_A" --autonomy standard \
  --engineer-name "$ENGINEER_A" --critic-name "$CRITIC_A" 2>&1)
check_test "tampered job text is refused" "$?" -ne 0
grep -qi 'job digest mismatch' <<< "$WGEN_TAMPERED"; check "the refusal names the job digest mismatch" "$?"

SCRIPT_A_BEFORE_RETRY=$(cat "$SCRIPT_A")
run_with_modern_bash "$WORKFLOW_GENERATOR" pair web-engineer \
  --job "$ADVERSARIAL_JOB" --contract "$CONTRACT_A" --task-id "$TASK_ID_A" \
  --control-root "$CONTROL_ROOT_A" --autonomy standard \
  --engineer-name "$ENGINEER_A" --critic-name "$CRITIC_A" >/dev/null 2>&1
check_test "a duplicate generation for an already-registered contract is refused" "$?" -ne 0
check_test "the refused duplicate leaves the original script on disk" -f "$SCRIPT_A"
if [ -f "$SCRIPT_A" ]; then
  check_test "the refused duplicate does not alter the original script" "$(cat "$SCRIPT_A")" = "$SCRIPT_A_BEFORE_RETRY"
else
  check "the refused duplicate does not alter the original script" 1
fi

PROJECT_C=$(new_project)
CONTROL_ROOT_C=$(new_control_root "$PROJECT_C" wf-trio \
  web-engineer nova-route balanced \
  web-code-critic nova-route fast \
  test-dev nova-route thorough)
CONTRACT_C=$(bash "$TASK_CONTRACT" issue "$PROJECT_C" trio-1 \
  --command integration-test --role web-engineer --team trio --job "trio job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_C" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:src)
TASK_ID_C=$(basename "$CONTRACT_C" .json)

AGEN_OUTPUT_C=$(LBWC_AGENT_RANDOM_SEED=707 run_with_modern_bash "$AGENT_GENERATOR" --trio web-engineer \
  --job "trio job" --contract "$CONTRACT_C" --task-id "$TASK_ID_C" \
  --control-root "$CONTROL_ROOT_C" --write-capability directory:src \
  --execution-backend workflow 2>&1)
AGEN_RC_C=$?
check "agent-generator mints a real workflow-backend trio" "$AGEN_RC_C"

ENGINEER_C=$(nth_spawn_ready_name "$AGEN_OUTPUT_C" 1)
CRITIC_C=$(nth_spawn_ready_name "$AGEN_OUTPUT_C" 2)
TESTDEV_C=$(nth_spawn_ready_name "$AGEN_OUTPUT_C" 3)
check_test "SPAWN_READY output names a trio engineer" -n "$ENGINEER_C"
check_test "SPAWN_READY output names a trio critic" -n "$CRITIC_C"
check_test "SPAWN_READY output names a trio test-dev" -n "$TESTDEV_C"

WGEN_OUTPUT_C=$(run_with_modern_bash "$WORKFLOW_GENERATOR" trio web-engineer \
  --job "trio job" --contract "$CONTRACT_C" --task-id "$TASK_ID_C" \
  --control-root "$CONTROL_ROOT_C" --autonomy standard \
  --engineer-name "$ENGINEER_C" --critic-name "$CRITIC_C" --testdev-name "$TESTDEV_C" 2>&1)
check "workflow-generator accepts the fed trio SPAWN_READY names" "$?"
grep -q '^WORKFLOW_READY' <<< "$WGEN_OUTPUT_C"; check "trio generation prints a WORKFLOW_READY line" "$?"

SCRIPT_C="$CONTROL_ROOT_C/workflows/$TASK_ID_C.js"
check_test "the rendered trio workflow script exists" -f "$SCRIPT_C"
check_test "the rendered script names the engineer agent type" "$(grep -c "\"$ENGINEER_C\"" "$SCRIPT_C")" -ge 1
check_test "the rendered script names the critic agent type" "$(grep -c "\"$CRITIC_C\"" "$SCRIPT_C")" -ge 1
check_test "the rendered script names the test-dev agent type" "$(grep -c "\"$TESTDEV_C\"" "$SCRIPT_C")" -ge 1

ENGINEER_EFFORT_C=$(grep -m1 '^effort:' "$PROJECT_C/.claude/agents/$ENGINEER_C.md" | sed 's/^effort: "//; s/"$//')
CRITIC_EFFORT_C=$(grep -m1 '^effort:' "$PROJECT_C/.claude/agents/$CRITIC_C.md" | sed 's/^effort: "//; s/"$//')
TESTDEV_EFFORT_C=$(grep -m1 '^effort:' "$PROJECT_C/.claude/agents/$TESTDEV_C.md" | sed 's/^effort: "//; s/"$//')
check_test "each trio member resolved its own distinct effort" \
  "$ENGINEER_EFFORT_C:$CRITIC_EFFORT_C:$TESTDEV_EFFORT_C" = "balanced:fast:thorough"
check_test "the rendered script carries the engineer's own resolved effort" \
  "$(grep -c "const ENGINEER_EFFORT = \"$ENGINEER_EFFORT_C\";" "$SCRIPT_C")" -eq 1
check_test "the rendered script carries the critic's own resolved effort" \
  "$(grep -c "const CRITIC_EFFORT = \"$CRITIC_EFFORT_C\";" "$SCRIPT_C")" -eq 1
check_test "the rendered script carries the test-dev's own resolved effort" \
  "$(grep -c "const TESTDEV_EFFORT = \"$TESTDEV_EFFORT_C\";" "$SCRIPT_C")" -eq 1

WORKFLOW_MANIFEST_C="$CONTROL_ROOT_C/workflow-manifest.json"
ROSTER_C=$(jq -c --arg id "$TASK_ID_C" '.workflows[$id].roster // []' "$WORKFLOW_MANIFEST_C")
EXPECTED_ROSTER_C=$(jq -cn --arg e "$ENGINEER_C" --arg c "$CRITIC_C" --arg t "$TESTDEV_C" '[$e, $c, $t]')
check_test "the registered roster holds exactly the three trio names in order" "$ROSTER_C" = "$EXPECTED_ROSTER_C"

PROJECT_G=$(new_project)
CONTROL_ROOT_G=$(new_control_root "$PROJECT_G" wf-no-effort scout nova-route "")
CONTRACT_G=$(bash "$TASK_CONTRACT" issue "$PROJECT_G" effort-1 \
  --command integration-test --role scout --team solo --job "unresolved effort job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_G" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_G=$(basename "$CONTRACT_G" .json)
AGEN_OUT_G=$(LBWC_AGENT_RANDOM_SEED=808 run_with_modern_bash "$AGENT_GENERATOR" scout \
  --job "unresolved effort job" --contract "$CONTRACT_G" --task-id "$TASK_ID_G" \
  --control-root "$CONTROL_ROOT_G" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_G=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_G" | awk '{print $2}')
check_test "unresolved-effort fixture mints an agent" -n "$NAME_G"
check_test "the minted definition carries no effort frontmatter line" \
  "$(grep -c '^effort:' "$PROJECT_G/.claude/agents/$NAME_G.md")" -eq 0

WGEN_OUT_G=$(run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "unresolved effort job" --contract "$CONTRACT_G" --task-id "$TASK_ID_G" \
  --control-root "$CONTROL_ROOT_G" --name "$NAME_G" 2>&1); WGEN_G_RC=$?
check "workflow generation succeeds for an agent with no resolved effort" "$WGEN_G_RC"
grep -q '^WORKFLOW_READY' <<< "$WGEN_OUT_G"; check "unresolved-effort generation prints a WORKFLOW_READY line" "$?"

SCRIPT_G="$CONTROL_ROOT_G/workflows/$TASK_ID_G.js"
check_test "the unresolved-effort workflow script exists" -f "$SCRIPT_G"
case "$(cat "$SCRIPT_G" 2>/dev/null)" in
  *"const EFFORT = null;"*) check "the rendered EFFORT constant is the null literal" 0 ;;
  *) check "the rendered EFFORT constant is the null literal" 1 ;;
esac

if command -v node >/dev/null 2>&1; then
  HARNESS="$PLUGIN_ROOT/tests/fixtures/workflow-harness.cjs"
  HARNESS_OUT_G=$(node "$HARNESS" "$SCRIPT_G" '["ok"]' 2>&1); HARNESS_RC_G=$?
  check "the harness runs the unresolved-effort script" "$HARNESS_RC_G"
  check_test "the rendered agent options carry no effort key" \
    "$(jq -r '.agentCalls[0].hasEffort' <<< "$HARNESS_OUT_G")" = false
fi

PROJECT_D=$(new_project)
CONTROL_ROOT_D=$(new_control_root "$PROJECT_D" wf-manifest scout nova-route balanced)
CONTRACT_D=$(bash "$TASK_CONTRACT" issue "$PROJECT_D" manifest-1 \
  --command integration-test --role scout --team solo --job "manifest mismatch job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_D" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_D=$(basename "$CONTRACT_D" .json)
AGEN_OUT_D=$(LBWC_AGENT_RANDOM_SEED=303 run_with_modern_bash "$AGENT_GENERATOR" scout \
  --job "manifest mismatch job" --contract "$CONTRACT_D" --task-id "$TASK_ID_D" \
  --control-root "$CONTROL_ROOT_D" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_D=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_D" | awk '{print $2}')
check_test "manifest-mismatch fixture mints an agent" -n "$NAME_D"

MANIFEST_D_PATH="$CONTROL_ROOT_D/agent-manifest.json"
DEF_PATH_D="$PROJECT_D/.claude/agents/$NAME_D.md"

mutate_manifest_field_d() {
  local field="$1" value="$2"
  jq --arg n "$NAME_D" --arg f "$field" --arg v "$value" '.agents[$n][$f] = $v' "$MANIFEST_D_PATH" > "$MANIFEST_D_PATH.tmp"
  mv "$MANIFEST_D_PATH.tmp" "$MANIFEST_D_PATH"
}
run_wgen_d() {
  run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
    --job "manifest mismatch job" --contract "$CONTRACT_D" --task-id "$TASK_ID_D" \
    --control-root "$CONTROL_ROOT_D" --name "$NAME_D" 2>&1
}

ORIG_ROLE_D=$(jq -r --arg n "$NAME_D" '.agents[$n].role' "$MANIFEST_D_PATH")
mutate_manifest_field_d role "not-scout"
WGEN_ROLE_MISMATCH=$(run_wgen_d); WGEN_ROLE_RC=$?
check_test "a manifest role mismatch is refused" "$WGEN_ROLE_RC" -ne 0
grep -qi 'manifest role mismatch' <<< "$WGEN_ROLE_MISMATCH"; check "the refusal names the manifest role mismatch" "$?"
check_test "the refused role-mismatch attempt leaves no workflow script" ! -e "$CONTROL_ROOT_D/workflows/$TASK_ID_D.js"
mutate_manifest_field_d role "$ORIG_ROLE_D"

ORIG_CONTRACT_ID_D=$(jq -r --arg n "$NAME_D" '.agents[$n].contract_id' "$MANIFEST_D_PATH")
mutate_manifest_field_d contract_id "bogus-contract-id"
WGEN_CID_MISMATCH=$(run_wgen_d); WGEN_CID_RC=$?
check_test "a manifest contract id mismatch is refused" "$WGEN_CID_RC" -ne 0
grep -qi 'manifest contract id mismatch' <<< "$WGEN_CID_MISMATCH"; check "the refusal names the manifest contract id mismatch" "$?"
mutate_manifest_field_d contract_id "$ORIG_CONTRACT_ID_D"

ORIG_TASK_IDENTITY_D=$(jq -r --arg n "$NAME_D" '.agents[$n].task_identity' "$MANIFEST_D_PATH")
mutate_manifest_field_d task_identity "bogus-task-identity"
WGEN_TID_MISMATCH=$(run_wgen_d); WGEN_TID_RC=$?
check_test "a manifest task identity mismatch is refused" "$WGEN_TID_RC" -ne 0
grep -qi 'manifest task identity mismatch' <<< "$WGEN_TID_MISMATCH"; check "the refusal names the manifest task identity mismatch" "$?"
mutate_manifest_field_d task_identity "$ORIG_TASK_IDENTITY_D"

ORIG_DEFINITION_SHA_D=$(jq -r --arg n "$NAME_D" '.agents[$n].definition_sha256' "$MANIFEST_D_PATH")
mutate_manifest_field_d definition_sha256 "0000000000000000000000000000000000000000000000000000000000000000"
WGEN_DIGEST_MISMATCH=$(run_wgen_d); WGEN_DIGEST_RC=$?
check_test "a manifest definition digest mismatch is refused" "$WGEN_DIGEST_RC" -ne 0
grep -qi 'manifest definition digest mismatch' <<< "$WGEN_DIGEST_MISMATCH"; check "the refusal names the manifest definition digest mismatch" "$?"
mutate_manifest_field_d definition_sha256 "$ORIG_DEFINITION_SHA_D"

check_test "the minted definition file exists before the missing-file test" -f "$DEF_PATH_D"
mv "$DEF_PATH_D" "$DEF_PATH_D.bak"
WGEN_MISSING_DEF=$(run_wgen_d); WGEN_MISSING_DEF_RC=$?
check_test "a missing agent definition file is refused" "$WGEN_MISSING_DEF_RC" -ne 0
grep -qi 'agent definition file is missing' <<< "$WGEN_MISSING_DEF"; check "the refusal names the missing definition file" "$?"
mv "$DEF_PATH_D.bak" "$DEF_PATH_D"

run_wgen_d >/dev/null 2>&1; WGEN_D_CLEAN_RC=$?
check "the manifest-mismatch fixture generates cleanly once every field is restored" "$WGEN_D_CLEAN_RC"
check_test "the restored fixture wrote a workflow script" -f "$CONTROL_ROOT_D/workflows/$TASK_ID_D.js"

PLUGIN_FIXTURE_PHASE_BROKEN="$WORK_ROOT/plugin-phase-broken"
mkdir -p "$PLUGIN_FIXTURE_PHASE_BROKEN"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/config" "$PLUGIN_FIXTURE_PHASE_BROKEN/"
sed -i.bak 's/map(select(length > 0))/map(select(length > 0)) + ["Ghost Phase"]/' \
  "$PLUGIN_FIXTURE_PHASE_BROKEN/scripts/render-workflow-template.sh"
rm -f "$PLUGIN_FIXTURE_PHASE_BROKEN/scripts/render-workflow-template.sh.bak"

PROJECT_E=$(new_project)
CONTROL_ROOT_E=$(new_control_root "$PROJECT_E" wf-phase-broken scout nova-route balanced)
CONTRACT_E=$(bash "$PLUGIN_FIXTURE_PHASE_BROKEN/scripts/task-contract.sh" issue "$PROJECT_E" phase-1 \
  --command integration-test --role scout --team solo --job "phase mismatch job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_E" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_E=$(basename "$CONTRACT_E" .json)
AGEN_OUT_E=$(LBWC_AGENT_RANDOM_SEED=404 run_with_modern_bash "$PLUGIN_FIXTURE_PHASE_BROKEN/scripts/agent-generator.sh" scout \
  --job "phase mismatch job" --contract "$CONTRACT_E" --task-id "$TASK_ID_E" \
  --control-root "$CONTROL_ROOT_E" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_E=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_E" | awk '{print $2}')
check_test "phase-mismatch fixture mints an agent" -n "$NAME_E"
WGEN_PHASE_MISMATCH=$(run_with_modern_bash "$PLUGIN_FIXTURE_PHASE_BROKEN/scripts/workflow-generator.sh" solo scout \
  --job "phase mismatch job" --contract "$CONTRACT_E" --task-id "$TASK_ID_E" \
  --control-root "$CONTROL_ROOT_E" --name "$NAME_E" 2>&1)
WGEN_PHASE_MISMATCH_RC=$?
check_test "a meta.phases entry absent from the rendered body is refused" "$WGEN_PHASE_MISMATCH_RC" -ne 0
grep -qi 'phase() calls do not match meta.phases' <<< "$WGEN_PHASE_MISMATCH"; check "the refusal names the phase mismatch" "$?"
check_test "the refused phase-mismatch attempt leaves no workflow script" ! -e "$CONTROL_ROOT_E/workflows/$TASK_ID_E.js"

PLUGIN_FIXTURE_SYNTAX_BROKEN="$WORK_ROOT/plugin-syntax-broken"
mkdir -p "$PLUGIN_FIXTURE_SYNTAX_BROKEN"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/config" "$PLUGIN_FIXTURE_SYNTAX_BROKEN/"
printf '\nfunction (((;\n' >> "$PLUGIN_FIXTURE_SYNTAX_BROKEN/templates/workflows/solo.js.tpl"

PROJECT_F=$(new_project)
CONTROL_ROOT_F=$(new_control_root "$PROJECT_F" wf-syntax-broken scout nova-route balanced)
CONTRACT_F=$(bash "$PLUGIN_FIXTURE_SYNTAX_BROKEN/scripts/task-contract.sh" issue "$PROJECT_F" syntax-1 \
  --command integration-test --role scout --team solo --job "syntax failure job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_F" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_F=$(basename "$CONTRACT_F" .json)
AGEN_OUT_F=$(LBWC_AGENT_RANDOM_SEED=505 run_with_modern_bash "$PLUGIN_FIXTURE_SYNTAX_BROKEN/scripts/agent-generator.sh" scout \
  --job "syntax failure job" --contract "$CONTRACT_F" --task-id "$TASK_ID_F" \
  --control-root "$CONTROL_ROOT_F" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_F=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_F" | awk '{print $2}')
check_test "syntax-failure fixture mints an agent" -n "$NAME_F"
WGEN_SYNTAX_FAIL=$(run_with_modern_bash "$PLUGIN_FIXTURE_SYNTAX_BROKEN/scripts/workflow-generator.sh" solo scout \
  --job "syntax failure job" --contract "$CONTRACT_F" --task-id "$TASK_ID_F" \
  --control-root "$CONTROL_ROOT_F" --name "$NAME_F" 2>&1)
WGEN_SYNTAX_FAIL_RC=$?
check_test "invalid JavaScript in the rendered body is refused" "$WGEN_SYNTAX_FAIL_RC" -ne 0
grep -qi 'node syntax check' <<< "$WGEN_SYNTAX_FAIL"; check "the refusal names the node syntax check" "$?"
check_test "the refused syntax-failure attempt leaves no workflow script" ! -e "$CONTROL_ROOT_F/workflows/$TASK_ID_F.js"

NO_NODE_PATH_DIR="$WORK_ROOT/no-node-path"
mkdir -p "$NO_NODE_PATH_DIR"
ln -s "$GENERATOR_BASH" "$NO_NODE_PATH_DIR/bash"
for no_node_tool in jq shasum awk sed grep head tail cat mktemp mv rm mkdir date python3 dirname basename; do
  no_node_tool_path=$(command -v "$no_node_tool") \
    || { printf 'workflow-generator-core: required tool not found: %s\n' "$no_node_tool" >&2; exit 1; }
  ln -s "$no_node_tool_path" "$NO_NODE_PATH_DIR/$no_node_tool"
done

run_without_node() {
  PATH="$NO_NODE_PATH_DIR" "$GENERATOR_BASH" "$@"
}

PROJECT_H=$(new_project)
CONTROL_ROOT_H=$(new_control_root "$PROJECT_H" wf-no-node scout nova-route balanced)
CONTRACT_H=$(bash "$TASK_CONTRACT" issue "$PROJECT_H" no-node-1 \
  --command integration-test --role scout --team solo --job "node absent fallback job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_H" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_H=$(basename "$CONTRACT_H" .json)
AGEN_OUT_H=$(LBWC_AGENT_RANDOM_SEED=909 run_with_modern_bash "$AGENT_GENERATOR" scout \
  --job "node absent fallback job" --contract "$CONTRACT_H" --task-id "$TASK_ID_H" \
  --control-root "$CONTROL_ROOT_H" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_H=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_H" | awk '{print $2}')
check_test "node-absent fixture mints an agent" -n "$NAME_H"

WGEN_OUT_H=$(run_without_node "$WORKFLOW_GENERATOR" solo scout \
  --job "node absent fallback job" --contract "$CONTRACT_H" --task-id "$TASK_ID_H" \
  --control-root "$CONTROL_ROOT_H" --name "$NAME_H" 2>&1)
WGEN_H_RC=$?
check "a well-formed render still succeeds with node absent from PATH" "$WGEN_H_RC"
grep -q '^WORKFLOW_READY' <<< "$WGEN_OUT_H"; check "the node-absent success prints a WORKFLOW_READY line" "$?"
grep -qi 'node not found, falling back' <<< "$WGEN_OUT_H"; check "the node-absent success emits the fallback warning" "$?"
check_test "the node-absent success wrote a workflow script" -f "$CONTROL_ROOT_H/workflows/$TASK_ID_H.js"

WGEN_SYNTAX_FAIL_NO_NODE=$(run_without_node "$PLUGIN_FIXTURE_SYNTAX_BROKEN/scripts/workflow-generator.sh" solo scout \
  --job "syntax failure job" --contract "$CONTRACT_F" --task-id "$TASK_ID_F" \
  --control-root "$CONTROL_ROOT_F" --name "$NAME_F" 2>&1)
WGEN_SYNTAX_FAIL_NO_NODE_RC=$?
check_test "invalid JavaScript is refused with node absent from PATH" "$WGEN_SYNTAX_FAIL_NO_NODE_RC" -ne 0
grep -qi 'has unbalanced parentheses, braces, or brackets' <<< "$WGEN_SYNTAX_FAIL_NO_NODE"
check "the node-absent refusal names the fallback balance check" "$?"
check_test "the node-absent refused syntax-failure attempt leaves no workflow script" ! -e "$CONTROL_ROOT_F/workflows/$TASK_ID_F.js"

PLUGIN_FIXTURE_QUOTE_BLIND="$WORK_ROOT/plugin-quote-blind"
mkdir -p "$PLUGIN_FIXTURE_QUOTE_BLIND"
cp -R "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/templates" "$PLUGIN_ROOT/config" "$PLUGIN_FIXTURE_QUOTE_BLIND/"
printf '\nconst QUOTE_PROBE = '\''don"t trust embedded quotes'\'';\nconst LEAKED_FORBIDDEN_TOKEN = require("nefarious");\n' \
  >> "$PLUGIN_FIXTURE_QUOTE_BLIND/templates/workflows/solo.js.tpl"

PROJECT_QB=$(new_project)
CONTROL_ROOT_QB=$(new_control_root "$PROJECT_QB" wf-quote-blind scout nova-route balanced)
CONTRACT_QB=$(bash "$PLUGIN_FIXTURE_QUOTE_BLIND/scripts/task-contract.sh" issue "$PROJECT_QB" quote-1 \
  --command integration-test --role scout --team solo --job "single quote blinding job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_QB" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_QB=$(basename "$CONTRACT_QB" .json)
AGEN_OUT_QB=$(LBWC_AGENT_RANDOM_SEED=111 run_with_modern_bash "$PLUGIN_FIXTURE_QUOTE_BLIND/scripts/agent-generator.sh" scout \
  --job "single quote blinding job" --contract "$CONTRACT_QB" --task-id "$TASK_ID_QB" \
  --control-root "$CONTROL_ROOT_QB" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_QB=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_QB" | awk '{print $2}')
check_test "single-quote-blinding fixture mints an agent" -n "$NAME_QB"

WGEN_QUOTE_BLIND=$(run_with_modern_bash "$PLUGIN_FIXTURE_QUOTE_BLIND/scripts/workflow-generator.sh" solo scout \
  --job "single quote blinding job" --contract "$CONTRACT_QB" --task-id "$TASK_ID_QB" \
  --control-root "$CONTROL_ROOT_QB" --name "$NAME_QB" 2>&1)
WGEN_QUOTE_BLIND_RC=$?
check_test "a forbidden token hidden behind a single-quoted string is refused, not blinded" "$WGEN_QUOTE_BLIND_RC" -ne 0
grep -qi "forbidden token 'require(' found outside a string literal" <<< "$WGEN_QUOTE_BLIND"
check "the refusal names the forbidden token leaked past the single-quoted string" "$?"
check_test "the refused single-quote-blinding attempt leaves no workflow script" ! -e "$CONTROL_ROOT_QB/workflows/$TASK_ID_QB.js"

PROJECT_B1=$(new_project)
CONTROL_ROOT_B1=$(new_control_root "$PROJECT_B1" wf-det scout nova-route balanced)
CONTRACT_B1=$(bash "$TASK_CONTRACT" issue "$PROJECT_B1" det-1 \
  --command integration-test --role scout --team solo --job "deterministic job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_B1" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_B1=$(basename "$CONTRACT_B1" .json)
AGEN_OUT_B1=$(LBWC_AGENT_RANDOM_SEED=202 run_with_modern_bash "$AGENT_GENERATOR" scout \
  --job "deterministic job" --contract "$CONTRACT_B1" --task-id "$TASK_ID_B1" \
  --control-root "$CONTROL_ROOT_B1" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_B1=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_B1" | awk '{print $2}')
run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "deterministic job" --contract "$CONTRACT_B1" --task-id "$TASK_ID_B1" \
  --control-root "$CONTROL_ROOT_B1" --name "$NAME_B1" >/dev/null 2>&1
FIRST_JS="$CONTROL_ROOT_B1/workflows/$TASK_ID_B1.js"

PROJECT_B2=$(new_project)
CONTROL_ROOT_B2=$(new_control_root "$PROJECT_B2" wf-det scout nova-route balanced)
CONTRACT_B2=$(bash "$TASK_CONTRACT" issue "$PROJECT_B2" det-1 \
  --command integration-test --role scout --team solo --job "deterministic job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_B2" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_B2=$(basename "$CONTRACT_B2" .json)
AGEN_OUT_B2=$(LBWC_AGENT_RANDOM_SEED=202 run_with_modern_bash "$AGENT_GENERATOR" scout \
  --job "deterministic job" --contract "$CONTRACT_B2" --task-id "$TASK_ID_B2" \
  --control-root "$CONTROL_ROOT_B2" --write-capability directory:notes \
  --execution-backend workflow 2>&1)
NAME_B2=$(grep '^SPAWN_READY' <<< "$AGEN_OUT_B2" | awk '{print $2}')
run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "deterministic job" --contract "$CONTRACT_B2" --task-id "$TASK_ID_B2" \
  --control-root "$CONTROL_ROOT_B2" --name "$NAME_B2" >/dev/null 2>&1
SECOND_JS="$CONTROL_ROOT_B2/workflows/$TASK_ID_B2.js"

check_test "the task id is identical across the two isolated runs" "$TASK_ID_B1" = "$TASK_ID_B2"
check_test "the minted agent name is identical across the two isolated runs" "$NAME_B1" = "$NAME_B2"
check_test "the first deterministic run wrote a script" -f "$FIRST_JS"
check_test "the second deterministic run wrote a script" -f "$SECOND_JS"
if [ -f "$FIRST_JS" ] && [ -f "$SECOND_JS" ]; then
  cmp -s "$FIRST_JS" "$SECOND_JS"
  check "two identical invocations produce byte-identical files" "$?"
else
  check "two identical invocations produce byte-identical files" 1
fi

PROJECT_I=$(new_project)
CONTROL_ROOT_I=$(new_control_root "$PROJECT_I" wf-disabled-config scout nova-route balanced)
jq '.workflow_execution.enabled = false' "$CONTROL_ROOT_I/config.json" > "$CONTROL_ROOT_I/config.json.tmp"
mv "$CONTROL_ROOT_I/config.json.tmp" "$CONTROL_ROOT_I/config.json"
CONTRACT_I=$(bash "$TASK_CONTRACT" issue "$PROJECT_I" disabled-config-1 \
  --command integration-test --role scout --team solo --job "disabled config job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_I" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_I=$(basename "$CONTRACT_I" .json)
WGEN_DISABLED_CONFIG=$(run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "disabled config job" --contract "$CONTRACT_I" --task-id "$TASK_ID_I" \
  --control-root "$CONTROL_ROOT_I" --name "lbwc-scout-unused-unused-unused" 2>&1)
check_test "generation is refused when workflow_execution.enabled is false" "$?" -ne 0
grep -qi 'workflow backend is disabled in configuration' <<< "$WGEN_DISABLED_CONFIG"
check "the refusal names the disabled configuration" "$?"
check_test "the refused disabled-config attempt leaves no workflow script" ! -e "$CONTROL_ROOT_I/workflows/$TASK_ID_I.js"

PROJECT_J=$(new_project)
CONTROL_ROOT_J=$(new_control_root "$PROJECT_J" wf-unavailable-cap scout nova-route balanced)
jq '.workflow = {available:false, unavailable_reasons:["Claude Code 2.1.100 is older than the workflow version floor 2.1.154."]}' \
  "$CONTROL_ROOT_J/claude-capabilities.json" > "$CONTROL_ROOT_J/claude-capabilities.json.tmp"
mv "$CONTROL_ROOT_J/claude-capabilities.json.tmp" "$CONTROL_ROOT_J/claude-capabilities.json"
CONTRACT_J=$(bash "$TASK_CONTRACT" issue "$PROJECT_J" unavailable-cap-1 \
  --command integration-test --role scout --team solo --job "unavailable capability job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_J" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_J=$(basename "$CONTRACT_J" .json)
WGEN_UNAVAILABLE_CAP=$(run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "unavailable capability job" --contract "$CONTRACT_J" --task-id "$TASK_ID_J" \
  --control-root "$CONTROL_ROOT_J" --name "lbwc-scout-unused-unused-unused" 2>&1)
check_test "generation is refused when the capability catalog reports unavailable" "$?" -ne 0
grep -qi 'workflow backend is unavailable' <<< "$WGEN_UNAVAILABLE_CAP"
check "the refusal reports unavailability" "$?"
grep -qF 'Claude Code 2.1.100 is older than the workflow version floor 2.1.154.' <<< "$WGEN_UNAVAILABLE_CAP"
check "the refusal names the unavailable reason verbatim" "$?"
check_test "the refused unavailable-capability attempt leaves no workflow script" ! -e "$CONTROL_ROOT_J/workflows/$TASK_ID_J.js"

PROJECT_K=$(new_project)
CONTROL_ROOT_K=$(new_control_root "$PROJECT_K" wf-live-disable scout nova-route balanced)
CONTRACT_K=$(bash "$TASK_CONTRACT" issue "$PROJECT_K" live-disable-1 \
  --command integration-test --role scout --team solo --job "live disable job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_K" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_K=$(basename "$CONTRACT_K" .json)
WGEN_LIVE_DISABLE=$(CLAUDE_CODE_DISABLE_WORKFLOWS=1 run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "live disable job" --contract "$CONTRACT_K" --task-id "$TASK_ID_K" \
  --control-root "$CONTROL_ROOT_K" --name "lbwc-scout-unused-unused-unused" 2>&1)
check_test "generation fails closed when CLAUDE_CODE_DISABLE_WORKFLOWS is live-set against a stale available catalog" "$?" -ne 0
grep -qi 'CLAUDE_CODE_DISABLE_WORKFLOWS is set in this session' <<< "$WGEN_LIVE_DISABLE"
check "the refusal names the live CLAUDE_CODE_DISABLE_WORKFLOWS override" "$?"

PROJECT_L=$(new_project)
CONTROL_ROOT_L=$(new_control_root "$PROJECT_L" wf-live-subagent scout nova-route balanced)
CONTRACT_L=$(bash "$TASK_CONTRACT" issue "$PROJECT_L" live-subagent-1 \
  --command integration-test --role scout --team solo --job "live subagent model job" \
  --group fixed \
  --control-root "$CONTROL_ROOT_L" --requested-backend workflow --resolved-backend workflow \
  --write-capability directory:notes)
TASK_ID_L=$(basename "$CONTRACT_L" .json)
WGEN_LIVE_SUBAGENT=$(CLAUDE_CODE_SUBAGENT_MODEL=claude-opus run_with_modern_bash "$WORKFLOW_GENERATOR" solo scout \
  --job "live subagent model job" --contract "$CONTRACT_L" --task-id "$TASK_ID_L" \
  --control-root "$CONTROL_ROOT_L" --name "lbwc-scout-unused-unused-unused" 2>&1)
check_test "generation fails closed when CLAUDE_CODE_SUBAGENT_MODEL is live-set against a stale available catalog" "$?" -ne 0
grep -qi 'CLAUDE_CODE_SUBAGENT_MODEL is set in this session' <<< "$WGEN_LIVE_SUBAGENT"
check "the refusal names the live CLAUDE_CODE_SUBAGENT_MODEL override" "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
