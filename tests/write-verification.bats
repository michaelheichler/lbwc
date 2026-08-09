#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  SCRIPT="$SCRIPTS_DIR/write-verification.sh"
  PHASE_DIR="$TEST_TEMP_DIR/.lbwc-planning/phases/01-verification"
  TARGET="$PHASE_DIR/01-VERIFICATION.md"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

run_writer() {
  local payload="$1"
  local output_path="$2"

  printf '%s\n' "$payload" | bash "$SCRIPT" "$output_path"
}

passing_payload() {
  cat <<'JSON'
{
  "phase": "01",
  "tier": "standard",
  "result": "PASS",
  "checks": {"passed": 1, "failed": 0, "total": 1},
  "checks_detail": [
    {"id": "must-have", "status": "PASS", "category": "must_have", "description": "The artifact exists", "evidence": "observed"}
  ]
}
JSON
}

@test "writes a canonical verification artifact for a valid payload" {
  printf '%s\n' "old artifact" > "$TARGET"

  run run_writer "$(passing_payload)" "$TARGET"

  [ "$status" -eq 0 ]
  ! grep -Fqx 'old artifact' "$TARGET"
  grep -Fx 'writer: write-verification.sh' "$TARGET"
  grep -Fx 'result: PASS' "$TARGET"
  grep -Fx '## Must-Have Checks' "$TARGET"
}

@test "rejects an invalid payload without creating an artifact" {
  run run_writer '{"tier":"standard","result":"UNKNOWN","checks":{"passed":1,"total":1}}' "$TARGET"

  [ "$status" -ne 0 ]
  [ ! -e "$TARGET" ]
}

@test "rejects a non-object payload without replacing an existing artifact" {
  printf '%s\n' "old artifact" > "$TARGET"

  run run_writer '{"payload":[]}' "$TARGET"

  [ "$status" -ne 0 ]
  grep -Fqx "old artifact" "$TARGET"
}

@test "rejects a tier outside the verification enum" {
  payload=$(passing_payload | jq '.tier = "thorough"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"tier"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects negative fractional and inconsistent check counters" {
  for checks in \
    '{"passed":-1,"failed":0,"total":0}' \
    '{"passed":0.5,"failed":0,"total":1}' \
    '{"passed":1,"failed":1,"total":1}'; do
    payload=$(passing_payload | jq --argjson checks "$checks" '.checks = $checks | del(.checks_detail) | .result = "FAIL"')

    run run_writer "$payload" "$TARGET"

    [ "$status" -ne 0 ]
    [[ "$output" == *"checks"* ]]
    [ ! -e "$TARGET" ]
  done
}

@test "downgrades PASS to PARTIAL when detail includes a FAIL" {
  payload=$(passing_payload | jq '.result = "PASS" | .checks = {passed: 0, failed: 1, total: 1} | .checks_detail[0].status = "FAIL"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -eq 0 ]
  grep -Fx 'result: PARTIAL' "$TARGET"
}

@test "rejects a FAIL result without structured failed-check detail before replacement" {
  printf '%s\n' "old artifact" > "$TARGET"
  payload=$(passing_payload | jq '.result = "FAIL" | .checks = {passed: 0, failed: 0, total: 0} | del(.checks_detail)')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"checks_detail"* ]]
  grep -Fqx "old artifact" "$TARGET"
}

@test "rejects a FAIL result whose detail has no failed check before replacement" {
  printf '%s\n' "old artifact" > "$TARGET"
  payload=$(passing_payload | jq '.result = "FAIL"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL check"* ]]
  grep -Fqx "old artifact" "$TARGET"
}

@test "rejects a FAIL result with an unstable failed-check ID before replacement" {
  printf '%s\n' "old artifact" > "$TARGET"
  payload=$(passing_payload | jq '.result = "FAIL" | .checks = {passed: 0, failed: 1, total: 1} | .checks_detail[0].status = "FAIL" | .checks_detail[0].id = "test failure"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"stable ID"* ]]
  grep -Fqx "old artifact" "$TARGET"
}

@test "rejects a FAIL result without actionable description and evidence before replacement" {
  for field in description evidence; do
    printf '%s\n' "old artifact" > "$TARGET"
    payload=$(passing_payload | jq --arg field "$field" '.result = "FAIL" | .checks = {passed: 0, failed: 1, total: 1} | .checks_detail[0].status = "FAIL" | .checks_detail[0][$field] = " "')

    run run_writer "$payload" "$TARGET"

    [ "$status" -ne 0 ]
    [[ "$output" == *"actionable"* ]]
    grep -Fqx "old artifact" "$TARGET"
  done
}

@test "retains remediation evidence in a rich failed Artifact check" {
  payload=$(passing_payload | jq '
    .result = "FAIL" |
    .checks = {passed: 0, failed: 1, total: 1} |
    .checks_detail[0] = {
      id: "artifact-docs",
      status: "FAIL",
      category: "artifact",
      description: "docs/api.md",
      exists: false,
      contains: "retry guidance",
      evidence: "docs/api.md is missing, so add the retry guidance."
    }
  ')

  run run_writer "$payload" "$TARGET"

  [ "$status" -eq 0 ]
  grep -Fx '| # | ID | Artifact | Exists | Contains | Evidence | Status |' "$TARGET"
  grep -Fx '| 1 | artifact-docs | docs/api.md | No | retry guidance | docs/api.md is missing, so add the retry guidance. | FAIL |' "$TARGET"
}

@test "retains remediation evidence in a rich failed Key Link check" {
  payload=$(passing_payload | jq '
    .result = "FAIL" |
    .checks = {passed: 0, failed: 1, total: 1} |
    .checks_detail[0] = {
      id: "qa-route",
      status: "FAIL",
      category: "key_link",
      description: "QA command invokes the writer",
      from: "commands/qa.md",
      to: "scripts/write-verification.sh",
      via: "subprocess call",
      evidence: "commands/qa.md bypasses the writer, so route QA through it."
    }
  ')

  run run_writer "$payload" "$TARGET"

  [ "$status" -eq 0 ]
  grep -Fx '| # | ID | From | To | Via | Evidence | Status |' "$TARGET"
  grep -Fx '| 1 | qa-route | commands/qa.md | scripts/write-verification.sh | subprocess call | commands/qa.md bypasses the writer, so route QA through it. | FAIL |' "$TARGET"
}

@test "requires every check to reference each plan when plans exist" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["01-01"]')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_ref"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects duplicate plan IDs instead of silently de-duplicating them" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["01-01", "01-01"] | .checks_detail[0].plan_ref = "01-01"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plans_verified"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects a plan filename alias in plans_verified" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["01-01-PLAN.md"] | .checks_detail[0].plan_ref = "01-01"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plans_verified"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects an empty plan ID even when a valid plan ID is also supplied" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["", "01-01"] | .checks_detail[0].plan_ref = "01-01"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plans_verified"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects the legacy PLAN alias when frontmatter declares the canonical ID" {
  printf '%s\n' '---' 'plan: 01' '---' > "$PHASE_DIR/PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["PLAN"] | .checks_detail[0].plan_ref = "PLAN"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plans_verified"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects an unknown plan reference" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '.plans_verified = ["01-01"] | .checks_detail[0].plan_ref = "PLAN.md"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_ref"* ]]
  [ ! -e "$TARGET" ]
}

@test "rejects an unknown plan reference even when another check names the verified plan" {
  touch "$PHASE_DIR/01-01-PLAN.md"
  payload=$(passing_payload | jq '
    .checks = {passed: 2, failed: 0, total: 2} |
    .plans_verified = ["01-01"] |
    .checks_detail[0].plan_ref = "01-01" |
    .checks_detail += [{"id":"artifact","status":"PASS","plan_ref":"PLAN.md"}]
  ')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"plan_ref"* ]]
  [ ! -e "$TARGET" ]
}

@test "writes each discovered canonical plan ID exactly once" {
  touch "$PHASE_DIR/01-01-PLAN.md" "$PHASE_DIR/01-02-PLAN.md"
  payload=$(passing_payload | jq '
    .checks = {passed: 2, failed: 0, total: 2} |
    .plans_verified = ["01-01", "01-02"] |
    .checks_detail[0].plan_ref = "01-01" |
    .checks_detail += [{"id":"artifact","status":"PASS","plan_ref":"01-02"}]
  ')

  run run_writer "$payload" "$TARGET"

  [ "$status" -eq 0 ]
  grep -Fx '  - 01-01' "$TARGET"
  grep -Fx '  - 01-02' "$TARGET"
}

@test "rejects phase frontmatter injection without replacing an artifact" {
  printf '%s\n' "old artifact" > "$TARGET"
  payload=$(passing_payload | jq '.phase = "01\\nwriter: forged"')

  run run_writer "$payload" "$TARGET"

  [ "$status" -ne 0 ]
  [[ "$output" == *"phase"* ]]
  grep -Fqx "old artifact" "$TARGET"
}

@test "writes a valid payload outside a Git repository" {
  payload=$(passing_payload)

  run bash -c 'cd "$1" && printf "%s\\n" "$2" | bash "$3" "$4"' bash "$TEST_TEMP_DIR" "$payload" "$SCRIPT" "$TARGET"

  [ "$status" -eq 0 ]
  grep -Fx 'result: PASS' "$TARGET"
  ! grep -Fq 'verified_at_commit:' "$TARGET"
}
