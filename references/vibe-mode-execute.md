## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

**Execute-mode invariant:** Parallel execution is only valid when dependency-aware routing finds real parallel delegate work and the live tool set can create real team-scoped teammates. If routing selects serialized subagents, turbo/internal direct, or real team semantics cannot be established, execute mode must fall back to explicit non-team execution. Never simulate a team with background `Agent` spawns that lack `team_name`.

**Spawn path (hard branch):** After the frozen snapshot exists, choose exactly one spawn path. A main session must not do both.

- If `snapshot.resolved_backend` is `tmux`: do not follow `execute-protocol.md` native Agent spawn. After generation and `state ... dispatched`, run `scripts/tmux-spawn-group.sh dispatch` as documented below.
- If `snapshot.resolved_backend` is `in_process`: follow `execute-protocol.md` native Agent spawn. Do not run the tmux spawn driver.

Read `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/execute-protocol.md` for plan loading, contracts, verification, and commits. Use its Agent spawn steps only on the `in_process` branch.

**Orchestrator read-scope:** Do NOT read product source files. Your job is orchestration: read plans, check summaries, and spawn Dev for remaining work. If you need product-code understanding to route or sequence, delegate that to Dev.

Before reading:
**Step 0, pre-normalize filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
**Step 1, parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /lbwc:init first."
   - No PLAN.md in phase dir: STOP "Phase {NN} has no plans. Run `/lbwc:vibe --plan {NN}` first."
   - All plans have SUMMARY.md: cautious/standard -> WARN + confirm. Confident/pure-vibe -> warn + auto-continue.
   - **Milestone path guard:** If `{phase_dir}` contains `.lbwc-planning/milestones/`, STOP "Cannot execute inside archived milestones." This prevents writing artifacts into shipped milestone directories.
3. **Compile context:** If `config_context_compiler=true`, run:
   - `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
   - `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} qa {phases_dir}`
   Include compiled context paths in Dev and QA task descriptions. When referencing `.context-dev.md`, describe it as: "compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions). It also includes phase operational context (goal, conventions, active plan, research findings, changed files, code slices)." When referencing `.context-qa.md`, describe it as: "compiled context. It includes milestone scope decisions and phase verification context (success criteria, requirements, conventions to check)."
  If `TODO_SELECTED_JSON` already exists from the numbered-todo path and `DETAIL_STATUS=ok`, reuse the already-loaded detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.`

  Otherwise, if a ref hash was extracted during Input Parsing, load extended detail now:
   ```bash
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh get {hash}
   ```
  Parse the JSON output. If `status` is `"ok"`, include the detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.` If `status` is `"not_found"` or `"error"`, run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh detail-warning {hash}` and continue without detail. Do not block. This provides the executing agent with the rich context that motivated the work item.

Then freeze or validate the runtime snapshot as in Frozen snapshot spawn dispatch. Cancel remains the snapshot helper in Execute mode: it only writes `{PHASE_DIR}/.runtime-cancelled.json`. After the snapshot exists, take the hard spawn branch above. On `in_process`, read the protocol file and execute Steps 2-5 including Agent spawn. On `tmux`, use the protocol for non-spawn steps only and dispatch through the spawn driver.

## Frozen snapshot spawn dispatch

This is the same dispatch as `/lbwc:build`. `{PHASE_DIR}` and `{PROJECT_ROOT}` are already resolved by Execute mode. `{LINK}` is the plugin root from Context. Cite `{LINK}/references/tmux-spawn-protocol.md` on the tmux branch. Do not invent a second orchestrator.

Copy snapshot backends into CLI flags. Control root is `{PROJECT_ROOT}/.lbwc-planning`, the freeze `--planning-dir`. When `snapshot.requested_backend` equals `snapshot.resolved_backend`, pass those values plus `--control-root` and `--assert-snapshot` so `open` cannot disagree with the snapshot. When they differ, that is the already-frozen `comms_fallback` case: omit the schema 3 backend flags (`open` requires matching backends), then follow the native Agent path.

```bash
SNAPSHOT_PATH="{PHASE_DIR}/.runtime-snapshot.json"
CONTROL_ROOT="{PROJECT_ROOT}/.lbwc-planning"
REQUESTED_BACKEND=$(jq -r '.requested_backend' "$SNAPSHOT_PATH")
RESOLVED_BACKEND=$(jq -r '.resolved_backend' "$SNAPSHOT_PATH")
OPEN_BACKEND_ARGS=()
if [ "$REQUESTED_BACKEND" = "$RESOLVED_BACKEND" ]; then
  OPEN_BACKEND_ARGS=(--requested-backend "$REQUESTED_BACKEND" --resolved-backend "$RESOLVED_BACKEND" --control-root "$CONTROL_ROOT" --assert-snapshot "$SNAPSHOT_PATH")
fi
CONTRACT_PATH=$(bash "{LINK}/scripts/task-contract.sh" open "$PLAN_PATH" "{PROJECT_ROOT}" "$TASK_NAME" --role "$ROLE" --team "$TEAM_MODE" --group "$GROUP_NAME" --job "$BRIEF" "${OPEN_BACKEND_ARGS[@]}" "${CONTRACT_ALLOWANCE_ARGS[@]}")
TASK_ID=$(basename "$CONTRACT_PATH" .json)
```

Pass the contract path, task id, job, team mode, identical allowance arguments, and `--execution-backend "$RESOLVED_BACKEND"` to one generator invocation. Append `--execution-backend "$RESOLVED_BACKEND"` to the `agent-generator.sh` call in `execute-protocol.md`. The main session owns `open`. Workers never create or modify contracts. If generation fails, leave that grouping contract `planned` and report the error.

Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation. Stop on contract, generator, preflight, provision, split-group, or bus failure. Do not silently switch to in-process except the already-frozen `comms_fallback` case above.

If `snapshot.resolved_backend` is `in_process`, keep the native Agent path: spawn every generated name together in the same turn with `Agent(...)` as `@references/agent-spawn-protocol.md` requires. Do not run `tmux-spawn-group.sh`.

If `snapshot.resolved_backend` is `tmux`, follow `{LINK}/references/tmux-spawn-protocol.md` on this branch only. Do not call native Agent. After generation and `state ... dispatched`, run the spawn driver. `MAIN_ID` is the live orchestrator session `${CLAUDE_SESSION_ID:-}`. Fail closed when it is empty.

   ```bash
   MAIN_ID="${CLAUDE_SESSION_ID:-}"
   [ -n "$MAIN_ID" ] || { echo "LBWC: CLAUDE_SESSION_ID is required for tmux spawn" >&2; exit 1; }
   TIMEOUT_MS=$(jq -r '.tmux_execution.comms_latency_tolerance_ms' "$SNAPSHOT_PATH")
   CONTRACT_DIGEST=$(jq -r '.contract_digest' "$CONTRACT_PATH")
   bash "{LINK}/scripts/tmux-spawn-group.sh" dispatch --project-root "{PROJECT_ROOT}" --control-root "$CONTROL_ROOT" --main-id "$MAIN_ID" --contract-id "$TASK_ID" --contract-digest "$CONTRACT_DIGEST" --spawn-ready-text "$GENERATOR_OUTPUT" --job "$BRIEF" --timeout-ms "$TIMEOUT_MS"
   ```

   Observe the helper JSON summary as the grouping reports. Then continue contract state, verification, and commits from `execute-protocol.md`. After the grouping is terminal, apply protocol cleanup (`kill-agent` or `kill-session`) from the frozen cleanup policy.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/normalize-plan-filenames.sh`
- `scripts/todo-details.sh`
- `scripts/todo-lifecycle.sh`
