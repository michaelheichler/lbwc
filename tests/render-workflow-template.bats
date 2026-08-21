#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/render-workflow-template.sh"
  OUT_DIR=$(mktemp -d)
  ADVERSARIAL_JOB=$'evil "job" with \\ backslash\nnewline `backtick` ${evil} and */ close-comment @@JOB@@'
}

teardown() {
  rm -rf "$OUT_DIR"
}

HARNESS="$BATS_TEST_DIRNAME/fixtures/workflow-harness.cjs"

render_pair() {
  local autonomy="$1" job="${2:-job}"
  run bash "$SCRIPT" pair NAME=probe-pair DESCRIPTION=desc \
    "JOB=$job" TASK_ID=task-2 "AUTONOMY=$autonomy" \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast
}

render_trio() {
  local autonomy="$1" job="${2:-job}"
  run bash "$SCRIPT" trio NAME=probe-trio DESCRIPTION=desc \
    "JOB=$job" TASK_ID=task-3 "AUTONOMY=$autonomy" \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast \
    TESTDEV_AGENT_TYPE=lbwc-td-a TESTDEV_MODEL=sonnet TESTDEV_EFFORT=fast
}

run_workflow() {
  local rendered_file="$1" responses_json="$2"
  run node "$HARNESS" "$rendered_file" "$responses_json"
}

wrap_body_for_syntax_check() {
  local file="$1" wrapped="${1}.syntax-check.mjs"
  { printf '(async () => {\n'; tail -n +2 "$file"; printf '})\n'; } > "$wrapped"
  printf '%s\n' "$wrapped"
}

assert_rendered_js_valid() {
  local file="$1" meta_line meta_expr wrapped
  command -v node >/dev/null 2>&1 || skip "node is unavailable"

  meta_line=$(head -n1 "$file")
  meta_expr=${meta_line#"export const meta = "}
  meta_expr=${meta_expr%";"}
  run jq -e . <<< "$meta_expr"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    return 1
  fi

  wrapped=$(wrap_body_for_syntax_check "$file")
  run node --check --input-type=module - < "$wrapped"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    return 1
  fi
}

agent_labels() {
  jq -r '.agentCalls | map(.label) | join(",")' <<< "$output"
}

decode_const() {
  local file="$1" name="$2"
  node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8");
    const re = new RegExp("^const " + process.argv[2] + " = (\".*\");$", "m");
    const match = re.exec(src);
    if (!match) { process.exit(1); }
    process.stdout.write(JSON.parse(match[1]));
  ' "$file" "$name"
}

render_solo() {
  run bash "$SCRIPT" solo NAME=probe DESCRIPTION=desc \
    "JOB=$1" TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet EFFORT=balanced
}

@test "solo template renders valid JavaScript with meta on line 1" {
  render_solo "simple job"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo.js"

  first_line=$(head -n1 "$OUT_DIR/solo.js")
  [[ "$first_line" == "export const meta = "*";" ]]

  meta_json=${first_line#"export const meta = "}
  meta_json=${meta_json%";"}
  run jq -e . <<< "$meta_json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.phases | join(",")' <<< "$meta_json")" = Execute ]

  assert_rendered_js_valid "$OUT_DIR/solo.js"
}

@test "the syntax check rejects a rendered file whose body is corrupted" {
  command -v node >/dev/null 2>&1 || skip "node is unavailable"
  render_solo "simple job"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$OUT_DIR/solo-corrupt.js"
  printf 'function (((;\n' >> "$OUT_DIR/solo-corrupt.js"

  run assert_rendered_js_valid "$OUT_DIR/solo-corrupt.js"
  [ "$status" -ne 0 ]
  [[ "$output" == *SyntaxError* ]]
}

@test "adversarial job text round-trips byte for byte through the JOB constant" {
  render_solo "$ADVERSARIAL_JOB"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo.js"

  assert_rendered_js_valid "$OUT_DIR/solo.js"

  decoded=$(decode_const "$OUT_DIR/solo.js" JOB)
  [ "$decoded" = "$ADVERSARIAL_JOB" ]
}

@test "no unit separator byte survives rendering" {
  render_solo "$ADVERSARIAL_JOB"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo.js"

  case "$output" in
    *$'\x1f'*) unit_separator_found=1 ;;
    *) unit_separator_found=0 ;;
  esac
  [ "$unit_separator_found" -eq 0 ]
}

@test "a literal marker inside job text does not trip the leftover-token scan" {
  render_solo 'plain text containing @@TASK_ID@@ literally'
  [ "$status" -eq 0 ]
  [[ "$output" == *'@@TASK_ID@@ literally'* ]]
}

@test "solo template passes the qa schema when ROLE is qa" {
  run bash "$SCRIPT" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=qa AGENT_TYPE=lbwc-qa-a MODEL=sonnet EFFORT=balanced
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo-qa.mjs"

  run_workflow "$OUT_DIR/solo-qa.mjs" '[{"result":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agentCalls[0].hasSchema' <<< "$output")" = true ]
}

@test "solo template omits the schema option for a non-qa role rather than passing null" {
  render_solo "simple job"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo-scout.mjs"

  run_workflow "$OUT_DIR/solo-scout.mjs" '["ok"]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agentCalls[0].hasSchema' <<< "$output")" = false ]
}

@test "solo template includes agent effort when EFFORT is resolved" {
  render_solo "simple job"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo-effort.mjs"

  run_workflow "$OUT_DIR/solo-effort.mjs" '["ok"]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agentCalls[0].hasEffort' <<< "$output")" = true ]
}

@test "solo template omits agent effort when EFFORT is unresolved" {
  run bash "$SCRIPT" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet EFFORT=
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo-no-effort.mjs"

  [[ "$(cat "$OUT_DIR/solo-no-effort.mjs")" == *"const EFFORT = null;"* ]]
  assert_rendered_js_valid "$OUT_DIR/solo-no-effort.mjs"

  run_workflow "$OUT_DIR/solo-no-effort.mjs" '["ok"]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agentCalls[0].hasEffort' <<< "$output")" = false ]
}

@test "solo template executes the adversarial job through the harness" {
  render_solo "$ADVERSARIAL_JOB"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/solo-adversarial.mjs"

  run_workflow "$OUT_DIR/solo-adversarial.mjs" '["ok"]'
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = scout ]
  [ "$(jq -r '.agentCalls[0].hasSchema' <<< "$output")" = false ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
}

@test "an unsupplied token fails the render" {
  run bash "$SCRIPT" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field EFFORT"* ]]
}

@test "an unknown shape is rejected" {
  run bash "$SCRIPT" quad NAME=probe DESCRIPTION=desc
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown shape"* ]]
}

@test "an unknown field is rejected rather than silently discarded" {
  run bash "$SCRIPT" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet EFFORT=balanced \
    TASKID=task-1
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown field 'TASKID'"* ]]
}

@test "a template with no phase calls fails with a clear message instead of a bare pipefail exit" {
  fixture_dir=$(mktemp -d)
  mkdir -p "$fixture_dir/scripts" "$fixture_dir/templates/workflows"
  cp "$SCRIPT" "$fixture_dir/scripts/render-workflow-template.sh"
  printf 'const JOB = @@JOB@@;\nconst TASK_ID = @@TASK_ID@@;\nconst ROLE = @@ROLE@@;\nconst AGENT_TYPE = @@AGENT_TYPE@@;\nconst MODEL = @@MODEL@@;\nconst EFFORT = @@EFFORT@@;\n' \
    > "$fixture_dir/templates/workflows/solo.js.tpl"

  run bash "$fixture_dir/scripts/render-workflow-template.sh" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet EFFORT=balanced
  rm -rf "$fixture_dir"

  [ "$status" -eq 1 ]
  [[ "$output" == "render-workflow-template: template 'solo' declares no phase(\"...\") calls" ]]
}

@test "a template carrying an undeclared marker fails the unresolved-token scan" {
  fixture_dir=$(mktemp -d)
  mkdir -p "$fixture_dir/scripts" "$fixture_dir/templates/workflows"
  cp "$SCRIPT" "$fixture_dir/scripts/render-workflow-template.sh"
  printf 'const JOB = @@JOB@@;\nconst TASK_ID = @@TASK_ID@@;\nconst ROLE = @@ROLE@@;\nconst AGENT_TYPE = @@AGENT_TYPE@@;\nconst MODEL = @@MODEL@@;\nconst EFFORT = @@EFFORT@@;\nconst STRAY = @@UNDECLARED_MARKER@@;\n\nawait phase("Execute");\n\nreturn { status: "complete" };\n' \
    > "$fixture_dir/templates/workflows/solo.js.tpl"

  run bash "$fixture_dir/scripts/render-workflow-template.sh" solo NAME=probe DESCRIPTION=desc \
    JOB=job TASK_ID=task-1 ROLE=scout AGENT_TYPE=lbwc-scout-a MODEL=sonnet EFFORT=balanced
  rm -rf "$fixture_dir"

  [ "$status" -eq 1 ]
  [[ "$output" == "render-workflow-template: unresolved template token" ]]
}

@test "pair template renders valid JavaScript with both phase titles in meta" {
  run bash "$SCRIPT" pair NAME=probe-pair DESCRIPTION=desc \
    JOB=job TASK_ID=task-2 AUTONOMY=standard \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair.js"

  first_line=$(head -n1 "$OUT_DIR/pair.js")
  meta_json=${first_line#"export const meta = "}
  meta_json=${meta_json%";"}
  [ "$(jq -r '.phases | join(",")' <<< "$meta_json")" = "Implement,Review" ]

  assert_rendered_js_valid "$OUT_DIR/pair.js"
}

@test "pair template fails without a critic token" {
  run bash "$SCRIPT" pair NAME=probe-pair DESCRIPTION=desc \
    JOB=job TASK_ID=task-2 AUTONOMY=standard \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field CRITIC_EFFORT"* ]]
}

@test "trio template renders valid JavaScript with all three phase titles in meta" {
  run bash "$SCRIPT" trio NAME=probe-trio DESCRIPTION=desc \
    "JOB=$ADVERSARIAL_JOB" TASK_ID=task-3 AUTONOMY=pure-vibe \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast \
    TESTDEV_AGENT_TYPE=lbwc-td-a TESTDEV_MODEL=sonnet TESTDEV_EFFORT=fast
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio.js"

  first_line=$(head -n1 "$OUT_DIR/trio.js")
  meta_json=${first_line#"export const meta = "}
  meta_json=${meta_json%";"}
  [ "$(jq -r '.phases | join(",")' <<< "$meta_json")" = "Implement,Build Tests,Verify" ]

  assert_rendered_js_valid "$OUT_DIR/trio.js"

  decoded=$(decode_const "$OUT_DIR/trio.js" JOB)
  [ "$decoded" = "$ADVERSARIAL_JOB" ]
}

@test "two identical invocations produce byte-identical output" {
  run bash "$SCRIPT" trio NAME=probe-trio DESCRIPTION=desc \
    JOB=job TASK_ID=task-3 AUTONOMY=confident \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast \
    TESTDEV_AGENT_TYPE=lbwc-td-a TESTDEV_MODEL=sonnet TESTDEV_EFFORT=fast
  [ "$status" -eq 0 ]
  first="$output"

  run bash "$SCRIPT" trio NAME=probe-trio DESCRIPTION=desc \
    JOB=job TASK_ID=task-3 AUTONOMY=confident \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT=balanced \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=fast \
    TESTDEV_AGENT_TYPE=lbwc-td-a TESTDEV_MODEL=sonnet TESTDEV_EFFORT=fast
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "pair template omits engineer and critic effort when both are unresolved" {
  run bash "$SCRIPT" pair NAME=probe-pair DESCRIPTION=desc \
    JOB=job TASK_ID=task-2 AUTONOMY=standard \
    ENGINEER_AGENT_TYPE=lbwc-eng-a ENGINEER_MODEL=sonnet ENGINEER_EFFORT= \
    CRITIC_AGENT_TYPE=lbwc-crit-a CRITIC_MODEL=sonnet CRITIC_EFFORT=
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-no-effort.mjs"

  [[ "$(cat "$OUT_DIR/pair-no-effort.mjs")" == *"const ENGINEER_EFFORT = null;"* ]]
  [[ "$(cat "$OUT_DIR/pair-no-effort.mjs")" == *"const CRITIC_EFFORT = null;"* ]]
  assert_rendered_js_valid "$OUT_DIR/pair-no-effort.mjs"

  run_workflow "$OUT_DIR/pair-no-effort.mjs" '[{"n":1},{"verdict":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agentCalls[0].hasEffort' <<< "$output")" = false ]
  [ "$(jq -r '.agentCalls[1].hasEffort' <<< "$output")" = false ]
}

@test "pair template executes the adversarial job through the harness" {
  render_pair standard "$ADVERSARIAL_JOB"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/pair-adversarial.mjs"

  run_workflow "$OUT_DIR/pair-adversarial.mjs" '[{"n":1},{"verdict":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,critic" ]
  [ "$(jq -r '.agentCalls[1].hasSchema' <<< "$output")" = true ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
  [ "$(jq -r '.result.round' <<< "$output")" = 1 ]
}

@test "trio template executes the adversarial job through the harness" {
  render_trio standard "$ADVERSARIAL_JOB"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$OUT_DIR/trio-adversarial.mjs"

  run_workflow "$OUT_DIR/trio-adversarial.mjs" '[{"n":1},{"t":1},{"verdict":"PASS"}]'
  [ "$status" -eq 0 ]
  [ "$(agent_labels)" = "engineer,test-dev,critic" ]
  [ "$(jq -r '.agentCalls[2].hasSchema' <<< "$output")" = true ]
  [ "$(jq -r '.result.status' <<< "$output")" = complete ]
}

@test "committed workflow templates carry no single-quoted strings" {
  local single_quote
  single_quote=$(printf '\047')
  local template
  while IFS= read -r template; do
    run grep -nF "$single_quote" "$template"
    [ "$status" -ne 0 ]
  done < <(find "$BATS_TEST_DIRNAME/../templates/workflows" -name '*.js.tpl')
}
