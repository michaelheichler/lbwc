---
category: monitoring
hidden: true
disable-model-invocation: true
description: Verify completed phase work.
argument-hint: "[phase-number] [--tier=quick|standard|deep] [--effort=thorough|balanced|fast|turbo]"
allowed-tools: Read, Write, Bash, Glob, Grep, Agent, Skill, LSP, AskUserQuestion, Workflow
---

# LBWC QA: $ARGUMENTS

## Context

Working directory:

```
!`pwd`
```

Plugin root:

```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; bash "$L/scripts/phase-detect.sh" > "/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

@${CLAUDE_PLUGIN_ROOT}/references/agent-spawn-protocol.md

Every QA spawn follows `{plugin-root}/references/agent-spawn-protocol.md`: issue a solo read-only QA contract with `scripts/task-contract.sh`, run generic `scripts/agent-generator.sh qa`, then advance that exact contract to `dispatched`. The main session owns mutable planning state, verification persistence, Git, and user questions.

Current state:

```text
!`head -40 .lbwc-planning/STATE.md 2>/dev/null || echo "No state found"`
```

Config: Pre-injected by SessionStart hook. Override with --effort flag.

Phase directories:

```text
!`ls .lbwc-planning/phases/ 2>/dev/null || echo "No phases directory"`
```

Phase state:

```text
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"
P="/tmp/.lbwc-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local resolver root
  resolver="$L/scripts/resolve-plugin-root.sh"
  if [ ! -f "$resolver" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
      resolver="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
    else
      return 1
    fi
  fi
  root=$(bash "$resolver" --require-script phase-detect.sh 2>/dev/null) || return 1
  PD=$(bash "$root/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect
then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

```text
!`bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-compact.sh" qa 2>/dev/null || true`
```

## Workflow capability gate

Refresh the saved Claude capability catalog before any QA contract or spawn:

```bash
bash "{plugin-root}/scripts/lbwc-model" refresh .lbwc-planning
```

This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`, the authority the execution-mode choice in Step 3 reads before offering or resolving `workflow`. A non-zero exit here does not stop QA. It leaves `RESOLVED_BACKEND` at `in_process`, so QA proceeds on whatever catalog already exists. Only a run that goes on to request or choose `workflow` can still be blocked, by step 0 of `workflow-spawn-protocol.md` and by `workflow-generator.sh`'s own live re-validation at generation time. Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.

## Guard

- Not initialized (no .lbwc-planning/ dir): STOP "Run /lbwc:init first."
- **Debug session override:** If `$ARGUMENTS` does NOT contain an explicit phase number OR `$ARGUMENTS` contains `--session`, check for an active debug session before any phase-related guards:

  ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" get-or-latest .lbwc-planning 2>/dev/null)" 2>/dev/null || true
  ```

  The helper exports `active_session`, `session_id`, `session_file`, and `session_status`, use `session_status` for lifecycle checks after `eval`.
  If `active_session != none` AND exported `session_status` is `qa_pending` or `qa_failed` AND (`phase_count=0` OR `$ARGUMENTS` contains `--session`) → skip ALL remaining guards and jump directly to `<debug_session_qa>` below.
  If phases exist (`phase_count > 0`) AND `$ARGUMENTS` does NOT contain `--session`, skip this override, standard phase QA takes priority.
- **Brownfield normalization:** If Phase state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:

  ```bash
  NORM_SCRIPT="{plugin-root}/scripts/normalize-plan-filenames.sh"
  if [ -f "$NORM_SCRIPT" ]; then
    for pdir in .lbwc-planning/phases/*/; do
      [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
    done
  fi
  ```

  Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
  Then re-run phase-detect.sh to refresh state (filenames changed):

  ```bash
  bash "{plugin-root}/scripts/phase-detect.sh" > "/tmp/.lbwc-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
  ```

  Use the refreshed phase-detect output for all subsequent guard checks and steps.
- **Auto-detect phase** (no explicit number): Phase detection is pre-computed in Context above. Use `next_phase` and `next_phase_slug` for the target phase.
  - If `next_phase_state=needs_qa_remediation`, target that phase directly.
    - If the remediation stage is `plan` or `execute`, STOP and tell the user to run `/lbwc:vibe` to continue QA remediation first, standalone QA must not mint a round VERIFICATION before re-verification is actually ready.
    - If the remediation stage is `verify` or `done`, standalone QA re-verifies the authoritative round artifact rather than overwriting the frozen phase-level VERIFICATION.
  - If `first_qa_attention_phase` is set and `qa_attention_status` is `pending`, `failed`, or `verify`, target that phase directly, existing QA artifacts may be stale or failed even when a file already exists, and verify-stage remediation rounds remain directly re-runnable even if an earlier phase is unfinished.
  - Otherwise, to find the first phase needing QA: scan phase dirs for first with completed `*-SUMMARY.md` files but no authoritative QA verification artifact (no numbered final VERIFICATION, no brownfield plain `VERIFICATION.md`, no wave fallback). Found: announce "Auto-detected Phase {NN} ({slug})". All verified: STOP "All phases verified."
- Phase not built (no SUMMARYs): STOP "Phase {NN} has no completed plans. Run /lbwc:vibe first."

## Debug Session Routing

<debug_session_qa>
**Before resolving phase target**, check for an active debug session. This handles the case where phase_count=0 but a debug session with `session_status=qa_pending` or `session_status=qa_failed` exists.

```bash
eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" get-or-latest .lbwc-planning)"
```

The helper exports `active_session`, `session_id`, `session_file`, and `session_status`, use `session_status` for routing after `eval`.

**Routing decision:**

- If `$ARGUMENTS` contains an explicit phase number AND no `--session` flag → skip debug-session routing, use standard phase QA flow below.
- If `active_session != none` AND exported `session_status` is `qa_pending` or `qa_failed` AND (`phase_count=0` OR `$ARGUMENTS` contains `--session`) → enter debug-session QA mode (below). If `phase_count > 0` and no `--session` flag, skip debug-session routing, standard phase QA takes priority.
- If `active_session != none` but exported `session_status` is NOT `qa_pending`/`qa_failed` → skip debug-session routing. Session is in a different lifecycle stage.
- If `active_session = none` → skip debug-session routing, continue to standard phase QA.

**Debug-session QA mode:**
When routed here, skip the standard phase-resolution Steps entirely. Instead:

1. Read the debug session's QA context:

   ```bash

  QA_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa)

   ```

2. Increment the QA round:
   ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-qa .lbwc-planning)"
   ```

1. Resolve tier: same logic as Step 1 below (--tier flag > --effort flag > config default > Standard).

2. Issue a read-only QA contract and generate the agent:

   ```bash
   PROJECT_ROOT=$(pwd)
   QA_BRIEF="debug-session verification, round {qa_round}"
   CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-qa-{session_id}-{qa_round}" --command qa --role qa --team solo --job "$QA_BRIEF") || exit 1
   TASK_ID=$(basename "$CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
   ```

   Read the emitted `Agent-call parameters:` and `SPAWN_READY` line. Spawn QA with only its printed `subagent_type`, `name`, and `model`. Do not add any other Agent-call fields.

    Before composing the QA task description, evaluate installed skills visible in your system context. Read each selected skill description. Select every materially helpful skill for this verification pass. Include supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context.

    The QA prompt MUST begin with exactly one skill outcome block. Use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when skills are preselected. Otherwise use `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>`. Do not omit both blocks.

    State the skill outcome in your response before spawning the agent. For example, write "Skills: activating {skill-name}" or "Skills: none preselected, {reason}". This is exactly one explicit skill outcome block. Select the single most direct skill, plus materially helpful adjacent skills. If the prompt or error mentions SwiftData, include `swiftdata` with relevant test, build, and debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.

  If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the debug-session QA agent. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

  Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.

   Task description for debug-session QA:
   ```text
   Debug session verification. Tier: {ACTIVE_TIER}. Round: {qa_round}.

   This is a debug-session QA round, NOT a phase-scoped verification. You are verifying
   a standalone debug fix, there are no phase PLAN.md or SUMMARY.md files.

   Session context (issue, investigation, plan, implementation, prior QA rounds):
   {QA_CONTEXT}

   Verification targets:
   - The root cause identified in the investigation is correct
   - The fix addresses the root cause (not just the symptom)
   - Changed files are correct and complete
   - No regressions introduced in modified files
   - Related tests pass

   Output your verdict as PASS, FAIL, or PARTIAL with a checks table.
   Return the structured qa_verdict payload inline. Do not write any file or run Git commands. The main session validates and persists the QA result.
   Format each check as: ID | Description | Status (PASS/FAIL) | Evidence
   ```

1. Process the QA result:
   - Parse the verdict (PASS/FAIL/PARTIAL) from the QA agent's response.
   - The main session validates the returned qa_verdict, advances the task contract through its observed states, and writes the QA round to the session file with `write-debug-session.sh`. Do not accept prose-only or malformed payloads.
   - Update session status based on result:
     - PASS → `bash .../debug-session-state.sh set-status .lbwc-planning uat_pending`
     - FAIL or PARTIAL → `bash .../debug-session-state.sh set-status .lbwc-planning qa_failed`

2. Present debug-session QA result:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug QA: Round {qa_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Tier:     {quick|standard|deep}
     Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
     Checks:   {passed}/{total}
     Failed:   {list or "None"}

   ```

   - If PASS: `➜ Next: /lbwc:verify --session -- Run UAT on the debug fix`
   - If FAIL/PARTIAL: `➜ Next: /lbwc:debug --resume -- Address QA failures and re-investigate`

   STOP after presenting. Do not continue to the standard phase QA steps.
</debug_session_qa>

Note: Continuous verification handled by hooks. This command is for deep, on-demand verification only.

## Steps

1. **Resolve tier:** Priority order: `--tier` flag > `--effort` flag > config
  default > Standard.
  Keep effort profile as `QA_EFFORT_PROFILE` (thorough|balanced|fast|turbo).
  Effort mapping: turbo=skip (exit "QA skipped in turbo mode"), fast=quick,
  balanced=standard, thorough=deep.
  Read `{plugin-root}/references/effort-profile-{profile}.md`.
  Context overrides: >15 requirements or last phase before ship → Deep.

2. **Resolve phase:** Use `.lbwc-planning/phases/` for phase directories.

3. **Spawn QA:**
    - **Choose the execution backend.** Follow step 0 of `{plugin-root}/references/workflow-spawn-protocol.md`, with `<control-root>` bound to `.lbwc-planning`. Use these literal `AskUserQuestion` fields when that step's `ask` branch applies:

      - header: `QA execution`
      - question: `Where should this QA verification run? Workflow run orchestrates it through a committed background script. Native spawn keeps the current single-agent QA run.`
      - options:
        - `Workflow run`: Verify through a committed workflow script in the background.
        - `Native spawn`: Keep the current native QA spawn.
        - `Cancel QA`: Do not verify this phase now.

      This gate applies only to standard phase QA. Debug-session QA in `<debug_session_qa>` always spawns `in_process`.

    - Follow `{plugin-root}/references/agent-spawn-protocol.md`. When `RESOLVED_BACKEND` is `in_process`, issue a solo read-only QA contract, generate it with the generic generator, and advance the contract to `dispatched`:

        ```bash
        PROJECT_ROOT=$(pwd)
        QA_BRIEF="verify phase {NN}, tier {ACTIVE_TIER}"
        CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "qa-{NN}-{task-slug}" --command qa --role qa --team solo --job "$QA_BRIEF") || exit 1
        TASK_ID=$(basename "$CONTRACT_PATH" .json)
        bash "{plugin-root}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" || exit 1
        bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
        ```

      Read `Agent-call parameters:` and `SPAWN_READY`. Spawn QA with only printed `subagent_type`, `name`, and `model`. Do not add any other Agent-call fields.

      When `RESOLVED_BACKEND` is `workflow`, follow `{plugin-root}/references/workflow-spawn-protocol.md`. Issue the same solo QA contract as a schema 3 contract. QA is read-only and its generated definition disallows the `Write` tool outright, so this contract carries no write capability:

        ```bash
        PROJECT_ROOT=$(pwd)
        CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
        QA_BRIEF="verify phase {NN}, tier {ACTIVE_TIER}"
        CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "qa-{NN}-{task-slug}" --command qa --role qa --team solo --job "$QA_BRIEF" --control-root "$CONTROL_ROOT" --requested-backend workflow --resolved-backend workflow) || exit 1
        TASK_ID=$(basename "$CONTRACT_PATH" .json)
        GENERATOR_OUTPUT=$(bash "{plugin-root}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --control-root "$CONTROL_ROOT" --execution-backend workflow) || exit 1
        NAME=$(printf '%s\n' "$GENERATOR_OUTPUT" | awk '/^SPAWN_READY/{print $2}')
        ```

      Read `Agent-call parameters:` and `SPAWN_READY <name>` from `GENERATOR_OUTPUT`, captured above as `NAME`, then render and register the workflow:

        ```bash
        bash "{plugin-root}/scripts/workflow-generator.sh" solo qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --name "$NAME" --control-root "$CONTROL_ROOT" || exit 1
        bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
        ```

      Read the `Workflow-call parameters:` block and the `WORKFLOW_READY <task-id>` line that follows it. Call `Workflow` exactly once with `scriptPath` set to the printed `path` value. Never pass `script`, and never inline or paraphrase the rendered file into the call. The `PreToolUse` guard on `Workflow` independently revalidates the path against the registered digest. A denial is a stop, not a fallback trigger. `Workflow` runs QA in the background. Its own tool result reports only the launch, never the QA verdict. Wait for the run's own terminal result. A `user_decision_required` result is the only path back to the user, ask exactly one bounded `AskUserQuestion` about it. Any other terminal result carries the `qa_verdict` payload. Process it exactly like the `in_process` branch above through the rest of this step and Step 4.

    - Display: `◆ Spawning QA...`
    - Resolve the VERIFICATION output path before spawning QA:

        ```bash
        QA_STATE=$(bash "{plugin-root}/scripts/qa-remediation-state.sh" get "{phase-dir}" 2>/dev/null || true)
        QA_STAGE=$(printf '%s\n' "$QA_STATE" | head -1)
        VERIF_PATH=$(printf '%s\n' "$QA_STATE" | awk -F= '/^verification_path=/{print $2; exit}')
        case "$QA_STAGE" in
          verify) ;;
          done)
            VERIF_PATH=$(bash "{plugin-root}/scripts/resolve-verification-path.sh" current "{phase-dir}" 2>/dev/null || true)
            [ -n "$VERIF_PATH" ] && [ ! -f "$VERIF_PATH" ] && VERIF_PATH=""
            if [ -z "$VERIF_PATH" ] || [ ! -f "$VERIF_PATH" ]; then
              echo "Phase {NN} QA remediation is done, but the round-scoped VERIFICATION artifact is missing. Re-run /lbwc:vibe to restore the remediation artifact before standalone QA." >&2
              exit 1
            fi
            ;;
          plan|execute)
            echo "Phase {NN} has active QA remediation at stage ${QA_STAGE}. Run /lbwc:vibe to continue remediation before standalone QA." >&2
            exit 1
            ;;
          *) VERIF_PATH="" ;;
        esac
        if [ -z "$VERIF_PATH" ]; then
          VERIF_NAME=$(bash "{plugin-root}/scripts/resolve-artifact-path.sh" verification "{phase-dir}")
          VERIF_PATH="{phase-dir}/${VERIF_NAME}"
        fi
        if [ ! -f "$VERIF_PATH" ]; then
          bash "{plugin-root}/scripts/track-known-issues.sh" sync-summaries "{phase-dir}" 2>/dev/null || true
        fi
        ```

      The guarded `sync-summaries` backfill above is for resumed phase-level QA only. It closes the interruption window where execution completed and `SUMMARY.md` files exist, but the earlier session ended before the post-build QA handoff created `{phase-dir}/known-issues.json`.

    - Before composing the QA task description, evaluate installed skills visible in your system context. Read each selected skill description and select every materially helpful skill for this verification pass, including supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context.

      The QA prompt MUST begin with exactly one skill outcome block. Use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when skills are preselected. Otherwise use `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>`. Do not omit both blocks.

      State the skill outcome in your response before spawning the agent. This is exactly one explicit skill outcome block. Select the single most direct skill, plus materially helpful adjacent skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.

      If the prompt or error mentions SwiftData, include `swiftdata` with relevant test, build, and debug skills.

      If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the phase QA agent. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

      Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.

    - Also evaluate available MCP tools in your system context. If any MCP servers provide build, test, documentation, or domain-specific capabilities relevant to verification, note them in the QA task context.

        ```text
        Verify phase {NN}. Tier: {ACTIVE_TIER}.
        Determine verification scope from `VERIF_PATH`.
        - If `VERIF_PATH` is under `remediation/qa/round-*/R*-VERIFICATION.md`, re-verify the remediation round using compounded remediation context.
          - Run `bash "{plugin-root}/scripts/compile-verify-context.sh" --remediation-only "{phase-dir}"` and use its `VERIFICATION HISTORY` section to re-verify each original FAIL from the source VERIFICATION.
          - Plans for `plans_verified` / `plan_ref`: {current round R{RR}-PLAN.md path(s) only}
          - Summaries for current-round execution evidence: {current round R{RR}-SUMMARY.md path(s) only}
          - Do NOT include phase-root PLAN.md/SUMMARY.md files in plans_verified or plan_ref for round-scoped output.
          - Any original FAIL not resolved by code-fix, plan-amendment, documented process-exception, or doc-fix is still a FAIL, even if the remediation round's own must_haves pass. A doc-fix requires a documentation-content subject and the named documentation path in files_modified.
        - Otherwise, verify full phase scope.
          - Plans: {paths to phase PLAN.md files}
          - Summaries: {paths to phase SUMMARY.md files}
          - If `{phase-dir}/known-issues.json` exists, read it as the authoritative tracked phase backlog. Re-check those known issues during this QA run and return only the ones that still remain unresolved in `pre_existing_issues`.
        Phase success criteria: {section from ROADMAP.md}
        If `.lbwc-planning/codebase/META.md` exists, read CONVENTIONS.md, TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.lbwc-planning/codebase/` to bootstrap codebase understanding before verifying.
        Verification protocol: `{plugin-root}/references/verification-protocol.md`
        Return findings using the qa_verdict schema (see `{plugin-root}/references/handoff-schemas.md`).
        If tests reveal pre-existing failures unrelated to this phase, list them in your response under a "Pre-existing Issues" heading and include them in the qa_verdict payload's pre_existing_issues array.
        Return the `qa_verdict` payload inline. Do not write `VERIFICATION.md`, planning artifacts, or Git state. The main session validates the payload and persists it with `write-verification.sh` to `{VERIF_PATH}`.
        ```

    - The sole main-session orchestrator persists VERIFICATION.md. It validates the QA payload, advances the observed task contract, and pipes the validated JSON through `bash "{plugin-root}/scripts/write-verification.sh" "{VERIF_PATH}"`. If validation or the writer fails, surface the error and do not fall back to manual writes.

4. **Reconcile with the deterministic QA gate before trusting the result:**
    - Immediately after the main session persists `VERIFICATION.md`, sync tracked known issues from the written artifact:

      ```bash
      bash "{plugin-root}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{VERIF_PATH}" 2>/dev/null || true
      ```

      After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:

      ```bash
      bash "{plugin-root}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
      ```

      Phase-level `VERIFICATION.md` merges newly found pre-existing issues into `{phase-dir}/known-issues.json` without clearing the execution-time backlog. Round-scoped `R{RR}-VERIFICATION.md` is authoritative for unresolved known issues and prunes/clears the registry when issues are fixed.

    - Then run:

      ```bash
      QA_GATE=$(bash "{plugin-root}/scripts/qa-result-gate.sh" "{phase-dir}" 2>/dev/null || true)
      QA_GATE_ROUTING=$(printf '%s\n' "$QA_GATE" | awk -F= '/^qa_gate_routing=/{print $2; exit}')
      ```

    - Follow `QA_GATE_ROUTING` literally:
      - `PROCEED_TO_UAT` → if `VERIF_PATH` is round-scoped (`remediation/qa/round-*/R*-VERIFICATION.md`), persist the remediation transition first:

        ```bash
        bash "{plugin-root}/scripts/qa-remediation-state.sh" advance "{phase-dir}"
        ```

        Then continue to presentation.
      - `REMEDIATION_REQUIRED` → if `VERIF_PATH` is round-scoped (`remediation/qa/round-*/R*-VERIFICATION.md`), persist the next remediation round first:

        ```bash
        bash "{plugin-root}/scripts/qa-remediation-state.sh" needs-round "{phase-dir}"
        ```

        Then display that standalone QA found a result, but the deterministic gate still requires remediation, tell the user to continue via `/lbwc:vibe`. Do **not** present the round as a shippable PASS. If `qa_gate_process_exception_evidence_missing=true`, say the round has a clean verification result but lacks recorded remediation-artifact evidence, and the next round should record an existing remediation `RNN-PLAN.md`/`RNN-SUMMARY.md` or valid original phase `PLAN.md`. If `qa_gate_known_issues_override=true`, note that the contract checks passed but `{qa_gate_known_issue_count}` tracked known issues remain unresolved in `{phase-dir}/known-issues.json`.
      - `REMEDIATION_REQUIRED` → if `VERIF_PATH` is phase-level, initialize QA remediation state first so plain `/lbwc:vibe` has a deterministic resume target:

        ```bash
        bash "{plugin-root}/scripts/qa-remediation-state.sh" init "{phase-dir}" 2>/dev/null || true
        ```

        Then display that the phase-level QA result was written, but the deterministic gate still requires remediation, tell the user to continue via `/lbwc:vibe`. Do **not** continue to the generic verified presentation. If `qa_gate_process_exception_evidence_missing=true`, say the round has a clean verification result but lacks recorded remediation-artifact evidence, and the next round should record an existing remediation `RNN-PLAN.md`/`RNN-SUMMARY.md` or valid original phase `PLAN.md`. If `qa_gate_known_issues_override=true`, note that the contract checks passed but `{qa_gate_known_issue_count}` tracked known issues remain unresolved in `{phase-dir}/known-issues.json`.
      - `QA_RERUN_REQUIRED` → display that the persisted verification artifact is invalid or incomplete and must be re-run before it can be trusted. Do **not** present it as authoritative.

5. **Present:** Per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md:

    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Phase {NN}: {name} -- Verified
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Tier:     {quick|standard|deep}
      Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
      Checks:   {passed}/{total}
      Failed:   {list or "None"}

      Report:   {path to VERIFICATION.md}

    ```

**Discovered Issues:** Collect pre-existing failures, out-of-scope bugs, and unrelated issues. De-duplicate by test name and file. Keep the first message for duplicate pairs. Append the list after the result box. Show at most 20 entries. If more exist, append `... and {N} more`:

```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Registry: {phase-dir}/known-issues.json
```

This display is supplemental to the phase registry. After `VERIFICATION.md` is written, the orchestrator must sync these issues into `{phase-dir}/known-issues.json` before reading the deterministic gate. Do NOT create todos automatically or enter an interactive loop here. If no discovered issues: omit the section entirely. Cap the list at 20 entries. After displaying discovered issues, STOP. Do not take further action.

Run:

```text
bash "{plugin-root}/scripts/suggest-next.sh" qa {result}
```

Then display the output.

## Failure and recovery

- If a contract, generator, spawn, qa_verdict validation, or writer step fails, stop and report the error verbatim. Do not create an uncontracted QA fallback.
- If the workflow generator fails or the `Workflow` call is denied, leave the contract `planned` and report the failure verbatim. Do not fall back to `in_process`.
- Preserve phase and debug-session state until the main-session write succeeds.

## Output Format

Use the existing debug and phase result blocks. Label a result authoritative only after the main session validates and persists it.

## Next Up

Use the existing result routing and `suggest-next.sh` output.
