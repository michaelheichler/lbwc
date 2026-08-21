---
category: lifecycle
description: Form a contract-bound Claude Code agent team for one scoped task, choosing native, tmux, or workflow spawn after confirmation.
argument-hint: "[work instruction] [--plan <path>] [--scope <path> ...]"
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, TaskCreate, TaskUpdate, Agent, Workflow
disable-model-invocation: true
---

# LBWC Team $ARGUMENTS

## Context

Plugin root, project root, and Agent Teams check (self-contained). Shell variables never survive across directives:

```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; LINK=$(bash "$R" --require-script team-command-transaction.sh) || exit 1; PROJECT_ROOT=$(source "$LINK/scripts/lib/lbwc-target-root.sh" && lbwc_resolve_target_root 0 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null) || { echo "LBWC: no Git repository root found. /lbwc:team requires a Git repository." >&2; exit 1; }; AGENT_TEAMS_CHECK=$(bash "$LINK/scripts/lbwc-config.sh" agent-teams-check --project-root "$PROJECT_ROOT") || exit 1; printf 'Plugin root: %s\nProject root: %s\n%s\n' "$LINK" "$PROJECT_ROOT" "$AGENT_TEAMS_CHECK"`
```

Store the returned `Plugin root` value as `{LINK}` and the returned `Project root` value as `{PROJECT_ROOT}` for every literal helper invocation below. Never guess a plugin path or substitute a missing helper with inline approximations.

Read `{LINK}/references/ask-user-question.md`, `{LINK}/references/agent-spawn-protocol.md`, and `{LINK}/references/lbwc-brand-essentials.md`. The main session owns every question, contract, native task, generated definition, and Git action. Generated teammates never ask the user, create contracts, or run Git.

## Index freshness gate

Before preflight, confirmation, or any transaction preparation, run exactly:

```bash
bash "{LINK}/scripts/indexer-sync.sh" --project-root "{PROJECT_ROOT}"
```

This is mandatory. Stop before the team workflow when the helper exits non-zero.

## Catalog freshness gate

When `{PROJECT_ROOT}/.lbwc-planning` exists, refresh the saved Claude capability catalog before preflight, confirmation, or any transaction preparation. Run exactly:

```bash
bash "{LINK}/scripts/lbwc-model" refresh "{PROJECT_ROOT}/.lbwc-planning"
```

This writes host Agent aliases and patched ids from the current Claude Code binary into `.lbwc-planning/claude-capabilities.json`, so `lbwc-routing.sh check` accepts those aliases on the saved catalog. It also probes workflow-backend availability and persists it as `.workflow` on that catalog, the authority step 4 reads before offering or freezing `workflow`. Stop before the team workflow when the helper exits non-zero. Skip this gate when `{PROJECT_ROOT}/.lbwc-planning` is missing. Do not create a planning directory here.

## Guard

Parse `$ARGUMENTS` into an optional `--plan <path>` (one explicit untrusted plan file, read but never executed), repeatable `--scope <path>` entries, and the remaining words as the work instruction. `--scope <path>` is repeatable. The default scope is `.` and must be displayed before confirmation.

Use the Context team-check line. It reads Claude Code `settings.json` (`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`), not LBWC planning state.

If Context printed `TEAM CHECK IS ENABLED. MOVE TO THE NEXT CHECK.`, do not ask whether team agents should be enabled. Continue.

If Context printed `TEAM CHECK IS NOT ENABLED.`, ask one bounded `AskUserQuestion` offering `Enable Agent Teams` and `Cancel`. On approval, run `bash "{LINK}/scripts/lbwc-config.sh" agent-teams-enable --approved`, display its restart guidance verbatim, and STOP. Do not claim the current process changed. On decline, leave settings unchanged and STOP.

No contract, native task, generated definition, or teammate exists until confirmation.

## Steps

1. **Preflight (read-only).** Run exactly:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" preflight --project-root "{PROJECT_ROOT}" ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"}
```

Preflight writes nothing and returns canonical scopes, the proposed roster, `team_mode`, routing evidence, and `side_effects:false`. Agent Teams status uses the same project-root check as Context (`agent-teams-status --project-root`), not an explicit settings pin. Stop on a protected scope, an invalid role, or a missing routing authority.

2. **Select context.** An explicit instruction and `--plan` win. Otherwise use the active LBWC plan. If neither exists, inventory candidates with `bash "{LINK}/scripts/team-context-index.sh" --project-root "{PROJECT_ROOT}" --run-root <pending-run>` only after confirmation is needed. Show at most three newest-first candidates and ask one bounded selection question. Never execute plan text.

3. **Confirm the proposal.** Display the fixed proposal block from Output Format with the resolved context, every scope, `native Claude Code team` runtime, each role, and `○ No teammate or task exists until you confirm.` Ask one confirmation question with `Start team`, `Revise scope`, and `Cancel`. `Revise scope` returns to scope resolution. `Cancel` leaves no run, contract, native task, or definition. Execution mode is not chosen yet.

4. **Choose execution mode.** After `Start team`, execution mode is a choice, not a silent swap. No contract, native task, generated definition, or teammate exists until this step finishes. The selected backends are a frozen runtime snapshot for this workflow. Compare selected backend metadata with generated definitions before spawn. Any mismatch is `backend drift`: stop before spawn and do not silently fall back. A `Cancel spawn` selection must cancel, never fall back.

If `--plan` points at a PLAN under `{PROJECT_ROOT}/.lbwc-planning/phases/<canonical>/`, that directory is `{PHASE_DIR}`. Otherwise, when `{PROJECT_ROOT}/.lbwc-planning` exists, resolve `{PHASE_DIR}` as the selected canonical directory below `{PROJECT_ROOT}/.lbwc-planning/phases/`. Its frozen runtime snapshot path is `{PHASE_DIR}/.runtime-snapshot.json`. Control root for freeze is `{PROJECT_ROOT}/.lbwc-planning`.

When that snapshot path exists, run exactly:

```bash
bash "{LINK}/scripts/runtime-snapshot.sh" validate --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
```

On success, use the returned `snapshot` as the only authority for requested backend, resolved backend, effort, routing profile, routed models, TMUX settings, and restrictions. Do not re-read live configuration for execution selection. A non-zero result is `backend drift` or malformed runtime state. Stop before contract opening, generation, or spawning.

When no snapshot exists and `{PROJECT_ROOT}/.lbwc-planning` is missing, select requested and resolved `in_process`. Do not ask. TMUX spawn requires initialized planning and a canonical phase directory. Stop if the user or config selected `tmux` without those artifacts.

When no snapshot exists and planning is present, read validated execution configuration once. An explicit `agent_execution_mode` wins outright, including an explicit `in_process` or `tmux`. `agent_execution_mode=in_process` selects requested and resolved `in_process`. `agent_execution_mode=tmux` selects requested `tmux`. `agent_execution_mode=workflow` selects requested `workflow`: read `.workflow.available` from `{PROJECT_ROOT}/.lbwc-planning/claude-capabilities.json` and `.workflow_execution.enabled` from `{PROJECT_ROOT}/.lbwc-planning/config.json`. When `.workflow.available` is `false`, stop before any contract or agent exists and report `.workflow.unavailable_reasons` verbatim. Otherwise, when `.workflow_execution.enabled` is not `true`, stop before any contract or agent exists with `workflow backend is disabled in configuration`. Otherwise resolve `workflow`. There is no automatic fallback from a requested `workflow` to another backend. For `agent_execution_mode=ask`, read both `.workflow.available` and `.workflow_execution.enabled` from the same catalog and config first, then ask one bounded execution-mode question before any contract or agent exists. Follow `{LINK}/references/ask-user-question.md`: exactly one question, `multiSelect` false, two to four visible options.

- header: `Team execution`
- question when `.workflow.available` and `.workflow_execution.enabled` are both `true`: `After confirming this team, where should teammates run? Workflow run orchestrates the roster from a committed background script. Native keeps the current Claude Code Agent team. TMUX starts each teammate as a fresh pane session.`
- options when `.workflow.available` and `.workflow_execution.enabled` are both `true`, `Workflow run` first:
  - `Workflow run`: Run the roster through a committed workflow script in the background.
  - `Native team`: Keep native Agent spawn, native tasks, and native teammate messaging.
  - `TMUX panes`: Start each teammate as a fresh pane session through provision and split-group.
  - `Cancel spawn`: Do not spawn teammates for this run.
- question when `.workflow.available` or `.workflow_execution.enabled` is not `true`: `After confirming this team, where should teammates run? Native keeps the current Claude Code Agent team. TMUX starts each teammate as a fresh pane session.`
- options when `.workflow.available` or `.workflow_execution.enabled` is not `true`, the same three options with `Workflow run` left out entirely:
  - `Native team`: Keep native Agent spawn, native tasks, and native teammate messaging.
  - `TMUX panes`: Start each teammate as a fresh pane session through provision and split-group.
  - `Cancel spawn`: Do not spawn teammates for this run.

If the user chooses `Workflow run`, select requested and resolved `workflow`. If the user chooses `Native team`, select requested and resolved `in_process`. Do not replace native teams. If the user chooses `TMUX panes`, select requested `tmux`. If the user chooses `Cancel spawn`, and `{PHASE_DIR}` exists, run exactly:

```bash
bash "{LINK}/scripts/runtime-snapshot.sh" cancel --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
```

Report cancellation and stop. This writes `{PHASE_DIR}/.runtime-cancelled.json` and creates no snapshot. If `{PHASE_DIR}` is missing, report cancellation and stop without a snapshot. It must cancel, never fall back.

This gate is a fast, friendly stop before any contract, native task, generated definition, or teammate exists. It is not the only layer: freezing a requested `workflow` still fails with `workflow backend is disabled in configuration` when `workflow_execution.enabled` in `{PROJECT_ROOT}/.lbwc-planning/config.json` is `false`, and `workflow-generator.sh` re-validates both flags again at generation time. The shipped default has `workflow_execution.enabled=false`, so an unconfigured project never offers `Workflow run` and does not reach that freeze-time failure.

For requested `tmux`, complete preflight before freezing. On success resolve `tmux`. On failure, resolve `in_process` only if `tmux_execution.comms_fallback=fall_back_to_in_process`. Otherwise stop without a snapshot. Then, when `{PHASE_DIR}` exists, run exactly:

```bash
bash "{LINK}/scripts/runtime-snapshot.sh" freeze --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}" --requested-backend "{REQUESTED_BACKEND}" --resolved-backend "{RESOLVED_BACKEND}"
```

A `created` or `matched` result moves runtime state to `ready` and does not alter a task contract. Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation that follows a schema 3 open. Schema 2 generation omits `--execution-backend`.

Copy snapshot backends into CLI flags only when `{PHASE_DIR}/.runtime-snapshot.json` exists. Control root is `{PROJECT_ROOT}/.lbwc-planning`, the freeze `--planning-dir`. Native `in_process` with no freeze must not `jq` a missing snapshot: leave `OPEN_BACKEND_ARGS` empty and keep the selected `in_process` backends. When the snapshot exists and `snapshot.requested_backend` equals `snapshot.resolved_backend`, pass those values plus `--control-root` and `--assert-snapshot` so the schema 3 team contract cannot disagree with the snapshot. When they differ, that is the already-frozen `comms_fallback` case: omit the schema 3 backend flags, then follow the native Agent path.

```bash
SNAPSHOT_PATH="{PHASE_DIR}/.runtime-snapshot.json"
CONTROL_ROOT="{PROJECT_ROOT}/.lbwc-planning"
OPEN_BACKEND_ARGS=()
if [ -f "$SNAPSHOT_PATH" ]; then
  REQUESTED_BACKEND=$(jq -r '.requested_backend' "$SNAPSHOT_PATH")
  RESOLVED_BACKEND=$(jq -r '.resolved_backend' "$SNAPSHOT_PATH")
  if [ "$REQUESTED_BACKEND" = "$RESOLVED_BACKEND" ]; then
    OPEN_BACKEND_ARGS=(--requested-backend "$REQUESTED_BACKEND" --resolved-backend "$RESOLVED_BACKEND" --control-root "$CONTROL_ROOT" --assert-snapshot "$SNAPSHOT_PATH")
  fi
fi
```

If `snapshot.resolved_backend` is `in_process`, keep the native team and Agent path in step 5. Do not replace native teams.

If `snapshot.resolved_backend` is `tmux`, follow `{LINK}/references/tmux-spawn-protocol.md` on this branch only. Do not call native Agent. Continue at step 6.

If `snapshot.resolved_backend` is `workflow`, follow `{LINK}/references/workflow-spawn-protocol.md` on this branch only. Do not call native Agent. Continue at step 7.

5. **Native path.** Run this path only when resolved backend is `in_process`. Choose one collision-safe run id, then run exactly:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" prepare --project-root "{PROJECT_ROOT}" --run-id "$RUN_ID" --instruction "$INSTRUCTION" ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"}
```

Prepare always creates a run root below `.temporary-agent-runfiles/runs/`, issues exactly one schema 3 native-team contract for the whole roster (`pair` or `trio`, never `solo` for a multi-role roster), generates every teammate definition, registers the manifest, and advances the contract to `dispatched`. It returns `run_root`, `control_root`, `contract_id`, `teammates`, and `ordered_actions` with `agent_spawn` before `task_create`. For an initialized project the control root is the active `.lbwc-planning`. Otherwise it is the run root. Do not create `.lbwc-planning` for an uninitialized repository.

Read spawn payloads from:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" spawn-payload --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

The payloads contain only `subagent_type` and `name`, one per teammate, and block unless every manifest entry is registered against the contract. Spawn every payload with `Agent` in one message, all in parallel, never sequential, never a subset. Never pass `team_name`, and never pass `model`, `effort`, `maxTurns`, `tools`, `prompt`, role, or permission overrides. The generated frontmatter is authoritative. The spawn guard rejects conflicting call-time values. The first teammate forms the session team natively. Do not edit Claude Code native team configuration, task storage, inboxes, or mailbox files. After each spawn succeeds, record it:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" record-spawn --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --contract-id "$CONTRACT_ID" --teammate "$NAME"
```

Only after every roster teammate is recorded (`spawn_complete` true), read the task payload:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" task-payload --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

It blocks until spawn evidence exists for the full roster, then returns `task.subject` equal to the contract id. Create the native task with `TaskCreate` using that exact subject so the `TaskCreated` hook binds it to the pending contract. Record the binding:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" record-task --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --contract-id "$CONTRACT_ID" --task-id "$TASK_ID"
```

Update the native task to running with `TaskUpdate`. Teammates coordinate through native `SendMessage`, `TaskGet`, `TaskList`, and `TaskUpdate`. Accept completion only through the `TaskCompleted` hook after the bound contract reaches `verified`. Then record the terminal status and print the summary:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" complete --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --event "team run completed"
bash "{LINK}/scripts/team-command-transaction.sh" summary --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

6. **Tmux path.** Run this path only when `snapshot.resolved_backend` is `tmux`. Do not call native Agent. Do not create a native shared task. Do not run `prepare`. Choose one collision-safe run id, then issue one schema 3 team contract for the whole roster (`pair` or `trio`, never `solo` for a multi-role roster). Copy snapshot backends into `issue` flags as `OPEN_BACKEND_ARGS` above. Repeat each resolved scope as `--role-write-capability "$ENGINEER_ROLE:directory:$SCOPE"`.

```bash
CONTRACT_PATH=$(bash "{LINK}/scripts/task-contract.sh" issue "{PROJECT_ROOT}" "$RUN_ID" --command team --role "$ENGINEER_ROLE" --team "$TEAM_MODE" --job "$INSTRUCTION" --runtime-kind native-team --communication-policy native-team "${OPEN_BACKEND_ARGS[@]}" ${CAPABILITY_ARGS[@]+"${CAPABILITY_ARGS[@]}"})
TASK_ID=$(basename "$CONTRACT_PATH" .json)
```

Pass the contract path, task id, job, team mode, identical capability arguments, and `--execution-backend "$RESOLVED_BACKEND"` to one generator invocation (`--native-team` with `--pair` or `--trio` matching `$TEAM_MODE`). The main session owns `issue`. Workers never create or modify contracts. If generation fails, leave that contract `planned` and report the error. After successful registration, run `state ... dispatched`.

Follow `{LINK}/references/tmux-spawn-protocol.md` on this branch only. Bind-file identity is the protocol identity (one-shot `credentials/<agent_id>.json`, identity-only pane `-e`). After generation and `state ... dispatched`, run the spawn driver. `MAIN_ID` is the live orchestrator session `${CLAUDE_SESSION_ID:-}`. Fail closed when it is empty. The helper builds `--agents` JSON, runs preflight, provision, and `split-group`, publishes `{brief:...}` jobs, awaits result/error, and acks with the `message_id` from await output. On provision or split failure it rolls back.

```bash
MAIN_ID="${CLAUDE_SESSION_ID:-}"
[ -n "$MAIN_ID" ] || { echo "LBWC: CLAUDE_SESSION_ID is required for tmux spawn" >&2; exit 1; }
TIMEOUT_MS=$(jq -r '.tmux_execution.comms_latency_tolerance_ms' "$SNAPSHOT_PATH")
CONTRACT_DIGEST=$(jq -r '.contract_digest' "$CONTRACT_PATH")
bash "{LINK}/scripts/tmux-spawn-group.sh" dispatch --project-root "{PROJECT_ROOT}" --control-root "$CONTROL_ROOT" --main-id "$MAIN_ID" --contract-id "$TASK_ID" --contract-digest "$CONTRACT_DIGEST" --spawn-ready-text "$GENERATOR_OUTPUT" --job "$INSTRUCTION" --timeout-ms "$TIMEOUT_MS"
```

Observe the helper JSON summary as the roster reports. After the grouping is terminal, apply protocol cleanup (`kill-agent` or `kill-session`) from the frozen cleanup policy. Stop on contract, generator, preflight, provision, split-group, or bus failure. Do not silently switch to in-process except the already-frozen `comms_fallback` case above.

7. **Workflow path.** Run this path only when `snapshot.resolved_backend` is `workflow`. Do not call native Agent. Do not create a native shared task. Do not run `prepare`. Choose one collision-safe run id, then issue one schema 3 team contract for the whole roster (`pair` or `trio`, never `solo` for a multi-role roster). Copy snapshot backends into `issue` flags as `OPEN_BACKEND_ARGS` above. Repeat each resolved scope as `--role-write-capability "$ENGINEER_ROLE:directory:$SCOPE"`.

```bash
CONTRACT_PATH=$(bash "{LINK}/scripts/task-contract.sh" issue "{PROJECT_ROOT}" "$RUN_ID" --command team --role "$ENGINEER_ROLE" --team "$TEAM_MODE" --job "$INSTRUCTION" --runtime-kind native-team --communication-policy native-team "${OPEN_BACKEND_ARGS[@]}" ${CAPABILITY_ARGS[@]+"${CAPABILITY_ARGS[@]}"})
TASK_ID=$(basename "$CONTRACT_PATH" .json)
```

Pass the contract path, task id, job, team mode, identical capability arguments, and `--execution-backend "$RESOLVED_BACKEND"` to one generator invocation (`--native-team` with `--pair` or `--trio` matching `$TEAM_MODE`). This mints every roster definition by the same mechanic `{LINK}/references/agent-spawn-protocol.md` already documents. If generation fails, leave that contract `planned` and report the error.

Follow `{LINK}/references/workflow-spawn-protocol.md` on this branch only. `workflow-generator.sh` requires the same contract while it is still `planned`, so run it before the state transition below. Its call is `workflow-generator.sh <solo|pair|trio> "$ENGINEER_ROLE" --job "$INSTRUCTION" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --control-root "$CONTROL_ROOT"`. Pass every name the prior invocation produced as `--name` (solo) or `--engineer-name`/`--critic-name`/`--testdev-name` (pair or trio), plus `--autonomy` read from `{PROJECT_ROOT}/.lbwc-planning/config.json` for a pair or trio. Read the `Workflow-call parameters:` block and the `WORKFLOW_READY <task-id>` line that follows it. On any `workflow-generator:` stderr failure, stop and report the error verbatim, and leave the contract `planned`. After successful registration, run `state ... dispatched`.

Call `Workflow` exactly once with `scriptPath` set to the path value from the `Workflow-call parameters:` block, confirmed by the `WORKFLOW_READY <task-id>` line that follows it. Never pass `script`, and never inline or paraphrase the rendered file into the call. The `PreToolUse` guard on `Workflow` independently revalidates the path against the registered digest. A denial is a stop, not a fallback trigger.

`Workflow` runs the roster in the background. Its own tool result reports only the launch (`taskId`, `runId`, `transcriptDir`, `scriptPath`), never the outcome. Observe the run through its own terminal result, not through native task or bus polling. When that result carries `user_decision_required`, ask exactly one bounded `AskUserQuestion` about continuing remediation, following `{LINK}/references/ask-user-question.md`. Any other terminal result is the roster's report. Record it and stop.

## Failure and recovery

On contract, task binding, generation, spawn, routing evidence, tmux preflight, provision, split-group, bus publish/await/ack, or completion mismatch, run `bash "{LINK}/scripts/team-command-transaction.sh" fail --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --event "<exact failure>"` when a run root exists. Retain runfiles, append the actionable diagnostic, and report the exact failed artifact. Never widen scope, silently substitute a model, pre-author native team state, or delete an unreadable run.

## Output Format

Use horizontal rules, not side-bordered boxes. The proposal block before confirmation is fixed:

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TEAM PROPOSAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Context   <selected plan or instruction source>
  Scope     <every resolved scope, comma-separated>
  Runtime   native Claude Code team

  <engineer-role>   implements the scoped task
    |-- <critic-role>   reviews completed work
    `-- test-dev       owns test paths (trio only)

  ○ No teammate or task exists until you confirm.
```

Report missing runtime routing evidence as unknown. After completion, print the run summary fields from `team-command-transaction.sh summary` unchanged: `run_id`, `status`, `project_root`, `scope`, and `records`. A recorded mismatch blocks acceptance.

## Next Up

The native shared task list is the next action after a confirmed successful native spawn. After a tmux spawn, observe pane sessions and bus results. After a workflow spawn, observe the run's own terminal result rather than a native task or pane. A restart is the only next action after enabling Agent Teams.
