#!/usr/bin/env bats

setup() {
  ROOT="$(mktemp -d)"
  PLAN="$ROOT/PLAN.md"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/task-contract.sh"
  cat >"$PLAN" <<'PLAN'
---
phase: 9
---
<tasks>
<task type="auto">
<name>write contract</name>
<role>coding-dijkstra</role>
<files>src/contract.py
tests/task-contract.bats</files>
<action>Implement the writer.</action>
<verify>Run the contract tests.</verify>
<done>Contract is durable.</done>
<strategy>tdd</strategy>
</task>
</tasks>
PLAN
}

teardown() { rm -rf "$ROOT"; }

@test "open writes canonical task contract and read returns it" {
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -eq 0 ]
  contract="$ROOT/.lbwc-planning/.contracts/tasks/09-PLAN-write-contract.json"
  [ -f "$contract" ]
  ROOT_CANON="$(cd "$ROOT" && pwd -P)"
  run jq --arg root "$ROOT_CANON" -e '.schema_version == 2 and .created_by == "main" and .project_root == $root and .roles == ["coding-dijkstra", "coding-dijkstra-critic"] and .state == "planned" and .phase == "09" and .task_name == "write contract" and .role == "coding-dijkstra" and .files == ["src/contract.py", "tests/task-contract.bats"] and .write_allowances == .files and (.contract_digest | test("^[0-9a-f]{64}$"))' "$contract"
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" read "$ROOT" "09-PLAN-write-contract"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state": "planned"'* ]]
}

@test "state permits legal transitions and rejects illegal ones" {
  bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  run bash "$SCRIPT" state "$ROOT" "09-PLAN-write-contract" dispatched
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" state "$ROOT" "09-PLAN-write-contract" verified
  [ "$status" -ne 0 ]
  [[ "$output" == *"illegal state transition"* ]]
}

@test "rejects traversal, unknown task, malformed plan, and duplicate drift" {
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "missing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown task"* ]]
  cp "$PLAN" "$ROOT/bad.md"
  perl -pi -e 's#</task>##' "$ROOT/bad.md"
  run bash "$SCRIPT" open "$ROOT/bad.md" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"malformed PLAN"* ]]
  bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  perl -pi -e 's/Implement the writer/Changed/' "$PLAN"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN digest mismatch"* ]]
}

@test "rejects unsafe repo-relative paths" {
  perl -pi -e 's#src/contract.py#../escape#' "$PLAN"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo-relative"* ]]
}

@test "rejects symlinked contract directories and duplicate task blocks" {
  mkdir -p "$ROOT/real-tasks"
  mkdir -p "$ROOT/.lbwc-planning"
  ln -s "$ROOT/real-tasks" "$ROOT/.lbwc-planning/.contracts"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"* ]]
  rm "$ROOT/.lbwc-planning/.contracts"
  cp "$PLAN" "$ROOT/dupe.md"
  perl -0777 -pi -e 's#</tasks>#</tasks><tasks></tasks>#' "$ROOT/dupe.md"
  run bash "$SCRIPT" open "$ROOT/dupe.md" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate tasks"* ]]
}

@test "reopen after transition is idempotent, but source drift fails" {
  bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  bash "$SCRIPT" state "$ROOT" "09-PLAN-write-contract" dispatched
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -eq 0 ]
  perl -pi -e 's/Implement the writer/Changed/' "$PLAN"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN digest mismatch"* ]]
}

@test "state rejects a tampered contract" {
  bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  perl -pi -e 's/"schema_version": 2/"schema_version": 99/' "$ROOT/.lbwc-planning/.contracts/tasks/09-PLAN-write-contract.json"
  run bash "$SCRIPT" state "$ROOT" "09-PLAN-write-contract" dispatched
  [ "$status" -ne 0 ]
  [[ "$output" == *"contract digest mismatch"* || "$output" == *"invalid contract"* ]]
}

@test "open rejects injected or non-exact role argument forms" {
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" --role 'coding-dijkstra;touch /tmp/pwned'
  [ "$status" -ne 0 ]
  [ ! -e /tmp/pwned ]
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" --bad coding-dijkstra
  [ "$status" -ne 0 ]
}

@test "state rejects a tampered roles sequence" {
  bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  perl -pi -e 's/coding-dijkstra-critic/not-the-configured-critic/' "$ROOT/.lbwc-planning/.contracts/tasks/09-PLAN-write-contract.json"
  run bash "$SCRIPT" state "$ROOT" "09-PLAN-write-contract" dispatched
  [ "$status" -ne 0 ]
  [[ "$output" == *"contract digest mismatch"* || "$output" == *"invalid contract"* ]]
}

@test "issue writes a command contract with exact team and role allowances" {
  run bash "$SCRIPT" issue "$ROOT" "docs-readme" \
    --command docs --role docs --team solo --job "Update README" \
    --write-allowance README.md
  [ "$status" -eq 0 ]
  contract="$output"
  ROOT_CANON="$(cd "$ROOT" && pwd -P)"
  run jq --arg root "$ROOT_CANON" -e '
    .schema_version == 2
    and .source_kind == "command"
    and .command_name == "docs"
    and .created_by == "main"
    and .project_root == $root
    and .team_mode == "solo"
    and .role == "docs"
    and .roles == ["docs"]
    and .write_allowances == ["README.md"]
    and .allowances_by_role == {docs:["README.md"]}
    and (.contract_digest | test("^[0-9a-f]{64}$"))
  ' "$contract"
  [ "$status" -eq 0 ]
}

@test "issue rejects an allowance for a role outside the exact team before writing" {
  run bash "$SCRIPT" issue "$ROOT" "bad-team" \
    --command build --role python-engineer --team pair --job "Implement" \
    --role-write-allowance test-dev:tests/unit.py
  [ "$status" -ne 0 ]
  [[ "$output" == *"allowance role is not in contract team"* ]]
  [ ! -d "$ROOT/.lbwc-planning/.contracts/tasks" ] || [ -z "$(find "$ROOT/.lbwc-planning/.contracts/tasks" -type f -print -quit)" ]
}

@test "verify rejects command job drift and a tampered contract" {
  contract=$(bash "$SCRIPT" issue "$ROOT" "debug-one" \
    --command debug --role debugger --team solo --job "Find root cause")
  run bash "$SCRIPT" verify "$contract" "$ROOT" --job "Different brief"
  [ "$status" -ne 0 ]
  [[ "$output" == *"job digest mismatch"* ]]
  perl -pi -e 's/"command_name": "debug"/"command_name": "qa"/' "$contract"
  run bash "$SCRIPT" verify "$contract" "$ROOT" --job "Find root cause"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contract digest mismatch"* ]]
}

@test "open binds a plan grouping and rejects allowances outside PLAN before writing" {
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --role coding-dijkstra --team pair --group implementation \
    --job "Implement the writer" \
    --write-allowance src/contract.py \
    --write-allowance tests/task-contract.bats
  [ "$status" -eq 0 ]
  contract="$output"
  run jq -e '
    .schema_version == 2
    and .source_kind == "plan"
    and .team_mode == "pair"
    and .group_name == "implementation"
    and .roles == ["coding-dijkstra", "coding-dijkstra-critic"]
    and .allowances_by_role["coding-dijkstra"] == ["src/contract.py", "tests/task-contract.bats"]
    and .allowances_by_role["coding-dijkstra-critic"] == []
  ' "$contract"
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --role coding-dijkstra --team pair --group outside \
    --job "Implement" --write-allowance src/not-in-plan.py
  [ "$status" -ne 0 ]
  [[ "$output" == *"allowance is not declared by PLAN"* ]]
}

@test "issue rejects protected framework paths before contract mutation" {
  local protected
  for protected in \
    config/subagent-critical-execution.txt \
    config/destructive-commands.txt \
    scripts/file-guard.sh \
    scripts/task-contract.sh \
    scripts/agent-lifecycle.sh \
    .lbwc-planning/.agent-manifest.json \
    .lbwc-planning/.contracts/tasks/forged.json \
    .claude/agents/forged.md
  do
    run bash "$SCRIPT" issue "$ROOT" "protected" \
      --command test --role python-engineer --team solo --job "mutate policy" \
      --write-allowance "$protected"
    [ "$status" -ne 0 ]
    [[ "$output" == *"protected path"* ]]
  done
  [ ! -d "$ROOT/.lbwc-planning/.contracts/tasks" ] || [ -z "$(find "$ROOT/.lbwc-planning/.contracts/tasks" -type f -print -quit)" ]
}

@test "repeated command issue creates a new run contract" {
  first=$(bash "$SCRIPT" issue "$ROOT" repeat \
    --command qa --role qa --team solo --job "verify")
  second=$(bash "$SCRIPT" issue "$ROOT" repeat \
    --command qa --role qa --team solo --job "verify")
  [ "$first" != "$second" ]
  [ -f "$first" ]
  [ -f "$second" ]
}

@test "issue writes schema 3 typed capabilities in an explicit temporary control root" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/team-one"
  mkdir -p "$control_root"
  run bash "$SCRIPT" issue "$ROOT" "team-scope" \
    --command team --role web-engineer --team solo --job "Implement the web scope" \
    --control-root "$control_root" \
    --write-capability file:src/web/index.ts \
    --write-capability directory:tests/web
  [ "$status" -eq 0 ]
  local contract="$output"
  control_root=$(cd -P "$control_root" && pwd -P)
  [ "$contract" = "$control_root/contracts/tasks/$(basename "$contract")" ]
  run jq -e '
    .schema_version == 3
    and .control_root == "'"$control_root"'"
    and .capabilities_by_role["web-engineer"] == [
      {access:"write",kind:"file",path:"src/web/index.ts"},
      {access:"write",kind:"directory",path:"tests/web"}
    ]
    and .write_allowances == ["src/web/index.ts", "tests/web"]
    and .runtime_kind == "native-team"
    and .communication_policy == "native-team"
    and .requested_backend == "in_process"
    and .resolved_backend == "in_process"
  ' "$contract"
  [ "$status" -eq 0 ]
}

@test "schema 3 binds validated backend metadata into the contract digest" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/team-backend" contract
  mkdir -p "$control_root"

  run bash "$SCRIPT" issue "$ROOT" "team-backend" \
    --command team --role web-engineer --team solo --job "Implement the web scope" \
    --control-root "$control_root" --requested-backend tmux --resolved-backend tmux \
    --write-capability directory:src/web
  [ "$status" -eq 0 ]
  contract="$output"
  run jq -e '.schema_version == 3 and .requested_backend == "tmux" and .resolved_backend == "tmux"' "$contract"
  [ "$status" -eq 0 ]

  jq '.resolved_backend = "in_process"' "$contract" > "$ROOT/tampered-contract.json"
  mv "$ROOT/tampered-contract.json" "$contract"
  run bash "$SCRIPT" verify "$contract" "$ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"contract digest mismatch"* ]]
}

@test "schema 3 root capability is limited to the team command" {
  run bash "$SCRIPT" issue "$ROOT" "not-team" \
    --command test --role web-engineer --team solo --job "scope" \
    --write-capability directory:.
  [ "$status" -ne 0 ]
  [[ "$output" == *"repository root capability is only valid for team"* ]]
}

@test "schema 3 state updates use the temporary control root only" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/team-state" contract id
  rm -rf "$ROOT/.lbwc-planning"
  mkdir -p "$control_root"
  contract=$(bash "$SCRIPT" issue "$ROOT" "team-state" \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --write-capability directory:src/web)
  id=$(basename "$contract" .json)

  run bash "$SCRIPT" state "$ROOT" "$id" dispatched

  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/.lbwc-planning" ]
  [ ! -e "$control_root/contracts/.lock" ]
}

@test "schema 3 rejects unsupported runtime and communication policies" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/team-policy"
  mkdir -p "$control_root"

  run bash "$SCRIPT" issue "$ROOT" "bad-runtime" \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --runtime-kind unknown-runtime \
    --write-capability directory:src/web
  [ "$status" -ne 0 ]
  [[ "$output" == *"runtime_kind"* ]]

  run bash "$SCRIPT" issue "$ROOT" "bad-communication" \
    --command team --role web-engineer --team solo --job "scope" \
    --control-root "$control_root" --communication-policy unknown-policy \
    --write-capability directory:src/web
  [ "$status" -ne 0 ]
  [[ "$output" == *"communication_policy"* ]]
}

@test "open writes schema 3 when backend and control-root flags are set" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/plan-schema3"
  mkdir -p "$control_root"

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root"
  [ "$status" -eq 0 ]
  local contract="$output"
  control_root=$(cd -P "$control_root" && pwd -P)
  [ "$contract" = "$control_root/contracts/tasks/$(basename "$contract")" ]
  run jq -e --arg root "$control_root" '
    .schema_version == 3
    and .source_kind == "plan"
    and .requested_backend == "tmux"
    and .resolved_backend == "tmux"
    and .control_root == $root
    and .runtime_kind == "native-team"
    and .communication_policy == "native-team"
    and .capabilities_by_role["coding-dijkstra"] == [
      {access:"write",kind:"file",path:"src/contract.py"},
      {access:"write",kind:"file",path:"tests/task-contract.bats"}
    ]
    and .write_allowances == ["src/contract.py", "tests/task-contract.bats"]
  ' "$contract"
  [ "$status" -eq 0 ]
}

@test "open without backend flags still writes schema 2" {
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract"
  [ "$status" -eq 0 ]
  run jq -e '
    .schema_version == 2
    and (has("requested_backend") | not)
    and (has("resolved_backend") | not)
    and (has("control_root") | not)
  ' "$output"
  [ "$status" -eq 0 ]
}

@test "open rejects a partial schema 3 flag set before writing" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/plan-partial"
  mkdir -p "$control_root"

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux
  [ "$status" -ne 0 ]
  [ ! -d "$ROOT/.lbwc-planning/.contracts/tasks" ] || [ -z "$(find "$ROOT/.lbwc-planning/.contracts/tasks" -type f -print -quit)" ]
  [ ! -d "$control_root/contracts/tasks" ] || [ -z "$(find "$control_root/contracts/tasks" -type f -print -quit 2>/dev/null)" ]

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" --control-root "$control_root"
  [ "$status" -ne 0 ]
}

@test "open --assert-snapshot compares flags and does not copy snapshot backends" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/plan-assert"
  mkdir -p "$control_root"
  control_root=$(cd -P "$control_root" && pwd -P)
  local snapshot="$ROOT/runtime-snapshot.json"
  jq -n --arg root "$control_root" '{
    requested_backend: "tmux",
    resolved_backend: "tmux",
    control_root: $root
  }' > "$snapshot"

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot"
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 3 and .requested_backend == "tmux" and .resolved_backend == "tmux"' "$output"
  [ "$status" -eq 0 ]

  jq '.requested_backend = "in_process" | .resolved_backend = "in_process"' "$snapshot" > "$ROOT/snapshot-mismatch.json"
  mv "$ROOT/snapshot-mismatch.json" "$snapshot"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot" --group mismatch
  [ "$status" -ne 0 ]
  [ ! -e "$control_root/contracts/tasks/09-PLAN-write-contract-mismatch.json" ]

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend in_process --resolved-backend in_process --control-root "$control_root" \
    --assert-snapshot "$snapshot" --group copied
  [ "$status" -eq 0 ]
  run jq -e '.requested_backend == "in_process" and .resolved_backend == "in_process"' "$output"
  [ "$status" -eq 0 ]
}

@test "issue --assert-snapshot compares flags and does not copy snapshot backends" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/team-assert"
  mkdir -p "$control_root"
  control_root=$(cd -P "$control_root" && pwd -P)
  local snapshot="$ROOT/team-runtime-snapshot.json"
  jq -n --arg root "$control_root" '{
    requested_backend: "tmux",
    resolved_backend: "tmux",
    control_root: $root
  }' > "$snapshot"

  run bash "$SCRIPT" issue "$ROOT" "team-assert" \
    --command team --role web-engineer --team solo --job "Implement the web scope" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot" --write-capability directory:src/web
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 3 and .requested_backend == "tmux" and .resolved_backend == "tmux"' "$output"
  [ "$status" -eq 0 ]

  jq '.requested_backend = "in_process" | .resolved_backend = "in_process"' "$snapshot" > "$ROOT/team-snapshot-mismatch.json"
  mv "$ROOT/team-snapshot-mismatch.json" "$snapshot"
  run bash "$SCRIPT" issue "$ROOT" "team-assert-mismatch" \
    --command team --role web-engineer --team solo --job "Implement the web scope" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot" --write-capability directory:src/web
  [ "$status" -ne 0 ]
  [ ! -e "$control_root/contracts/tasks/"*team-assert-mismatch* ]
}

@test "open --assert-snapshot accepts a freeze snapshot that omits control_root" {
  local control_root="$ROOT/.temporary-agent-runfiles/runs/freeze-shape"
  mkdir -p "$control_root"
  control_root=$(cd -P "$control_root" && pwd -P)
  local snapshot="$ROOT/freeze-shaped-snapshot.json"
  jq -n '{
    requested_backend: "tmux",
    resolved_backend: "tmux"
  }' > "$snapshot"

  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot" --group freeze-shape
  [ "$status" -eq 0 ]
  run jq -e '.schema_version == 3 and .requested_backend == "tmux" and .resolved_backend == "tmux"' "$output"
  [ "$status" -eq 0 ]

  jq '.resolved_backend = "in_process"' "$snapshot" > "$ROOT/freeze-mismatch.json"
  mv "$ROOT/freeze-mismatch.json" "$snapshot"
  run bash "$SCRIPT" open "$PLAN" "$ROOT" "write contract" \
    --requested-backend tmux --resolved-backend tmux --control-root "$control_root" \
    --assert-snapshot "$snapshot" --group freeze-mismatch
  [ "$status" -ne 0 ]
}
