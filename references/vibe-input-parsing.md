# LBWC Vibe Input Parsing

## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

## Generated Agent Authority

For every agent spawn, follow `references/agent-spawn-protocol.md`. The main
session issues the command contract, runs `scripts/agent-generator.sh`, and
uses its `SPAWN_READY` name and printed settings exactly. Generated output is
the sole authority for name, model, effort, and turn limit. Do not select them
from a static model profile. Every spawn below uses the generic contract-issuing
generator protocol.


Loaded via `@${CLAUDE_PLUGIN_ROOT}/references/vibe-input-parsing.md` from `commands/vibe.md` to resolve `/lbwc:vibe` arguments and state-driven routing.

## Pre-Parsing and Todo Resolution (VIBE-IP-01)

**Pre-parse: todo number resolution.** If $ARGUMENTS is a bare integer (matches `^[0-9]+$` with no other text or flags), inspect the persisted session snapshot from the latest `/lbwc:list-todos` invocation before deciding whether this integer is a todo or a phase target:
```bash
bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh" snapshot-show
```
- If the snapshot is present and `filter=null`, resolve the integer as a todo selection via:
  ```bash
  bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-todo-item.sh" <N> --session-snapshot --require-unfiltered --validate-live
  ```
  If `status` is `"ok"`, preserve `TODO_SELECTED=true`, store the full payload as `TODO_SELECTED_JSON`, replace $ARGUMENTS with the item's `command_text`, and keep the resolved `ref`/`state_path` metadata for later pickup. If the resolved `state_path` points under `.lbwc-planning/milestones/`, STOP with: `This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/migrate-orphaned-state.sh .lbwc-planning'.` Do not continue using the archived description as live work input.
- If the snapshot is present and `filter` is non-null, do **not** treat the integer as a claimable backlog todo. Preserve the existing bare phase-number path instead. If the integer later fails to resolve as a valid phase target, fail closed with: `Current list view is filtered, rerun unfiltered /lbwc:list-todos before using /lbwc:vibe N as a todo pickup.`
- If the snapshot is missing or malformed, preserve the existing bare phase-number path. Do **not** silently fall back to live unfiltered backlog resolution for todo pickup.

If `TODO_SELECTED_JSON` exists and its `ref` is non-null, eagerly load detail during Input Parsing, before routing commits to the todo-derived request:
```bash
bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh" get {hash}
```
If `status` is `"ok"`, store `DETAIL_STATUS=ok`, `detail.context`, and `detail.files` for later use. If `status` is `"not_found"` or `"error"`, record the matching `DETAIL_STATUS` value and run:
```bash
bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh" detail-warning {hash}
```
Continue without detail.

**Pre-parse: ref tag extraction.** Before evaluating paths below, check if $ARGUMENTS ends with a `(ref:HASH)` suffix (8 hex characters). If found, extract the hash and strip the ref tag (including any leading space) from $ARGUMENTS. The cleaned arguments are used for all subsequent parsing, the ref must not interfere with flag detection, keyword routing, or mode selection. Store the extracted hash for later use. If `TODO_SELECTED_JSON` already exists from the numbered-todo path above, reuse its resolved ref/detail metadata and do not reload detail here. For non-todo manual `(ref:HASH)` inputs, defer detail loading until an action-bearing mode actually needs it. If no ref tag is found, there is no hash to store.

**Todo pickup boundary (non-negotiable):** A numbered todo selected through `TODO_SELECTED_JSON` may only be claimed once routing has actually committed to the todo-derived request and any AskUserQuestion confirmation gate has completed successfully. If routing falls back to a phase-number path, stops on a guard, or the user declines confirmation, leave the todo untouched. Manual text and manual `(ref:HASH)` inputs never trigger pickup.

When the chosen route does commit to the todo-derived request, claim it exactly once before entering the chosen mode body by piping `TODO_SELECTED_JSON` into:
```bash
bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh" pickup /lbwc:vibe {DETAIL_STATUS} {cleanup_policy}
```
Set `{cleanup_policy}` to `safe` when `DETAIL_STATUS=ok`. Otherwise set it to `keep`. If the helper returns `status="error"`, STOP with its `message` value. If it returns `status="partial"`, continue but surface the helper's `warning` value so cleanup state stays explicit.

Three input paths, evaluated in order:

## Path 1: Flag Detection (VIBE-IP-02)

Check $ARGUMENTS for flags. If any mode flag is present, go directly to that mode.

Lifecycle modes:
- `--plan [N]` -> Plan mode
- `--execute [N]` -> Execute mode
- `--discuss [N]` -> Discuss mode
- `--assumptions [N]` -> Assumptions mode
- `--verify [N]` -> Verify mode
- `--archive` -> Archive mode

Phase setup and mutation modes:
- `--scope` -> Scope mode
- `--add "desc"` -> Add Phase mode
- `--insert N "desc"` -> Insert Phase mode
- `--remove N` -> Remove Phase mode

Behavior modifiers (combinable with mode flags):
- `--effort <level>`: thorough|balanced|fast|turbo (overrides config)
- `--skip-qa`: skip post-build QA
- `--skip-audit`: skip non-UAT pre-archive audit checks (hard UAT gate still enforced)
- `--yolo`: skip all confirmation gates, auto-loop remaining phases
- `--plan=NN`: execute single plan (bypasses wave grouping)
- Bare integer `N`: targets phase N (works with any mode flag)

If flags present: skip confirmation gate (flags express explicit intent).

## Path 2: Natural Language Intent (VIBE-IP-03)

If $ARGUMENTS present but no flags detected, interpret user intent:
- Discussion keywords (talk, discuss, explore, think about, what about) -> Discuss mode
- Assumption keywords (assume, assuming, what if, what are you assuming) -> Assumptions mode
- Planning keywords (plan, scope, break down, decompose, structure) -> Plan mode
- Execution keywords (build, execute, run, do it, go, make it, ship it) -> Execute mode
- Verification keywords (verify, test, uat, check my work, acceptance test, walk through) -> Verify mode
- Phase mutation keywords (add, insert, remove, skip, drop, new phase) -> relevant Phase Mutation mode
- Completion keywords (done, ship, archive, wrap up, finish, complete) -> Archive mode
- Ambiguous -> AskUserQuestion with contextual options

Confirm the interpreted intent with AskUserQuestion before executing.

## Path 3: State Detection (VIBE-IP-04)

If no $ARGUMENTS, evaluate phase-detect.sh output. First match determines mode:

**Phase-detect error guard (NON-NEGOTIABLE):** If the output contains `phase_detect_error=true`, display:
"⚠ Phase detection failed. Run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh` manually to debug."
STOP. Do NOT manually scan for project state or improvise routing, incorrect routing can corrupt archived milestones.

**Misnamed plan auto-repair:** If the output contains `misnamed_plans=true`, normalize all phase directories before routing:
```bash
NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
if [ -f "$NORM_SCRIPT" ]; then
  for pdir in .lbwc-planning/phases/*/; do
    [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
  done
fi
```
Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
Then re-run phase-detect.sh and use updated output for routing below.

**State-driven routing prohibition (NON-NEGOTIABLE):** When state detection routes to a mode, call its confirmation gate (AskUserQuestion, see Confirmation Gate section below) in the same turn. Execute the mode inline after the user responds. Do NOT use TaskCreate, TaskUpdate, or any task management tool for state-driven routing. Those tools add overhead and delay execution. State routing is deterministic. The pre-computed data in the Context section provides all routing information. Do not spawn tasks or read protocol files for routing decisions. After confirmation (when required by the routing table), execute the mode inline. Modes that spawn agents (Scout, Lead, Dev) do so within their step-by-step flow. This delegates work units within a stage, not the stage pipeline itself.

<examples>
<example type="anti-pattern" label="WRONG, delegating the stage pipeline via TaskCreate">
State detects needs_uat_remediation → TaskCreate("Research"), TaskCreate("Plan"), TaskCreate("Execute") with blocking dependencies. The stages run as separate delegated tasks, breaking state management and losing orchestrator control between stages.
</example>
<example type="correct" label="RIGHT, inline orchestration with agent spawning per stage">
State detects needs_uat_remediation and enters the mode inline. Step 4 displays the main-session progress list (Research, Plan, Execute). Step 6 spawns Scout for research, advances state, spawns Lead for planning, advances again, spawns Dev for execution, and chains into re-verification.
</example>
</examples>

| Priority | Condition | Mode | Confirmation |
| --- | --- | --- | --- |
| 1 | `planning_dir_exists=false` | Init redirect | (redirect, no confirmation) |
| 2 | `project_exists=false` | Bootstrap | → AskUserQuestion: "No project defined. Set one up?" |
| 3 | `next_phase_state=needs_uat_remediation` | UAT Remediation | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} has unresolved UAT issues. Continue with remediation now?" |
| 3.5 | `next_phase_state=needs_qa_remediation` | QA Remediation | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} has QA failures. Continue with QA remediation?" |
| 4 | `next_phase_state=needs_reverification` | Re-verify | auto_uat=true: no confirmation. auto_uat=false: → AskUserQuestion: "Phase {NN} remediation complete. Run re-verification?" |
| 5 | `milestone_uat_issues=true` | Milestone UAT Recovery | (mode handles confirmation, see Milestone UAT Recovery steps) |
| 6 | `phase_count=0` | Scope | → AskUserQuestion: "Project defined but no phases. Scope the work?" |
| 7 | `next_phase_state=needs_verification` | Verify | (no confirmation, auto_uat intent or active UAT resume). **QA gate:** If `qa_after_uat_dormant=true` or `qa_reason=uat_cutover`, skip QA and stay in the UAT lane. Otherwise, if `qa_status=pending`, display "Phase {NN} QA is pending ({reason label}), running QA now." after mapping `qa_reason` through the reason labels below, then spawn QA inline first. This state also covers `all_done` milestones that were retargeted because authoritative pre-UAT QA on a completed no-UAT phase is stale/missing, fully built no-UAT phases retargeted back into verification when QA is still pending even with `auto_uat=false`, and active current-round UAT artifacts that must resume Verify instead of entering Re-verify preparation. If `qa_status=failed`, enter QA remediation inline only before UAT cutover. Only proceed to Verify mode when `qa_status` is `passed`, `remediated`, or explicitly dormant after UAT cutover. |
| 8 | `next_phase_state=needs_discussion` | Discuss | → AskUserQuestion: "Phase {NN} needs discussion before planning. Start discussion?" |
| 9 | `next_phase_state=needs_plan_and_execute` | Plan + Execute | → AskUserQuestion: "Phase {NN} needs planning and execution. Start?" |
| 10 | `next_phase_state=needs_execute` | Execute | → AskUserQuestion: "Phase {NN} is planned. Execute it?" |
| 11 | `next_phase_state=all_done` | Archive | → AskUserQuestion: "All phases complete. Run audit and archive?" (only when no `first_qa_attention_phase` remains) |

**all_done QA-attention fallback (pending):** When `next_phase_state=all_done`, `first_qa_attention_phase` is set, and `qa_attention_status=pending`, do **not** archive yet. Target `first_qa_attention_phase` / `first_qa_attention_slug` and continue into Verify mode instead. This is the stage-less resume path for a completed pre-UAT phase whose QA verification is still missing or stale, even when `auto_uat=false`. If that phase has any UAT state or artifact, QA attention is dormant and this fallback must not run.

**Earlier-work QA-attention fallback (failed):** When `next_phase_state` is still an earlier-work state (`needs_discussion`, `needs_plan_and_execute`, or `needs_execute`), but `first_qa_attention_phase` is set and `qa_attention_status=failed`, do **not** continue into that unrelated earlier work. Target `first_qa_attention_phase` / `first_qa_attention_slug` and continue into the existing QA Remediation mode instead. This is the stage-less resume path for a completed pre-UAT phase that already has phase-level QA findings and a persisted known-issues backlog, but has not written `.qa-remediation-stage` yet. If that phase has any UAT state or artifact, treat the QA metadata as dormant and do not enter QA Remediation.

**QA remediation resume priority (needs_qa_remediation), IMMEDIATE RESUME (NON-NEGOTIABLE):**
Persisted QA remediation / known-issues backlog is the authoritative plain `/lbwc:vibe` resume target. When `next_phase_state=needs_qa_remediation`, do **not** skip ahead to unrelated earlier discussion, planning, or execution work, close the QA backlog first, unless an active UAT remediation path is already higher priority.

**Re-verify after remediation (needs_reverification), IMMEDIATE EXECUTION (NON-NEGOTIABLE):**
When `next_phase_state=needs_reverification`, execute these steps inline in the same turn, do NOT create tasks, read protocol files, or perform any intermediate planning:
1. Run: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/prepare-reverification.sh {phase-dir}`
2. **Error guard:** If the script fails (non-zero exit), display the error message and **STOP**, do not attempt to enter Verify mode with stale/missing context.
3. Parse output: `archived=kept|in-round-dir|<original-uat-basename>`, `skipped=already_archived|ready_for_verify|cap_reached`, `round_file=...`, `phase=NN`, `layout=...`
  If `skipped=cap_reached`: display the UAT remediation cap banner and STOP. Use `max_rounds={N}` from the script output:
  ```text
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Reached maximum UAT remediation rounds ({N}).
    Review issues manually or adjust max_uat_remediation_rounds
    in config.json.
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```
  Do NOT refresh verify context or enter Verify mode.
4. If `archived=kept`: display "Phase UAT preserved. Starting fresh re-verification in round dir."
   If `archived=in-round-dir`: display "Archived previous UAT → {round_file}. Starting fresh re-verification."
   If `skipped=already_archived`: display "UAT already archived. Starting fresh re-verification."
   If `skipped=ready_for_verify`: display "Round {NN} remediation complete. Starting fresh re-verification."
    Otherwise, when `archived=` is the original phase-root UAT basename (flat/legacy layout), display "Archived previous UAT → {round_file}. Starting fresh re-verification."
5. Refresh verify context and UAT resume metadata for that phase:
  ```bash
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-uat-resume.sh "{phase-dir}"
  ```
  Use this refreshed output in place of the pre-computed verify blocks from Context.
  **uat_path validation (defense-in-depth):** If the refreshed `uat_path` does not already point at the current remediation round's round-scoped UAT path (`remediation/uat/round-{RR}/R{RR}-UAT.md` for round-dir layout, `remediation/round-{RR}/R{RR}-UAT.md` for legacy layout), run:
  ```bash
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh get-or-init "{phase-dir}" major
  ```
  Parse `round=RR` and `layout=...`, then override `uat_path` with the matching round-scoped path for that layout before entering Verify mode.
6. **Continue directly into Verify mode below** for that phase, do NOT stop, do NOT tell the user to run a separate command.

The `needs_reverification` state fires regardless of `auto_uat`, remediation always requires re-verification. The `auto_uat` flag only controls whether the user is prompted for confirmation.

**auto_uat verification / active UAT resume (needs_verification):** When `next_phase_state=needs_verification`, **continue directly into Verify mode below** targeting phase `{next_phase}` (from phase-detect output), do NOT stop and tell the user to run a separate command. Verify mode runs the CHECKPOINT loop **inline in this conversation** via AskUserQuestion, do NOT spawn a QA agent or any subagent for UAT (see Verify mode's inline execution rule). This state fires when `auto_uat=true` and a completed phase has no UAT verification yet, regardless of whether later phases still need work. It also fires when phase-detect reports an active current-round UAT blocker (`uat_blocking_status=active`): resume the existing UAT so in-progress human test state is not archived by Re-verify preparation. After verification completes, the next `/lbwc:vibe` call re-runs phase-detect and routes to the next pending phase.

**QA gate before UAT (needs_verification), NON-NEGOTIABLE:**
Before entering Verify mode (UAT), check `qa_status` from phase-detect output:
- `qa_after_uat_dormant=true` or `qa_reason=uat_cutover`: proceed to Verify mode (UAT) without running QA. QA remediation is a pre-UAT route only. Once any UAT state or artifact exists for the target phase, stale QA remediation metadata for that phase is traceability-only and must not send `/lbwc:vibe` back into QA Remediation.
- `qa_status=passed` or `qa_status=remediated`: proceed to Verify mode (UAT). These values mean VERIFICATION.md exists with PASS and the product code has not changed since QA verified it (staleness check via `verified_at_commit`).
- `qa_status=pending` (no VERIFICATION.md, malformed/untrusted VERIFICATION.md, deterministic gate rerun, or stale PASS): display "Phase {NN} QA is pending ({reason label}), running QA now." and spawn QA inline first. Resolve `{reason label}` from `qa_reason`. If `qa_reason=none` or is empty, use `qa_attention_reason`. If both are empty/none, omit the parenthetical.

  **QA pending artifact and gate reason labels:**
  - `missing_verification_artifact` → `no verification artifact exists`
  - `verification_result_missing` → `verification result is missing`
  - `verification_result_unrecognized` → `verification result is unrecognized`
  - `qa_gate_rerun_required` → `the QA gate requires a rerun`
  - `qa_gate_output_missing` → `the QA gate did not return a routing decision`

  **Repository freshness reason labels:**
  - `working_tree_changed` → `the working tree changed after QA`
  - `git_status_failed` → `git status failed during freshness check`
  - `git_log_failed` → `git log failed during freshness check`
  - `product_commit_unavailable` → `no product-code commit could be resolved`

  **Product freshness reason labels:**
  - `verified_at_commit_mismatch` → `product code changed since QA`
  - `product_changed_after_verification` → `product code changed after QA`
  - `freshness_baseline_unavailable` → `QA freshness could not be proven`
  - Unknown non-empty token → use the token verbatim.

  Then continue with QA:
  - If the phase-level verification artifact does not yet exist, backfill tracked known issues from completed summaries before QA starts:
    ```bash
    bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" sync-summaries "{phase-dir}" 2>/dev/null || true
    ```
    This backfill is only for the first phase-level QA run after execution. Do not reuse it for round-scoped remediation verification or generic stale-verification reruns.
  ```bash
  bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{QA-output-path}" 2>/dev/null || true
  ```
  After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:
  ```bash
  bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
  ```
  Then run the deterministic gate:
  ```bash
  bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-result-gate.sh" "{phase-dir}"
  ```
  **Follow `qa_gate_routing` output literally, no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
  - `qa_gate_routing=PROCEED_TO_UAT` → proceed to Verify mode (UAT)
  - `qa_gate_routing=REMEDIATION_REQUIRED` → init QA remediation: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh init {phase-dir}`, then enter QA Remediation mode below. If `qa_gate_known_issues_override=true`, the contract verification passed but `{qa_gate_known_issue_count}` unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
  - `qa_gate_routing=QA_RERUN_REQUIRED` → re-spawn QA agent immediately (max 2 retries). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain {qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check, do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified {qa_gate_plans_verified_count}/{qa_gate_plan_count} plans. Every plan in the phase must be verified, include all plan IDs in plans_verified." If QA fails to produce a valid result after 2 re-runs, STOP and escalate to user: "QA failed to produce a valid VERIFICATION.md after {N} attempts. Manual intervention needed."
- `qa_status=failed` (VERIFICATION.md exists with FAIL/PARTIAL): init QA remediation and enter QA Remediation mode
- `qa_status=remediating`: should not reach here (phase-detect routes to `needs_qa_remediation` first)
- `--skip-qa` flag: bypass contract-QA execution, but **do not** bypass unresolved phase known issues. UAT still cannot proceed while `{phase-dir}/known-issues.json` contains tracked issues.

**QA Remediation mode (needs_qa_remediation), cross-session recovery:**
When `next_phase_state=needs_qa_remediation`, resume QA remediation at the persisted stage. This is the cross-session recovery path, the inline execution path is in execute-protocol.md Step 4. This state also covers completed phases with no UAT yet when phase-level QA already wrote a PASS artifact but unresolved tracked known issues still force remediation before UAT can begin.

**Execution model:** This mode runs inline, the orchestrator manages stage transitions and spawns agents for the actual work within each stage. Do not decompose the stages into TaskCreate items, they are sequential steps of this conversation, not delegated tasks.

1. Read current state: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh get-or-init {phase-dir}`
  Parse output: `stage`, `round`, `round_dir`, `source_verification_path`, `source_fail_count`, `known_issues_path`, `known_issues_count`, `input_mode`, `verification_path`
   If remediation state was absent, `get-or-init` initializes round 01 before stage-specific routing. This is the deterministic stage-less resume path for a persisted known-issues backlog.
  <qa_remediation_artifact_contract>
  `round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` are authoritative host-repository paths from `qa-remediation-state.sh` metadata. Claude Code may run subagents from `.claude/worktrees/agent-*` sidechain CWDs. Pass these exact paths to Lead, Dev, and QA prompts and never rewrite them relative to the current CWD. Rewriting them relative to sidechain CWDs can write or read remediation artifacts from the wrong location and break resume or verification.
  </qa_remediation_artifact_contract>
  <qa_remediation_spawn_contract>
  QA remediation spawns are plain sequential subagent calls. Do not form an agent team (do not spawn teammates). Use plain sequential subagent Agent calls.

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

Use the remediation metadata paths above instead of forcing Claude worktree isolation or spawn cwd handoffs.
  </qa_remediation_spawn_contract>
  <qa_remediation_no_tool_circuit_breaker>
  After any QA remediation Lead, Dev, or QA subagent returns, follow the no-tool circuit breaker in `references/subagent-contracts.md` before artifact validation, deterministic gates, or state advancement. If it triggers, STOP without advancing `.qa-remediation-stage` and report the failed role and stage or task.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  </qa_remediation_no_tool_circuit_breaker>
2. Read remediation inputs.
- Round 01: phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`)
- Round 02+: previous round's `R{RR}-VERIFICATION.md`
- If `known_issues_count>0`, read `known_issues_path` as the authoritative unresolved known-issues backlog for this phase.
- `input_mode=verification` → remediate FAIL rows only
- `input_mode=known-issues` → remediate tracked known issues only
- `input_mode=both` → remediate both FAIL rows and tracked known issues in the same round

**Stage-specific actions:**

#### stage=plan

Create `R{RR}-PLAN.md` in `{round_dir}`.

**Inputs and classifications:**
- Read `source_verification_path` failed checks when `source_fail_count>0`, these are the current contract issues to fix
  - Read `known_issues_path` when `known_issues_count>0`, these tracked phase issues must clear before UAT can proceed
    - Round 01 uses the phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`).
    - Round 02+ first checks the previous round's `R{RR}-VERIFICATION.md`. If that artifact still contains FAIL checks, use it. If it passed QA but the deterministic gate still required another remediation round, carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs.
    - If `source_verification_path` is empty and `known_issues_count=0`, STOP and restore the earlier verification artifact that should have carried the unresolved FAILs before planning. Do NOT silently continue when the carried-forward phase-level source artifact is missing and there is no known-issues backlog to remediate.

**Deviation Classification (NON-NEGOTIABLE):** For each FAIL check in the source VERIFICATION.md, classify as exactly one of:
    **Implementation fixes:**
    - **`code-fix`**: The code/config must change to match the plan. The remediation plan MUST include tasks that modify the executable/config/test artifacts that actually implement the fix, not just planning or documentation files.

    **Plan and process decisions:**
    - **`plan-amendment`**: The deviation was a valid improvement over the original plan. The remediation plan MUST include a task to update the original PLAN.md with the actual approach and rationale, marking the deviation as resolved-by-amendment.
    - **`process-exception`**: Genuinely non-fixable retroactive issue (e.g., cannot un-batch a historical commit without risky rebase). The remediation plan must include the exception classification with explicit reasoning why it is non-fixable.

    **Documentation fixes:**
    - **`doc-fix`**: The documentation artifact is the product surface under test. Include `path: "docs/file.md"` for the named documentation path, and record that same path in the round summary.
  - **The plan MUST include at least one `code-fix`, `doc-fix`, or `plan-amendment` task if ANY FAIL check is classifiable as such.** A plan that classifies all FAIL checks as `process-exception` when code-fix, doc-fix, or plan-amendment alternatives exist is itself a defect. Documentation-only changes to SUMMARY.md deviations arrays are NOT a valid resolution for code/architecture deviations.
  - Include `fail_classifications:` YAML array in R{RR}-PLAN.md frontmatter.
    - `code-fix` / `process-exception` entries: `{id: "FAIL-ID", type: "code-fix|process-exception", rationale: "..."}`
    - `doc-fix` entries: `{id: "FAIL-ID", type: "doc-fix", path: "docs/file.md", rationale: "..."}`
    - `plan-amendment` entries MUST also identify the original plan being amended: `{id: "FAIL-ID", type: "plan-amendment", rationale: "...", source_plan: "01-01-PLAN.md"}`. `source_plan` must reference an original plan in the current phase only, never a sibling phase, archived milestone, or remediation plan.

**Known-issue contract:**
- Always include `known_issues_input:` and `known_issue_resolutions:` in R{RR}-PLAN.md frontmatter. When `known_issues_count=0` or `input_mode=verification`, set both to empty arrays (`known_issues_input: []` and `known_issue_resolutions: []`) rather than omitting them.
  - When `input_mode=known-issues` or `input_mode=both`, populate `known_issues_input:` with every carried known issue from `known_issues_path` using the canonical `{test,file,error}` JSON object-string shape already used for tracked issues.
  - When `input_mode=known-issues` or `input_mode=both`, populate `known_issue_resolutions:` with a matching entry for every carried known issue using `{test,file,error,disposition,rationale}` JSON object strings. Valid `disposition` values are `resolved`, `accepted-process-exception`, and `unresolved`.
    - `resolved` = this round fixes the issue and QA should no longer return it in `pre_existing_issues`
    - `accepted-process-exception` = QA must verify the issue is real but non-blocking for this phase, omit it from `pre_existing_issues`, and leave it visible via the summary/STATE backlog instead of reopening the round forever
    - `unresolved` = the issue remains blocking and the next round must continue to carry it
  - Do NOT omit the `known_issues_input` or `known_issue_resolutions` keys. Do NOT omit a carried known issue from either array. The deterministic gate treats missing coverage as a failed remediation round even if QA writes `PASS`.

**Plan recovery and Lead spawn:**
- Scope the plan to those failures: what to fix, which files, acceptance criteria
- Before probing for an existing plan, run the normalizer on `{round_dir}`:
    ```bash
    NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{round_dir}"
    fi
    ```
    If the canonical `{round_dir}/R{RR}-PLAN.md` exists after normalization, validate that exact artifact with the same validator command shown in the validation step below. If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`. If validation passes, do not spawn Lead again. Reuse the persisted plan and continue at the final post-validation state-advance step below. This preserves a valid plan written before an interrupted `stage=plan` resume instead of overwriting it.
  - The main session coordinates the remediation loop and spawns exactly one generated `lead` to write `{round_dir}/R{RR}-PLAN.md`.
  - Follow `references/agent-spawn-protocol.md`. Issue a solo read-only `lead` command contract for job `R{RR} remediation planning` with no write allowance. Run the generic `scripts/agent-generator.sh`, advance the contract to `dispatched`, and use the printed Agent-call parameters and `SPAWN_READY` name without re-resolving model, effort, or turns.
  - Use the generated name for both `subagent_type` and `name`. Omit team and worktree fields for this solo spawn. The Lead returns complete plan content. The main session writes the canonical plan before normalization and validation.
  - Lead prompt MUST include the authoritative `round_dir`, `source_verification_path`, `known_issues_path`, and output path `{round_dir}/R{RR}-PLAN.md`. The failed-check and known-issue inputs above. The deviation-classification and known-issue-resolution requirements above. And `Read the remediation plan template at /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-PLAN.md and follow its structure exactly.`
  - After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before normalization, plan validation, or state advancement. If it triggers, STOP without advancing `.qa-remediation-stage`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  - Normalize plan filenames before validation:
    ```bash
    NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{round_dir}"
    fi
    ```
  - Validate the exact QA remediation plan artifact before advancing:
    ```bash
    bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/validate-uat-remediation-artifact.sh plan "{round_dir}/R{RR}-PLAN.md"
    ```
    If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`. Do not search for an alternate PLAN.md.
  - After plan validation passes, advance state: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh advance {phase-dir}`

#### stage=execute

Execute each `R{RR}-PLAN.md` task sequentially through `references/agent-spawn-protocol.md`.

- Require each task to name a configured engineering anchor role, exact implementation files, exact test files, and acceptance criteria. Stop on missing or broad scope.
- Issue a pair or trio PLAN task contract from those exact files. Run the generic generator in matching `--pair` or `--trio` mode, advance the contract to `dispatched`, and spawn every generated member together with its printed Agent-call parameters.
- Generated agents modify only contracted files and return structured evidence. They do not commit or persist remediation summaries.
- The main session applies the no-tool circuit breaker, reviews the critic or `test-dev` verdict, commits accepted output, and appends the task evidence to `R{RR}-SUMMARY.md` using `templates/REMEDIATION-SUMMARY.md`.
- The summary frontmatter must aggregate `commit_hashes`, `files_modified`, and `deviations`. For known-issue input, include one `known_issue_outcomes` entry per carried issue.

No-tool invariant: treat unavailable tools as a provisioning failure, do not commit, do not advance state, and do not retry the same prompt.
  - After Dev completes without a no-tool provisioning failure, advance state: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh advance {phase-dir}`

#### stage=verify

Re-run QA.

**QA contract and artifact handling:**
- Run `compile-verify-context.sh --remediation-only {phase-dir}` and stop if it reports unavailable context.
- Follow `references/agent-spawn-protocol.md`. Issue a solo read-only `qa` command contract with no write allowance. Run the generic `scripts/agent-generator.sh qa` call, advance the contract to `dispatched`, and spawn it with the printed Agent-call parameters.
- QA returns the structured verification payload only. It never writes `{verification_path}`. The main session applies the no-tool circuit breaker, advances the observed contract through `running` and `awaiting_review`, validates the payload, and pipes it to `scripts/write-verification.sh "{verification_path}"`.
- On writer or gate failure, move the contract to `blocked` and stop. Mark it `verified` only after deterministic gate success. Keep the phase-level verification frozen as the original FAIL.

No-tool invariant: treat unavailable tools as a provisioning failure, do not persist verification, do not advance state, and do not retry the same prompt.
    - After the main-session writer persists `{verification_path}`, run `track-known-issues.sh sync-verification "{phase-dir}" "{verification_path}"` without suppressing failure. A sync failure moves the QA contract to `blocked` and stops state advancement.
    - `track-known-issues.sh promote-todos` is not an installed operation. Treat promotion as a Phase 3 dependency. Do not call it or claim surviving issues were promoted.
    - **Include in QA task description:** "In addition to verifying the remediation plan's own must_haves, you MUST re-verify each original FAIL from the VERIFICATION HISTORY section. For each FAIL_ID: if classified as code-fix, verify the code now matches the plan. If classified as doc-fix, verify the named documentation path now contains the required content. If classified as plan-amendment, verify the original PLAN.md has been updated with the actual approach and rationale. If classified as process-exception, verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL. If code-fix, doc-fix, or plan-amendment still appears viable, keep the FAIL open. Any original FAIL that has not been addressed by one of these four paths is still a FAIL."
    - **Include in QA task description when a KNOWN ISSUES block is present:** "Tracked phase known issues are not informational in remediation rounds. Re-check every carried known issue from `known_issues_input` / `known_issue_resolutions`. Return only still-blocking issues in `pre_existing_issues`. If a carried issue is verified as an `accepted-process-exception`, omit it from `pre_existing_issues`, confirm that the accepted non-blocking disposition is credible for this phase, and rely on the matching `known_issue_outcomes` entry to preserve visibility after the blocking registry clears. A clean remediation QA run must return an empty `pre_existing_issues` array for all resolved or accepted non-blocking carried issues so `{phase-dir}/known-issues.json` can clear."
      - The deterministic gate validates structural evidence only. QA must decide whether a `process-exception` is *actually* justified during this re-verification step, documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment.
  - **Phase 3 blocker:** current `qa-remediation-state.sh` does not populate source-verification metadata required by `qa-result-gate.sh`. Until that helper is extended and tested, STOP after persisting and syncing the round verification. Do not claim `PROCEED_TO_UAT` is reachable.
  - After the dependency is installed, run the deterministic gate:
    ```bash
    bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-result-gate.sh" "{phase-dir}"
    ```
    **Follow `qa_gate_routing` output literally, no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
    - `qa_gate_routing=PROCEED_TO_UAT` → advance to done: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh advance {phase-dir}`, then **refresh verify context before entering Verify mode**:
      ```bash
      bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
      ```
      Use this fresh verify context and **continue directly into Verify mode** for the phase
    - `qa_gate_routing=REMEDIATION_REQUIRED` → start new round: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/qa-remediation-state.sh needs-round {phase-dir}`, loop back to stage=plan. If `qa_gate_known_issues_override=true`, unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
    - `qa_gate_routing=QA_RERUN_REQUIRED` → re-spawn QA immediately (max 2 retries per round). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain {qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check, do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified {qa_gate_plans_verified_count}/{qa_gate_plan_count} plans. Every plan in the phase must be verified, include all plan IDs in plans_verified." If QA still fails to produce valid output, treat as REMEDIATION_REQUIRED.
    - **When `qa_gate_metadata_only_override=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round made no implementation changes, only planning/documentation updates. The round still depends on a code-fix path (or omitted fail_classifications), so the original failures cannot be considered resolved without implementation changes. ${qa_gate_phase_deviation_count} phase deviations remain recorded.` This override is the deterministic safety net for rounds that still depend on implementation changes. Pure plan-amendment rounds can pass when the original plan was actually updated, and pure process-exception rounds still need planning/remediation-artifact evidence, delivered docs/README changes alone do not count. The next round's `stage=plan` MUST classify each FAIL as code-fix, doc-fix, plan-amendment, or process-exception per the Deviation Classification rules above.
    - **When `qa_gate_process_exception_evidence_missing=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round has a clean verification result, but the gate cannot find recorded remediation-artifact evidence. Record an existing remediation RNN-PLAN.md/RNN-SUMMARY.md or a valid original phase PLAN.md before treating the process-exception as resolved.` Continue with a new remediation round via `/lbwc:vibe`.
    - **When `qa_gate_round_change_evidence_empty=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Display `⚠ QA remediation round recorded no change evidence, both files_modified and commit_hashes were empty. A PASS without any recorded changed files or commits cannot resolve prior FAILs.` The next round must produce real code/plan changes or capture justified remediation evidence instead of an empty summary.
    - **When `qa_gate_round_change_evidence_unavailable=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Pure `plan-amendment` and `process-exception` rounds are validated by their own evidence paths (source-plan coverage and process-exception artifact evidence respectively) rather than by code change evidence. Display `⚠ QA remediation round recorded change evidence that could not be verified as current-round work. Either the recorded files did not match any committed or current round-local remediation-artifact changes after the source verification commit, or the referenced commit_hashes could not be proven to belong to this round, so the actual changed files could not be trusted.` Restore explicit files_modified entries and/or round-local commit evidence anchored to the remediation round before treating the failures as resolved.

- **stage=done:** Re-compute verify context, then proceed to Verify mode (UAT) for the phase:
  ```bash
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context-for-uat.sh "{phase-dir}"
  ```
  Use this fresh verify context for the Verify mode CHECKPOINT loop.

**QA Remediation + UAT blocking:** QA remediation is a pre-UAT route only. Before any UAT state or artifact exists for a phase, active QA remediation blocks UAT and `needs_qa_remediation` takes priority over `needs_verification`. Once any UAT state or artifact exists for that phase, stay in the UAT lane. Stale QA remediation metadata remains on disk for traceability but is dormant and must not resume automatically.

**all_done + natural language:** If $ARGUMENTS describe new work (bug, feature, task) and state is `all_done`, route to Add Phase mode instead of Archive. Add Phase handles codebase context loading and research internally, do NOT spawn an Explore agent or do ad-hoc research before entering the mode.

**UAT remediation default:** When `next_phase_state=needs_uat_remediation`, plain `/lbwc:vibe` must read that phase's UAT report and continue remediation directly. Do NOT require the user to manually specify `--discuss` or `--plan`.

**Milestone UAT recovery:** When `milestone_uat_issues=true` and active phases are empty, the latest shipped milestone has unresolved UAT issues. Present the user with options: (a) create remediation phases to fix the UAT issues, (b) start fresh with new work (ignoring the stale UAT), or (c) skip for now (issues re-trigger next session). Use `milestone_uat_count` to determine how many phases are affected. When `milestone_uat_count` > 1, parse `milestone_uat_phase_dirs` (pipe-separated) to read all UAT reports and display a consolidated issue summary. Use `milestone_uat_major_or_higher` to determine severity context.

**Remediation + require_phase_discussion:** Both in-phase UAT remediation and milestone-level remediation phases skip the discussion step via pre-seeded phase context files. When `uat-remediation-state.sh get-or-init` runs for in-phase remediation, it appends the UAT report to the existing `{NN}-CONTEXT.md` and adds `pre_seeded: true` to its frontmatter, preserving the original discussion context while satisfying the `require_phase_discussion` gate. Milestone remediation phases created by `create-remediation-phase.sh` generate a fresh `{NN}-CONTEXT.md` with `pre_seeded: true` (populated from the source UAT report). Both paths use the same `pre_seeded` mechanism so `suggest-next.sh` handles them uniformly.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

**Todo lifecycle:** `scripts/resolve-todo-item.sh`, `scripts/todo-details.sh`, and
`scripts/todo-lifecycle.sh`.

**Re-verification:** `scripts/compile-verify-context-for-uat.sh`,
`scripts/extract-uat-resume.sh`, `scripts/normalize-plan-filenames.sh`, and
`scripts/prepare-reverification.sh`.

**UAT remediation:** `scripts/uat-remediation-state.sh` and
`scripts/validate-uat-remediation-artifact.sh`.

**Agent and recovery support:** `scripts/extract-skill-follow-up-files.sh` and `scripts/migrate-orphaned-state.sh`.
