---
category: lifecycle
disable-model-invocation: true
description: Execute a phase PLAN through contract-bound pair or trio agents, one main-session commit per task, and a verified summary.
argument-hint: "<phase number or name>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent, SendMessage, LSP
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

After selecting the role and grouping, the main session opens one PLAN contract for that grouping. A TDD task has two contracts, `red` and `implementation`. Every other task has one `implementation` contract. The exact generator brief must be passed as `--job` to `open` and to the generator.

```bash
CONTRACT_PATH=$(bash "{LINK}/scripts/task-contract.sh" open "$PLAN_PATH" "{PROJECT_ROOT}" "$TASK_NAME" --role "$ROLE" --team "$TEAM_MODE" --group "$GROUP_NAME" --job "$BRIEF" "${CONTRACT_ALLOWANCE_ARGS[@]}")
TASK_ID=$(basename "$CONTRACT_PATH" .json)
```

Build `CONTRACT_ALLOWANCE_ARGS` only from the selected PLAN task's `<files>`. Repeat each engineer path as `--write-allowance <path>`. For a non-TDD trio, repeat each exact test path as `--role-write-allowance test-dev:<path>`. Use `qa-author`, `solo`, and only the exact test paths for the `red` contract. Use the selected engineer role, `pair`, and only implementation paths for the later TDD `implementation` contract. The contract writer rejects any allowance not declared in PLAN.

Pass the contract path, task id, job, team mode, and identical allowance arguments to one generator invocation. The main session owns `open`. Workers never create or modify contracts. If generation fails, leave that grouping contract `planned` and report the error.

Advance each grouping contract only from outcomes the main session observes. After successful registration, run `state ... dispatched`. After the manifest shows the admitted members `running`, run `state ... running`. After all reports arrive, run `state ... awaiting_review`. After verification, run `state ... verified`, `blocked`, or `cancelled`. Never advance one grouping from another grouping's outcome or from an unobserved worker claim. Record one bounded telemetry event only after the main session observes the command outcome:

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
2. When no snapshot exists, read validated execution configuration once. `agent_execution_mode=in_process` selects requested and resolved `in_process`. `agent_execution_mode=tmux` selects requested `tmux`. For `agent_execution_mode=ask`, ask one bounded execution-mode question before any contract or agent exists. If the user chooses `Cancel spawn`, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" cancel --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   Report cancellation and stop. This writes `{PHASE_DIR}/.runtime-cancelled.json` and creates no snapshot. A planned grouping contract stays unchanged. It must cancel, never fall back.
3. For requested `tmux`, complete preflight before freezing. On success resolve `tmux`. On failure, resolve `in_process` only if `tmux_execution.comms_fallback=fall_back_to_in_process`. Otherwise stop without a snapshot. Then run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" freeze --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}" --requested-backend "{REQUESTED_BACKEND}" --resolved-backend "{RESOLVED_BACKEND}"
   ```

   A `created` or `matched` result moves runtime state to `ready` and does not alter a task contract. Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation. The helper atomically records schema version, canonical phase, requested and resolved backend, effort, active routing profile and models, complete TMUX settings and restrictions, and the canonical source-config digest.
4. When the summary has been written and validated after every task reaches its terminal state, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" cleanup --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   This moves runtime state from `ready` to `cleaned`. A failed or blocked build preserves the snapshot for resume. A cleanup failure blocks the terminal transition and must be reported.

When the snapshot resolves `in_process`, use the native Agent path below unchanged. When it resolves `tmux`, follow `references/tmux-spawn-protocol.md` after issuing and generating the same contract.

For one wave, take the next task in PLAN order and generate only its current grouping with `--exclusive`, following `@references/agent-spawn-protocol.md`. For a pair or trio, spawn every member of that one grouping together in the same turn. Derive each member's manifest capability from the task's `files` field. Pass source paths through `--write-allowance` for the engineer and test paths through `--role-write-allowance test-dev:<exact-path>` for a non-TDD trio. Give the engineer the task's `name`, `action`, `verify`, and `done` fields verbatim as its brief. Do not ask an agent to declare or summarize file scope. Run the contract open and generator arguments in the preceding section after role selection and before this invocation.

- **TDD red stage:** open the `red` contract before generating solo `qa-author` with `--exclusive`. Pass the same must_haves brief and exact test-path allowances to both calls. Dispatch the contract before spawning. After the tests report and red commit, close its state from observed evidence. Wait until the manifest entry is `used` or `expired`. Then open a separate `implementation` pair contract for the engineer and critic. `test-dev` is not part of a TDD task.
When a task's pair or trio returns its verdict, observe and record the reports. Advance the contract to `awaiting_review`, then verify the task and advance it to `verified` or to `blocked` or `cancelled` before committing that task's changed files yourself, one commit per task, referencing the task name. Before generating another grouping, read the manifest and wait until every member of the current grouping is `used` or `expired`. A `registered` or `running` member means the grouping is not closed. After each task's verify step, record one `deviq-record.py evidence --phase <phase> --role <engineer-role> --field claim="..." --field check="..." --field result=pass|fail` from the engineer's report. If the paired critic returned BLOCK, also record `deviq-record.py block --phase <phase> --role <critic-role> --field trigger="..." --field consequence="..." --field fix="..." --field status=open`. Continue through the remaining tasks in that wave in PLAN order. Start the next dependency wave only after every task in the current wave is complete. Record command telemetry only after this main-session outcome is observed.

If an engineer deviates from the plan's stated `action`, record that deviation exactly as reported. Do not silently accept it or smooth it over, an unrecorded deviation becomes an unchecked claim `/qa` cannot gate on.

Once every wave is done, write `.lbwc-planning/phases/{NN}-{slug}/SUMMARY.md` from `templates/SUMMARY.md`. Include commit hashes, deviations, and an honest verdict for every `must_haves` truth, artifact, or key link from PLAN.md.

Report the commits made and the SUMMARY.md path. Tell the user to run `/lbwc:qa <phase>` next.

`deviq-record.py` prints a stable id for every block or evidence record it writes. Keep that id. Later resolution references `--field id=<id>`. Do not generate a solo `deviq` advisor while a build grouping is `registered` or `running`. If a group is blocked, close it first. Issue a new read-only `/lbwc:build` command contract for the advisor, then generate it with `--exclusive`. Apply its recommendation only through a newly contracted retry grouping.

## Failure and recovery

A failed contract, generator, worker verdict, verify command, commit, summary validation, or remediation transition blocks the task and its dependents. Preserve accepted predecessor commits and exact contract state. Report the failing task and recovery command. Never create a placeholder summary or bypass exclusive admission.

## Output Format

Show the phase, each task and grouping verdict, main-session commit hashes, deviations, summary path, telemetry status, and any blocker. Use the LBWC phase banner and no ANSI codes.

## Next Up

For a completed build, show `/lbwc:qa <phase>`. For a remediation build, show the same QA command for the active round. For a blocker, show only its exact recovery command, then stop.
