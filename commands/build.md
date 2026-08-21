---
category: lifecycle
disable-model-invocation: true
description: Execute a phase PLAN through contract-bound pair or trio agents, one main-session commit per task, and a verified summary.
argument-hint: "<phase number or name>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, SendMessage, LSP, AskUserQuestion, Workflow
---

After resolving Context, first read `{LINK}/skills-bundle/ponytail/SKILL.md` and apply the ponytail discipline at level full for the whole task.

# LBWC Build: $ARGUMENTS

## Context

Plugin root and project root (self-contained, shell variables do not survive across directives):

```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; LINK=$(bash "$R" --require-script indexer-sync.sh) || exit 1; PROJECT_ROOT=$(source "$LINK/scripts/lib/lbwc-target-root.sh" && lbwc_resolve_target_root 0 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null) || { echo "LBWC: no Git repository root found. /lbwc:build requires a Git repository." >&2; exit 1; }; printf 'Plugin root: %s\nProject root: %s\n' "$LINK" "$PROJECT_ROOT"`
```

Store the returned `Plugin root` value as `{LINK}` and the returned `Project root` value as `{PROJECT_ROOT}` for every later literal helper invocation. Never guess a plugin path or substitute a missing helper with an inline approximation.

## Index freshness gate

Before reading the selected PLAN or spawning any agent, run exactly:

```bash
bash "{LINK}/scripts/indexer-sync.sh" --project-root "{PROJECT_ROOT}"
```

This is mandatory. Stop before plan execution when the helper exits non-zero.

After the gate succeeds, run `bash "{LINK}/scripts/phase-detect.sh"`. Read the selected root or remediation PLAN, its declared task files and dependencies, relevant terminal summaries, task-contract state, and generated-agent manifest. Follow `{LINK}/references/execute-protocol.md` and `{LINK}/references/agent-spawn-protocol.md`.

## Workflow capability gate

Refresh the saved Claude capability catalog before any grouping contract or spawn:

```bash
bash "{LINK}/scripts/lbwc-model" refresh "{PROJECT_ROOT}/.lbwc-planning"
```

This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`, the authority the execution-mode choice in Spawn and verify reads before offering or resolving `workflow`. Stop before plan execution when the helper exits non-zero. Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.

## Guard

Require initialized active planning state, `phase_detect_complete=true`, a canonical PLAN, and no detector-selected blocking route that precedes build. The main session owns contracts, planning writes, verification, telemetry, Git, summaries, and user output. Stop on a missing helper, malformed PLAN, stale contract, open exclusive grouping, or undeclared path.

## Resolve the target phase

- Use $ARGUMENTS when supplied.
- Otherwise use the first non-`complete` phase in ROADMAP.md's Progress table.
- Read `.lbwc-planning/phases/{NN}-{slug}/PLAN.md`.
- If it does not exist, stop and tell the user to run `/plan <phase>` first.
- **Remediation round execution:** if the phase has an active remediation round (`remediation/qa/.qa-remediation-stage` or `remediation/uat/.uat-remediation-stage` with `stage=plan`, checkable via `bash "{LINK}/scripts/remediation-round.sh" current <phase-dir> <qa|uat>`), the work list is that round's `R{NN}-PLAN.md` instead of the phase PLAN.md. Run `bash "{LINK}/scripts/remediation-round.sh" stage <phase-dir> <kind> execute` before spawning, work the round plan's tasks exactly like a normal plan (steps 2-7 below), write `R{NN}-SUMMARY.md` from `{LINK}/templates/REMEDIATION-SUMMARY.md` instead of SUMMARY.md, then tell the user to run `/qa <phase>` to re-verify the round. The deviq build gate still runs first.
- Before spawning any dev/engineer pair or trio for this phase, run `bash "{LINK}/scripts/deviq-build-gate.sh" <phase>`. This is the one blocking rule and this is its only call site.
- If the gate exits non-zero, build one exact advisory brief from its open blocks. Issue a read-only solo `/build` command contract named `deviq-{phase}`. Generate one solo `deviq` agent with that contract and `--exclusive`. Advance the contract to `dispatched` before spawning. Wait for its manifest entry to become `used` or `expired`, then surface its recommendation instead of spawning anything else.

## Plan waves

Group the plan's `<task>` entries into waves by `depends_on`. Wave 1 has no unmet dependency. Later waves depend only on earlier waves. Preserve PLAN order for tasks within each wave.

Within a dependency wave, process tasks in PLAN order and admit exactly one task team at a time. Each task team contains one or more sequential groupings. A grouping is a solo red stage, a pair, or a trio. Independence within a wave means the tasks have no dependency edge between them. It does not permit parallel admission. Generate every build grouping with `--exclusive`, then wait until every member is `used` or `expired` before generating the next grouping. Do not pre-generate a later grouping.

This admission rule is identical under every resolved backend, including `workflow`, but a workflow grouping's closure signal is not. `--exclusive` reads the one shared agent manifest, not a backend-specific one. A workflow-spawned member's `agent()` step fires the same `SubagentStart`/`SubagentStop` hooks a native member's `Agent` call fires, carrying the registered `lbwc-` name in `agent_type`, and `agent-lifecycle.sh` advances that name to `running` then `used` from those hooks exactly as it does for a native or TMUX member. This is confirmed on the host, not assumed: see `references/workflow-probe-findings.md`, Unknown D. For a solo grouping that is the whole picture, one `agent()` call and one `used` transition, and the manifest closure check is sufficient on its own exactly as it is for native and TMUX.

A pair or trio grouping is not that simple. `templates/workflows/pair.js.tpl` and `templates/workflows/trio.js.tpl` retry the same registered names for up to three remediation rounds, unbounded under `pure-vibe`, and every round ends with its own `SubagentStop` followed by the next round's `SubagentStart`. Between rounds, a still-running grouping's members read `used` in the manifest exactly like a closed one does, so `used` is necessary but not sufficient for workflow closure. It can also mean the grouping is between rounds. The run's own terminal `result`, read once the `Workflow` call completes, is what actually signals the grouping is done, including every internal round. The main session observes that terminal result before it reads the manifest's `used`-or-`expired` state as confirmation, and only then generates the next grouping, exactly as detailed in the workflow branch of Spawn and verify below. The manifest is not the sole admission authority for `workflow` the way it is for `in_process` and `tmux`. For `workflow` it is corroborating state read after the terminal result, never a substitute for it. No wave or cross-grouping ordering is ever delegated into a workflow script itself.

Entry has the same asymmetry, mirrored. `references/agent-spawn-protocol.md` requires every admitted member spawned in one message. A native or tmux pair or trio reaches `running` together because of that. `templates/workflows/pair.js.tpl` instead awaits the engineer's `agent()` call before starting the critic's. `templates/workflows/trio.js.tpl` awaits engineer, then `test-dev`, then critic, in that order. A workflow pair or trio therefore never has more than one member `running` at once. It enters `running` one member at a time, in template order. `state ... running` in Main-session task contract and telemetry below is driven by the first admitted member reaching `running`. The later members have not started yet, so it is never driven by every admitted member reaching that state.

**Open item.** `agent-generator.sh --exclusive` alone cannot detect an in-flight workflow grouping between remediation rounds. It blocks only on a `registered` or `running` manifest entry, and a mid-loop `used` state passes that check. This command protects admission only by never generating the next grouping until it has itself observed the workflow's terminal result, not by anything `--exclusive` enforces on its own. A generator-side fix, such as a workflow-run marker distinct from the per-agent manifest that `--exclusive` also checks, is not implemented here.

## Select roles

For each task, choose exactly one role to own it:

- Python source files in scope: `python-engineer`.
- Web, frontend, or HTTP API files in scope: `web-engineer`.
- Everything else, or any task whose `verify` step is a correctness argument (an invariant, a termination condition, a proof obligation): `coding-dijkstra`.
- If a task's files span more than one of these, pick by the file the `action` step spends the most words on, do not split one task across two roles.
- If a task's `files` or `action` are too vague to route with any of the above, stop and report which task, rather than guessing a role for it.

## Select the team shape

For a task with `<strategy>tdd</strategy>`, use a solo `qa-author` red stage followed by `--pair` for the engineer and critic. `qa-author` is the only test owner. For every other task, use `--trio` when its `verify` step calls for new automated test coverage. Otherwise use `--pair`. Do not default to trio, `test-dev` is only for non-TDD tasks needing new tests.

## Implementation discipline

Apply the ponytail discipline read in the required first step to every implementation grouping. Keep the scope honest. Question work that is not needed. Look for an existing helper or pattern. Prefer the standard library or native capability before adding a dependency. Choose the smallest implementation that still satisfies the PLAN and verification gates. This discipline reduces needless code. It never permits skipping validation, error handling, security, or explicitly requested work.

## Main-session task contract and telemetry

After selecting the role and grouping, the main session opens one PLAN contract for that grouping. A TDD task has two contracts, `red` and `implementation`. Every other task has one `implementation` contract. The exact generator brief must be passed as `--job` to `open` and to the generator. Do not run `open` until Spawn and verify has a validated or frozen snapshot.

Copy snapshot backends into CLI flags only when `{PHASE_DIR}/.runtime-snapshot.json` exists. Control root is `{PROJECT_ROOT}/.lbwc-planning`, the freeze `--planning-dir`. Native `in_process` with no freeze must not `jq` a missing snapshot: leave `OPEN_BACKEND_ARGS` empty and keep the selected `in_process` backends. When the snapshot exists and `snapshot.requested_backend` equals `snapshot.resolved_backend`, pass those values plus `--control-root` and `--assert-snapshot` so `open` cannot disagree with the snapshot. When they differ, that is the already-frozen `comms_fallback` case: omit the schema 3 backend flags (`open` requires matching backends), then follow the native Agent path.

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
CONTRACT_PATH=$(bash "{LINK}/scripts/task-contract.sh" open "$PLAN_PATH" "{PROJECT_ROOT}" "$TASK_NAME" --role "$ROLE" --team "$TEAM_MODE" --group "$GROUP_NAME" --job "$BRIEF" "${OPEN_BACKEND_ARGS[@]}" "${CONTRACT_ALLOWANCE_ARGS[@]}")
TASK_ID=$(basename "$CONTRACT_PATH" .json)
```

Build `CONTRACT_ALLOWANCE_ARGS` only from the selected PLAN task's `<files>`. Repeat each engineer path as `--write-allowance <path>`. For a non-TDD trio, repeat each exact test path as `--role-write-allowance test-dev:<path>`. Use `qa-author`, `solo`, and only the exact test paths for the `red` contract. Use the selected engineer role, `pair`, and only implementation paths for the later TDD `implementation` contract. The contract writer rejects any allowance not declared in PLAN.

`CONTRACT_ALLOWANCE_ARGS` is identical for every resolved backend, including `workflow`. `task-contract.sh open` always derives a schema 3 contract's typed write capabilities from these same `--write-allowance`/`--role-write-allowance` flags, so there is no separate typed-capability form to build for a workflow grouping.

Pass the contract path, task id, job, team mode, and identical allowance arguments to one generator invocation. Pass `--execution-backend "$RESOLVED_BACKEND"` only when `OPEN_BACKEND_ARGS` is non-empty so the generator matches a schema 3 contract. Schema 2 native generation without a freeze, and the frozen `comms_fallback` case, must omit that override. The main session owns `open`. Workers never create or modify contracts. If generation fails, leave that grouping contract `planned` and report the error.

Advance each grouping contract only from outcomes the main session observes. After successful registration, run `state ... dispatched`. After the manifest shows the first admitted member `running`, run `state ... running`. For `in_process` and `tmux` every admitted member reaches `running` together, so the first is also the last. For `workflow`, only the first admitted member has started (see the entry-asymmetry paragraph in Plan waves above). After all reports arrive, run `state ... awaiting_review`. After verification, run `state ... verified`, `blocked`, or `cancelled`. Never advance one grouping from another grouping's outcome or from an unobserved worker claim. Record one bounded telemetry event only after the main session observes the command outcome:

```bash
python3 "{LINK}/scripts/lib/session-telemetry.py" record --event command --outcome success --phase "$PHASE"
```

Use the matching `failure`, `partial`, or `blocked` outcome when applicable. Workers and their reports do not write telemetry. A telemetry write failure is reported as a command-verification problem. It must not be silently treated as a successful outcome.

## Spawn and verify

Before opening a grouping contract, resolve `{PHASE_DIR}` as the selected canonical directory below `{PROJECT_ROOT}/.lbwc-planning/phases/`. Its frozen runtime snapshot path is `{PHASE_DIR}/.runtime-snapshot.json`.

1. When that path exists, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" validate --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   On success, use the returned `snapshot` as the only authority for requested backend, resolved backend, effort, routing profile, routed models, TMUX settings, and restrictions. Do not re-read live configuration for execution selection. A non-zero result is `backend drift` or malformed runtime state. Stop before contract opening, generation, spawning, or telemetry and preserve every contract state.
2. When no snapshot exists, read validated execution configuration once. An explicit `agent_execution_mode` wins outright, including an explicit `in_process` or `tmux`. `agent_execution_mode=in_process` selects requested and resolved `in_process`. `agent_execution_mode=tmux` selects requested `tmux`. `agent_execution_mode=workflow` selects requested `workflow`: read `.workflow.available` from `{PROJECT_ROOT}/.lbwc-planning/claude-capabilities.json` and `.workflow_execution.enabled` from `{PROJECT_ROOT}/.lbwc-planning/config.json`. When `.workflow.available` is `false`, stop before any contract or agent exists and report `.workflow.unavailable_reasons` verbatim. Otherwise, when `.workflow_execution.enabled` is not `true`, stop before any contract or agent exists with `workflow backend is disabled in configuration`. Otherwise resolve `workflow`. There is no automatic fallback from a requested `workflow` to another backend. For `agent_execution_mode=ask`, read both `.workflow.available` and `.workflow_execution.enabled` from the same catalog and config first, then ask one bounded execution-mode question before any contract or agent exists. Follow `{LINK}/references/ask-user-question.md`: exactly one question, `multiSelect` false, two to four visible options.

   - header: `Build execution`
   - question when `.workflow.available` and `.workflow_execution.enabled` are both `true`: `Where should this phase's task groupings run? Workflow run orchestrates each grouping through a committed background script. Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.`
   - options when `.workflow.available` and `.workflow_execution.enabled` are both `true`, `Workflow run` first:
     - `Workflow run`: Run each grouping through a committed workflow script in the background.
     - `Native spawn`: Keep the current native Agent spawn.
     - `TMUX panes`: Start each grouping as a fresh pane session through provision and split-group.
     - `Cancel spawn`: Do not spawn any grouping for this build.
   - question when `.workflow.available` or `.workflow_execution.enabled` is not `true`: `Where should this phase's task groupings run? Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.`
   - options when `.workflow.available` or `.workflow_execution.enabled` is not `true`, the same three options with `Workflow run` left out entirely:
     - `Native spawn`: Keep the current native Agent spawn.
     - `TMUX panes`: Start each grouping as a fresh pane session through provision and split-group.
     - `Cancel spawn`: Do not spawn any grouping for this build.

   If the user chooses `Workflow run`, select requested and resolved `workflow`. If the user chooses `Native spawn`, select requested and resolved `in_process`. If the user chooses `TMUX panes`, select requested `tmux`. If the user chooses `Cancel spawn`, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" cancel --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   Report cancellation and stop. This writes `{PHASE_DIR}/.runtime-cancelled.json` and creates no snapshot. A planned grouping contract stays unchanged. It must cancel, never fall back.
3. For requested `tmux`, complete preflight before freezing. On success resolve `tmux`. On failure, resolve `in_process` only if `tmux_execution.comms_fallback=fall_back_to_in_process`. Otherwise stop without a snapshot. Then run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" freeze --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}" --requested-backend "{REQUESTED_BACKEND}" --resolved-backend "{RESOLVED_BACKEND}"
   ```

   A `created` or `matched` result moves runtime state to `ready` and does not alter a task contract. Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation that follows a schema 3 open. Schema 2 generation omits `--execution-backend`. The helper atomically records schema version, canonical phase, requested and resolved backend, effort, active routing profile and models, complete TMUX settings and restrictions, and the canonical source-config digest.
4. When the summary has been written and validated after every task reaches its terminal state, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" cleanup --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   This moves runtime state from `ready` to `cleaned`. A failed or blocked build preserves the snapshot for resume. A cleanup failure blocks the terminal transition and must be reported.

Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation that follows a schema 3 open. Stop on contract, generator, preflight, provision, split-group, or bus failure. Do not silently switch to in-process except the already-frozen `comms_fallback` case above. Schema 2 generation omits `--execution-backend`.

For one wave, take the next task in PLAN order and generate only its current grouping with `--exclusive`, following `@references/agent-spawn-protocol.md` for generator admission. For a pair or trio, admit every member of that one grouping together. Derive each member's manifest capability from the task's `files` field. Pass source paths through `--write-allowance` for the engineer and test paths through `--role-write-allowance test-dev:<exact-path>` for a non-TDD trio. Give the engineer the task's `name`, `action`, `verify`, and `done` fields verbatim as its brief. Do not ask an agent to declare or summarize file scope. Run the contract open and generator arguments in the preceding section after role selection and before this invocation.

If `snapshot.resolved_backend` is `in_process`, keep the native Agent path: spawn every generated name together in the same turn with `Agent(...)` as `@references/agent-spawn-protocol.md` requires.

If `snapshot.resolved_backend` is `tmux`, follow `{LINK}/references/tmux-spawn-protocol.md` on this branch only. Do not call native Agent. After generation and `state ... dispatched`, run the spawn driver. `MAIN_ID` is the live orchestrator session `${CLAUDE_SESSION_ID:-}`. Fail closed when it is empty. The helper builds `--agents` JSON, runs preflight, provision, and `split-group`, publishes `{brief:...}` jobs, awaits result/error, and acks with the `message_id` from await output. On provision or split failure it rolls back.

   ```bash
   MAIN_ID="${CLAUDE_SESSION_ID:-}"
   [ -n "$MAIN_ID" ] || { echo "LBWC: CLAUDE_SESSION_ID is required for tmux spawn" >&2; exit 1; }
   TIMEOUT_MS=$(jq -r '.tmux_execution.comms_latency_tolerance_ms' "$SNAPSHOT_PATH")
   CONTRACT_DIGEST=$(jq -r '.contract_digest' "$CONTRACT_PATH")
   bash "{LINK}/scripts/tmux-spawn-group.sh" dispatch --project-root "{PROJECT_ROOT}" --control-root "$CONTROL_ROOT" --main-id "$MAIN_ID" --contract-id "$TASK_ID" --contract-digest "$CONTRACT_DIGEST" --spawn-ready-text "$GENERATOR_OUTPUT" --job "$BRIEF" --timeout-ms "$TIMEOUT_MS"
   ```

   Observe the helper JSON summary as the grouping reports. Then continue contract state, verification, and commits below. After the grouping is terminal, apply protocol cleanup (`kill-agent` or `kill-session`) from the frozen cleanup policy.

If `snapshot.resolved_backend` is `workflow`, follow `{LINK}/references/workflow-spawn-protocol.md` on this branch only. Do not call native Agent and do not run the tmux spawn driver. `workflow-generator.sh` requires the same grouping contract while it is still `planned`, so run it before the state transition below. Its call is `workflow-generator.sh <solo|pair|trio> "$ROLE" --job "$BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --control-root "$CONTROL_ROOT"`, with the shape matching `$TEAM_MODE` for this grouping. Pass every name the prior generator invocation produced as `--name` (solo) or `--engineer-name`/`--critic-name`/`--testdev-name` (pair or trio), plus `--autonomy` read from `{PROJECT_ROOT}/.lbwc-planning/config.json` for a pair or trio. Read the `Workflow-call parameters:` block and the `WORKFLOW_READY <task-id>` line that follows it. On any `workflow-generator:` stderr failure, stop and report the error verbatim, and leave the contract `planned`. After successful registration, run `state ... dispatched`.

   Call `Workflow` exactly once with `scriptPath` set to the path value from the `Workflow-call parameters:` block, confirmed by the `WORKFLOW_READY <task-id>` line that follows it. Never pass `script`, and never inline or paraphrase the rendered file into the call. The `PreToolUse` guard on `Workflow` independently revalidates the path against the registered digest. A denial is a stop, not a fallback trigger.

   `Workflow` runs the grouping in the background. Its own tool result reports only the launch (`taskId`, `runId`, `transcriptDir`, `scriptPath`), never the outcome. The manifest is still what `state ... running` reads, but entry is not the same shape here. The same `SubagentStart` hook that drives a native or TMUX member fires here too, but only for the one member the template has started so far. `templates/workflows/pair.js.tpl` awaits the engineer's `agent()` call before starting the critic's. `templates/workflows/trio.js.tpl` awaits engineer, then `test-dev`, then critic. A workflow pair or trio is therefore never more than one member `running` at once. Run `state ... running` from that first `SubagentStart`, not from waiting on every admitted member to reach it, because the later members have not started yet. Closure is not read from the manifest alone. Observe the run's own terminal `result` first, not through native task or bus polling, and only after that result arrives read the manifest's `used`-or-`expired` state as confirmation before generating the next grouping. For a pair or trio this ordering is required, not a formality. `templates/workflows/pair.js.tpl` and `templates/workflows/trio.js.tpl` retry the same registered names once per remediation round, so a member reads `used` between rounds while the grouping is still active. Reading the manifest alone at that moment would admit the next grouping too early. The terminal result is what actually marks the grouping done. The manifest corroborates it once observed, it does not substitute for it. When that result carries `user_decision_required`, ask exactly one bounded `AskUserQuestion` about continuing remediation, following `{LINK}/references/ask-user-question.md`. Any other terminal result is the grouping's report: continue contract state, verification, deviq evidence, and the commit exactly as the native path above. There is no pane or bus to clean up.

- **TDD red stage:** open the `red` contract before generating solo `qa-author` with `--exclusive`. Pass the same must_haves brief and exact test-path allowances to both calls. Dispatch the contract before spawning. After the tests report and red commit, close its state from observed evidence. Wait until the manifest entry is `used` or `expired`. Then open a separate `implementation` pair contract for the engineer and critic. `test-dev` is not part of a TDD task. On `workflow`, generate and dispatch the red stage exactly like any other grouping above: `agent-generator.sh --execution-backend workflow --exclusive`, then `workflow-generator.sh solo qa-author ...`, then one `Workflow` call. Follow the same workflow branch described above for both the red stage and the later implementation grouping.
When a task's pair or trio returns its verdict, observe and record the reports. Advance the contract to `awaiting_review`, then verify the task and advance it to `verified` or to `blocked` or `cancelled` before committing that task's changed files yourself, one commit per task, referencing the task name. Before generating another grouping, read the manifest and wait until every member of the current grouping is `used` or `expired`. A `registered` or `running` member means the grouping is not closed. After each task's verify step, record one `deviq-record.py evidence --phase <phase> --role <engineer-role> --field claim="..." --field check="..." --field result=pass|fail` from the engineer's report. If the paired critic returned BLOCK, also record `deviq-record.py block --phase <phase> --role <critic-role> --field trigger="..." --field consequence="..." --field fix="..." --field status=open`. Continue through the remaining tasks in that wave in PLAN order. Start the next dependency wave only after every task in the current wave is complete. Record command telemetry only after this main-session outcome is observed.

If an engineer deviates from the plan's stated `action`, record that deviation exactly as reported. Do not silently accept it or smooth it over, an unrecorded deviation becomes an unchecked claim `/qa` cannot gate on.

Once every wave is done, write `.lbwc-planning/phases/{NN}-{slug}/SUMMARY.md` from `templates/SUMMARY.md`. Include commit hashes, deviations, and an honest verdict for every `must_haves` truth, artifact, or key link from PLAN.md.

Report the commits made and the SUMMARY.md path. Tell the user to run `/lbwc:qa <phase>` next.

`deviq-record.py` prints a stable id for every block or evidence record it writes. Keep that id. Later resolution references `--field id=<id>`. Do not generate a solo `deviq` advisor while a build grouping is `registered` or `running`. If a group is blocked, close it first. Issue a new read-only `/lbwc:build` command contract for the advisor, then generate it with `--exclusive`. Apply its recommendation only through a newly contracted retry grouping.

## Failure and recovery

A failed contract, generator, tmux preflight, provision, split-group, bus publish/await/ack, worker verdict, verify command, commit, summary validation, or remediation transition blocks the task and its dependents. Preserve accepted predecessor commits and exact contract state. Report the failing task and recovery command. Never create a placeholder summary or bypass exclusive admission.

If the workflow generator fails or the `Workflow` call is denied for a grouping, leave that grouping's contract `planned` and report the failure verbatim. Do not fall back to `in_process` or `tmux`.

## Output Format

Show the phase, each task and grouping verdict, main-session commit hashes, deviations, summary path, telemetry status, and any blocker. Use the LBWC phase banner and no ANSI codes.

## Next Up

For a completed build, show `/lbwc:qa <phase>`. For a remediation build, show the same QA command for the active round. For a blocker, show only its exact recovery command, then stop.
