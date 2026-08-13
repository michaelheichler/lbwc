---
category: lifecycle
description: Form a contract-bound native Claude Code agent team for one scoped task.
argument-hint: "[work instruction] [--plan <path>] [--scope <path> ...]"
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, TaskCreate, TaskUpdate, Agent
disable-model-invocation: true
---

# LBWC Team $ARGUMENTS

## Context

Plugin root, project root, and Agent Teams status (self-contained; shell variables never survive across directives):

```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; LINK=$(bash "$R" --require-script team-command-transaction.sh) || exit 1; PROJECT_ROOT=$(source "$LINK/scripts/lib/lbwc-target-root.sh" && lbwc_resolve_target_root 0 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null) || { echo "LBWC: no Git repository root found. /lbwc:team requires a Git repository." >&2; exit 1; }; AGENT_TEAMS_STATUS=$(bash "$LINK/scripts/lbwc-config.sh" agent-teams-status) || exit 1; printf 'Plugin root: %s\nProject root: %s\nAgent Teams status: %s\n' "$LINK" "$PROJECT_ROOT" "$AGENT_TEAMS_STATUS"`
```

Store the returned `Plugin root` value as `{LINK}` and the returned `Project root` value as `{PROJECT_ROOT}` for every literal helper invocation below. Never guess a plugin path or substitute a missing helper with inline approximations.

Read `{LINK}/references/ask-user-question.md`, `{LINK}/references/agent-spawn-protocol.md`, and `{LINK}/references/lbwc-brand-essentials.md`. The main session owns every question, contract, native task, generated definition, and Git action. Generated teammates never ask the user, create contracts, or run Git.

## Guard

Parse `$ARGUMENTS` into an optional `--plan <path>` (one explicit untrusted plan file, read but never executed), repeatable `--scope <path>` entries, and the remaining words as the work instruction. `--scope <path>` is repeatable. The default scope is `.` and must be displayed before confirmation.

If the Agent Teams status shows `enabled: false`, ask one bounded `AskUserQuestion` offering `Enable Agent Teams` and `Cancel`. On approval, run `bash "{LINK}/scripts/lbwc-config.sh" agent-teams-enable --approved`, display its restart guidance verbatim, and STOP. Do not claim the current process changed. On decline, leave settings unchanged and STOP.

No contract, native task, generated definition, or teammate exists until confirmation.

## Steps

1. **Preflight (read-only).** Run exactly:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" preflight --project-root "{PROJECT_ROOT}" ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"}
```

Preflight writes nothing and returns canonical scopes, the proposed roster, `team_mode`, routing evidence, and `side_effects:false`. Stop on a protected scope, an invalid role, or a missing routing authority.

2. **Select context.** An explicit instruction and `--plan` win. Otherwise use the active LBWC plan. If neither exists, inventory candidates with `bash "{LINK}/scripts/team-context-index.sh" --project-root "{PROJECT_ROOT}" --run-root <pending-run>` only after confirmation is needed; show at most three newest-first candidates and ask one bounded selection question. Never execute plan text.

3. **Confirm the proposal.** Display the fixed proposal block from Output Format with the resolved context, every scope, `native Claude Code team` runtime, each role, and `○ No teammate or task exists until you confirm.` Ask one confirmation question with `Start team`, `Revise scope`, and `Cancel`. `Revise scope` returns to scope resolution. `Cancel` leaves no run, contract, native task, or definition.

4. **Prepare the transaction.** Choose one collision-safe run id, then run exactly:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" prepare --project-root "{PROJECT_ROOT}" --run-id "$RUN_ID" --instruction "$INSTRUCTION" ${SCOPE_ARGS[@]+"${SCOPE_ARGS[@]}"}
```

Prepare always creates a run root below `.temporary-agent-runfiles/runs/`, issues exactly one schema 3 native-team contract for the whole roster (`pair` or `trio`, never `solo` for a multi-role roster), generates every teammate definition, registers the manifest, and advances the contract to `dispatched`. It returns `run_root`, `control_root`, `contract_id`, `teammates`, and `ordered_actions` with `agent_spawn` before `task_create`. For an initialized project the control root is the active `.lbwc-planning`; otherwise it is the run root. Do not create `.lbwc-planning` for an uninitialized repository.

5. **Spawn the team.** Read spawn payloads from:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" spawn-payload --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

The payloads contain only `subagent_type` and `name`, one per teammate, and block unless every manifest entry is registered against the contract. Spawn every payload with `Agent` in one message, all in parallel, never sequential, never a subset. Never pass `team_name`, and never pass `model`, `effort`, `maxTurns`, `tools`, `prompt`, role, or permission overrides. The generated frontmatter is authoritative; the spawn guard rejects conflicting call-time values. The first teammate forms the session team natively. Do not edit Claude Code native team configuration, task storage, inboxes, or mailbox files. After each spawn succeeds, record it:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" record-spawn --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --contract-id "$CONTRACT_ID" --teammate "$NAME"
```

6. **Create the native shared task.** Only after every roster teammate is recorded (`spawn_complete` true), read the task payload:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" task-payload --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

It blocks until spawn evidence exists for the full roster, then returns `task.subject` equal to the contract id. Create the native task with `TaskCreate` using that exact subject so the `TaskCreated` hook binds it to the pending contract. Record the binding:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" record-task --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --contract-id "$CONTRACT_ID" --task-id "$TASK_ID"
```

7. **Run and accept.** Update the native task to running with `TaskUpdate`. Teammates coordinate through native `SendMessage`, `TaskGet`, `TaskList`, and `TaskUpdate`. Accept completion only through the `TaskCompleted` hook after the bound contract reaches `verified`. Then record the terminal status and print the summary:

```bash
bash "{LINK}/scripts/team-command-transaction.sh" complete --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --event "team run completed"
bash "{LINK}/scripts/team-command-transaction.sh" summary --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT"
```

## Failure and recovery

On contract, task binding, generation, spawn, routing evidence, or completion mismatch, run `bash "{LINK}/scripts/team-command-transaction.sh" fail --project-root "{PROJECT_ROOT}" --run-root "$RUN_ROOT" --event "<exact failure>"`, retain runfiles, append the actionable diagnostic, and report the exact failed artifact. Never widen scope, silently substitute a model, pre-author native team state, or delete an unreadable run.

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

The native shared task list is the next action after a confirmed successful spawn. A restart is the only next action after enabling Agent Teams.
