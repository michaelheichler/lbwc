---
category: lifecycle
description: "The one command. Detects state and parses intent. Routes to lifecycle modes including import, bootstrap, scope, plan, execute, verify, discuss, archive, and more."
argument-hint: "[intent or flags]. Modes: [--import [path]] [--plan] [--execute] [--verify] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive]. Modifiers: [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]."
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, AskUserQuestion, Agent, SendMessage, Skill, LSP, Workflow
disable-model-invocation: true
---

# LBWC Vibe

## Shared interaction contract

Read @${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md after resolving `{LINK}` in the Context block. Follow it for every bounded decision.

## Context

Working directory (store as `{PROJECT_ROOT}`):

```text
!`pwd`
```

Plugin root and pre-computed state (first line is `LINK`, remaining lines are `PD`):

```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-phase-state.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-phase-state.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R"`
```

Config:

```bash
!`cat .lbwc-planning/config.json 2>/dev/null || echo "No config found"`
```

```bash
!`bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-compact.sh" execute 2>/dev/null || true`
```

## Index freshness gate

Before reading the input parser or selecting a lifecycle mode, run exactly:

```bash
bash "{LINK}/scripts/indexer-sync.sh" --project-root "{PROJECT_ROOT}"
```

This is mandatory. Stop before mode selection when the helper exits non-zero.

## Workflow capability gate

Refresh the saved Claude capability catalog before any Execute-mode grouping contract or spawn:

```bash
bash "{LINK}/scripts/lbwc-model" refresh "{PROJECT_ROOT}/.lbwc-planning"
```

This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`, the authority Execute mode reads before offering or resolving `workflow`. Stop before Execute mode when the helper exits non-zero. Skip this gate when `.lbwc-planning/` is missing. Every other mode ignores this gate. Do not create a planning directory here.

## Input Parsing

Read `{LINK}/references/vibe-input-parsing.md` and use its route precedence and detector contract.

## Guard

Require `phase_detect_complete=true`. Stop on `phase_detect_error=true`, a missing canonical plugin root, malformed detector output, an invalid explicit phase, or a detector-selected blocking remediation route. Never guess a plugin path or replace a missing helper with an inline approximation.

Only the main session may ask the user, write planning artifacts, advance task or remediation state, or run Git. Generated agents work through dispatched contracts from `references/agent-spawn-protocol.md`. A pending user decision blocks every dependent spawn and mutation.

When detector output has `needs_milestone_rename=true`, the main session itself must run `{LINK}/scripts/rename-default-milestone.sh`. Validate its result, then re-run phase detection before selecting a mode. A generated agent never performs this migration.

### Confirmation Gate

Every mode triggers confirmation before executing. Follow the shared interaction contract in `references/ask-user-question.md`, then use the AskUserQuestion tool with the question from the routing table's Confirmation column (marked with `→ AskUserQuestion:`). This section stays local to `/lbwc:vibe`: it defines when confirmation is skipped, which routing copy to use, and which alternatives belong to each route.

- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).

**Discussion-aware alternatives:** Alternatives must reflect whether discussion has already happened for the target phase. Never offer "discuss this phase" as if discussion never happened. When `{NN}-CONTEXT.md` exists, use continuation-aware wording like "Start a discussion" (which enters the Discussion Engine's continuation mode, building on existing context rather than repeating it).

| Routing state | Recommended | Alternatives |
| --- | --- | --- |
| `needs_discussion` | "Discuss phase {NN}" | "Skip discussion and plan directly", "View phase goal first" |
| `needs_plan_and_execute` | "Plan and execute phase {NN}" | "Plan only (review before executing)", "Start a discussion (explore gray areas before planning)" |
| `needs_execute` | "Execute phase {NN}" | "Review plans first", "Start a discussion (revisit scope before executing)" |
| `milestone_uat_issues` | "Create remediation phases" | "Start fresh with new work", "Not now" |

## Modes

### Mode: Import

Explicit `--import [path]` and clear natural-language requests to import, migrate, or bring in external plans route here before Init Redirect. Do not infer import intent from ordinary planning language.

If the project is uninitialized and an external plan source is detected, ask one bounded choice: `Import external plan`, `Start fresh initialization`, or `Cancel`. Import routes to `/lbwc:import`. Fresh initialization routes to Init Redirect. Cancel leaves project state unchanged.

Read `commands/import.md` and execute that workflow inline in the main session. Preserve any active remediation state because import is an explicit user-selected interruption, not a replacement for the persisted remediation backlog. After promotion, re-run phase detection before selecting the next lifecycle mode.

### Mode: Init Redirect

If `planning_dir_exists=false`: display "Run /lbwc:init first to set up your project." STOP.

### Mode: Bootstrap

Read `{LINK}/references/vibe-mode-bootstrap.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Steps:**

1. Load context: PROJECT.md, REQUIREMENTS.md. If `.lbwc-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.lbwc-planning/codebase/`.
2. If $ARGUMENTS (excl. flags) provided, use as scope. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. **Decompose through a contracted Architect:** Follow `references/agent-spawn-protocol.md`. Build one complete brief from PROJECT.md, REQUIREMENTS.md, the scope description, and the required output shape. Issue a solo, read-only `architect` command contract for `milestone scope decomposition`. Run the generic `scripts/agent-generator.sh architect` call with the identical brief, contract path, and task id. Advance the contract to `dispatched`, then use the emitted `model` and final `SPAWN_READY` name for `subagent_type` and `name`. Pass no effort, max-turn, timeout, team, background, isolation, or worker-cwd fields.

   Render the prompt prefix through `references/skill-activation-payload.md`. Ask the Architect to return a complete roadmap proposal with 3 to 5 independently plannable phases, goals, success criteria, dependency order, decomposition rationale, and REQ-ID mapping. The Architect is read-only. It does not write ROADMAP.md or mutate planning state. Apply the no-tool invariant from `references/subagent-contracts.md` to its return.

   Validate the returned phase count, unique names, complete REQ-ID coverage, dependency order, and source scope. The main session writes `.lbwc-planning/ROADMAP.md` only after that validation. A malformed, incomplete, or tool-less return stops Scope mode without writing partial roadmap state. Display `◆ Spawning Architect agent...` followed by `✓ Architect agent complete` only after validation.
4. Read the validated phase list from ROADMAP.md. Create `.lbwc-planning/phases/{NN}-{slug}/` directories for each phase.
5. Update STATE.md by calling bootstrap-state.sh. Extract `PROJECT_NAME` from PROJECT.md, derive `MILESTONE_NAME` from the scope description (step 2), and use the phase count from step 3. The script preserves existing project-level sections (Todos, Decisions, Blockers, Codebase Profile) while restoring the `## Current Phase` section:

   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .lbwc-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
   ```

   Do NOT write next-action suggestions (e.g. "Run /lbwc:vibe --plan 1") into the Todos section. Those are ephemeral display output from suggest-next.sh, not persistent state.
6. Write milestone context to `.lbwc-planning/CONTEXT.md` using the template from `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/MILESTONE-CONTEXT.md`. Capture:
   - **Gathered date** and **Calibration** (builder or architect, inferred from conversation signals, using the same calibration as the Discussion Engine)
   - **Scope Boundary:** the user's scope description from step 2
   - **Decomposition Decisions:** rationale for phase count, grouping, and ordering from step 3. Includes **Scope Coverage** (what the milestone covers vs what is explicitly excluded or deferred) as a subsection under Decomposition Decisions per the template structure.
   - **Requirement Mapping:** which REQ-IDs map to which phases (from step 3)
   - **Key Decisions:** project-level decisions surfaced during scoping (tech choices, architecture patterns that transcend the milestone). Also insert these as rows in STATE.md's `## Key Decisions` table (append after the header row, replacing the `_(No decisions yet)_` placeholder if present). Milestone-scoped decisions (phase ordering rationale, scope boundaries) stay only in CONTEXT.md.
   - **Deferred Ideas:** out-of-scope ideas mentioned during steps 2-3
7. **Scope commit boundary (conditional):**

   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "scope milestone" .lbwc-planning/config.json
   ```

   Behavior: `planning_tracking=commit` commits `.lbwc-planning/` if changed (ROADMAP.md, STATE.md, CONTEXT.md, phase dirs). Other modes no-op.
8. Display "Scoping complete. {N} phases created." STOP. Do not auto-continue to planning.

### Mode: Discuss

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** First phase without `*-CONTEXT.md`. All discussed: STOP "All phases discussed. Specify: `/lbwc:vibe --discuss N`"

**Continuation mode:** When the target phase already has a `{NN}-CONTEXT.md`, this is a **continuation discussion**, not a fresh one. If the CONTEXT.md has `pre_seeded: true` in its YAML frontmatter (remediation phase), WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning. Otherwise display: "Phase {NN} already has discussion context. Continuing to explore additional topics." The Discussion Engine will load existing decisions as baseline and focus on uncovered gray areas.

**Steps:**

1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase.
3. **Discussion commit boundary (conditional):**

   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "discuss phase {NN}" .lbwc-planning/config.json
   ```

   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Continuation mode:** Same as Discuss mode. If a `{NN}-CONTEXT.md` exists, this is a continuation. Pre-seeded remediation phases get the same warning.

**Steps:**

1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase. Pass "Discussion mode: assumptions" to the engine. Step 1.7 handles the assumptions workflow (codebase analysis, assumption formation, user correction, capture).
3. **Discussion commit boundary (conditional):**

   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "assumptions phase {NN}" .lbwc-planning/config.json
   ```

   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

Read `{LINK}/references/vibe-uat-remediation.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Milestone UAT Recovery

Read `{LINK}/references/vibe-mode-milestone-uat-recovery.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Plan

Read `{LINK}/references/vibe-mode-plan.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Execute

Before loading the execute protocol, resolve `{PHASE_DIR}` as the selected canonical directory below `{PROJECT_ROOT}/.lbwc-planning/phases/`. Its frozen runtime snapshot path is `{PHASE_DIR}/.runtime-snapshot.json`.

1. When that path exists, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" validate --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   On success, use the returned `snapshot.requested_backend`, `snapshot.resolved_backend`, `snapshot.effort`, `snapshot.routing_profile`, `snapshot.routing_roles`, and `snapshot.tmux_execution` as the sole execution authority. Do not resolve again from live configuration. A non-zero result is `backend drift` or malformed runtime state. Stop before contracts, generation, spawning, telemetry, or prompts and preserve all state.
2. When no snapshot exists, read the validated execution configuration once. An explicit `agent_execution_mode` wins outright, including an explicit `in_process` or `tmux`. `agent_execution_mode=in_process` selects requested and resolved `in_process`. `agent_execution_mode=tmux` selects requested `tmux`. `agent_execution_mode=workflow` selects requested `workflow`: read `.workflow.available` from `{PROJECT_ROOT}/.lbwc-planning/claude-capabilities.json` and `.workflow_execution.enabled` from `{PROJECT_ROOT}/.lbwc-planning/config.json`. When `.workflow.available` is `false`, stop before any contract or agent exists and report `.workflow.unavailable_reasons` verbatim. Otherwise, when `.workflow_execution.enabled` is not `true`, stop before any contract or agent exists with `workflow backend is disabled in configuration`. Otherwise resolve `workflow`. There is no automatic fallback from a requested `workflow` to another backend. For `agent_execution_mode=ask`, read both `.workflow.available` and `.workflow_execution.enabled` from the same catalog and config first, then ask one bounded execution-mode question before any contract or agent exists. Follow `{LINK}/references/ask-user-question.md`: exactly one question, `multiSelect` false, two to four visible options.

   - header: `Execute execution`
   - question when `.workflow.available` and `.workflow_execution.enabled` are both `true`: `Where should this phase's task groupings run? Workflow run orchestrates each grouping through a committed background script. Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.`
   - options when `.workflow.available` and `.workflow_execution.enabled` are both `true`, `Workflow run` first:
     - `Workflow run`: Run each grouping through a committed workflow script in the background.
     - `Native spawn`: Keep the current native Agent spawn.
     - `TMUX panes`: Start each grouping as a fresh pane session through provision and split-group.
     - `Cancel spawn`: Do not spawn any grouping for this execution.
   - question when `.workflow.available` or `.workflow_execution.enabled` is not `true`: `Where should this phase's task groupings run? Native keeps the current Claude Code Agent spawn. TMUX starts each grouping as a fresh pane session.`
   - options when `.workflow.available` or `.workflow_execution.enabled` is not `true`, the same three options with `Workflow run` left out entirely:
     - `Native spawn`: Keep the current native Agent spawn.
     - `TMUX panes`: Start each grouping as a fresh pane session through provision and split-group.
     - `Cancel spawn`: Do not spawn any grouping for this execution.

   If the user chooses `Workflow run`, select requested and resolved `workflow`. If the user chooses `Native spawn`, select requested and resolved `in_process`. If the user chooses `TMUX panes`, select requested `tmux`. If the user chooses `Cancel spawn`, run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" cancel --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}"
   ```

   Report the cancellation and stop. This transition writes `{PHASE_DIR}/.runtime-cancelled.json` and creates no snapshot. It does not mutate contracts, manifests, or telemetry. Never fall back to in-process agents.
3. For requested `tmux`, complete TMUX preflight before freezing. On preflight success, resolved backend is `tmux`. On preflight failure, only `tmux_execution.comms_fallback=fall_back_to_in_process` may resolve to `in_process`. `bus_only` stops without a snapshot. Then run exactly:

   ```bash
   bash "{LINK}/scripts/runtime-snapshot.sh" freeze --planning-dir "{PROJECT_ROOT}/.lbwc-planning" --phase-dir "{PHASE_DIR}" --requested-backend "{REQUESTED_BACKEND}" --resolved-backend "{RESOLVED_BACKEND}"
   ```

   A `created` or `matched` result moves runtime state to `ready` without changing task contracts. Pass its `snapshot.resolved_backend` to every generator or TMUX dispatch. The helper atomically records schema version, canonical phase, requested and resolved backend, effort, active routing profile and models, complete TMUX settings and restrictions, and the canonical source-config digest.

Copy snapshot backends into CLI flags. Control root is `{PROJECT_ROOT}/.lbwc-planning`, the freeze `--planning-dir`. When `snapshot.requested_backend` equals `snapshot.resolved_backend`, pass those values plus `--control-root` and `--assert-snapshot` so `open` cannot disagree with the snapshot. When they differ, that is the already-frozen `comms_fallback` case: omit the schema 3 backend flags (`open` requires matching backends), then follow the native Agent path.

Pass `snapshot.resolved_backend` to every `agent-generator.sh --execution-backend` invocation that follows a schema 3 open. Stop on contract, generator, preflight, provision, split-group, or bus failure. Do not silently switch to in-process except the already-frozen `comms_fallback` case above. Schema 2 generation omits `--execution-backend`.

If `snapshot.resolved_backend` is `in_process`, keep the native Agent path in `{LINK}/references/vibe-mode-execute.md`.

If `snapshot.resolved_backend` is `tmux`, `{LINK}/references/vibe-mode-execute.md` follows `{LINK}/references/tmux-spawn-protocol.md` on this branch only. Do not call native Agent. Do not invent a second orchestrator. Do not follow execute-protocol Agent spawn on this branch.

If `snapshot.resolved_backend` is `workflow`, `{LINK}/references/vibe-mode-execute.md` follows `{LINK}/references/workflow-spawn-protocol.md` on this branch only. Do not call native Agent and do not run the tmux spawn driver.

Read `{LINK}/references/vibe-mode-execute.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Verify

Read `{LINK}/references/vibe-mode-verify.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Add Phase

Read `{LINK}/references/vibe-mode-add-phase.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Insert Phase

Read `{LINK}/references/vibe-mode-insert-phase.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Remove Phase

Read `{LINK}/references/vibe-mode-remove-phase.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Mode: Archive

Read `{LINK}/references/vibe-mode-archive.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`.

### Pure-Vibe Phase Loop

After Execute mode completes, continue automatically only when the installed configuration resolves autonomy to `pure-vibe`. Before each iteration, require every task contract to be terminal, every generated manifest member to be `used` or `expired`, every main-session commit to exist, and the selected summary and verification artifacts to validate. Re-run `phase-detect.sh` instead of carrying forward a prior route.

If the new detector output selects the next unbuilt phase, run its Plan mode and then Execute mode. Stop on `all_done`, any blocking remediation route, a required user decision, contract or manifest drift, a failed gate, or missing evidence. Other autonomy levels stop after the current phase. LBWC solo, pair, and trio groups close through their manifest lifecycle. Do not invent a source team shutdown flow or a delegation-state marker.

## Failure and recovery

A failed root resolver, detector, contract issue, generator call, tmux preflight, provision, split-group, bus publish/await/ack, artifact validation, state transition, or planning Git helper stops the current mode. Report the exact failing command boundary and preserve existing state. Never create placeholder plans, summaries, verification, or UAT files to make detection advance. Recovery re-runs `/lbwc:vibe` after the named blocker is corrected. If a bounded user dialog is dismissed or killed, clear the pending decision and resume normally.

If the workflow generator fails or the `Workflow` call is denied during Execute mode, leave that grouping's contract `planned` and report the failure verbatim. Do not fall back to `in_process` or `tmux`.

## Output Format

Before rendering output, read `{LINK}/references/lbwc-brand-essentials.md` and follow it. `{LINK}` is the first line of the plugin-root/state block in the Context output, labeled `first line is LINK`. Skip this read for Verify mode because UAT files use plain markdown.

Per-mode output:

- **Bootstrap:** project-defined banner + transition to scoping
- **Scope:** phases-created summary + STOP
- **Discuss:** ✓ for captured answers, Next Up Block
- **Assumptions:** numbered list with confidence indicators: ✓ confirmed (high), ⚡ validated (medium), ? resolved (low), ✗ corrected, ○ expanded (user added nuance), Next Up
- **Plan:** Phase Banner (double-line box), plan list with waves/tasks, Effort, Next Up
- **Execute:** Phase Banner, plan results (✓/✗), Metrics (plans, effort, deviations), QA result, "What happened" (NRW-02), Next Up
- **Add/Insert/Remove Phase:** Phase Banner, ✓ checklist, Next Up
- **Archive:** Phase Banner, Metrics (phases, tasks, commits, reqs, deviations), archive path, tag, branch, memory status, Next Up

Rules: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

## Next Up

Only after the selected mode reaches its terminal boundary, run `bash "{LINK}/scripts/suggest-next.sh" vibe {result}`. Render its exact next command in one Next Up Block, then stop. Do not begin the suggested mode in the same turn unless the Pure-Vibe Phase Loop explicitly authorizes it.
