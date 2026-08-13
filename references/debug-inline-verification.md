# Debug Inline Verification

This protocol owns the QA and UAT stages for a standalone debug session. It does not use phase PLAN.md or SUMMARY.md files.

## Inline QA

Run QA automatically after a verified fix commit or when a resumed session has `session_status=qa_pending` or `fix_applied`.

1. Resolve configuration:

   ```bash
   AUTO_UAT=$(jq -r '.auto_uat // "false"' .lbwc-planning/config.json 2>/dev/null || echo "false")
   if [ -z "${EFFORT_PROFILE:-}" ]; then
     EFFORT_PROFILE=$(jq -r '.effort // "balanced"' .lbwc-planning/config.json 2>/dev/null || echo "balanced")
   fi
   QA_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa)
   ```

2. Map effort to `ACTIVE_TIER`: fast=quick, balanced=standard, thorough=deep. For turbo, set status to `uat_pending` and continue at Inline UAT without incrementing QA.

3. Increment the QA round:

   ```bash
   eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-qa .lbwc-planning)"
   ```

4. Issue and dispatch a read-only QA contract:

   ```bash
   PROJECT_ROOT=$(pwd)
   QA_BRIEF="debug-session verification, round {qa_round}"
   CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-qa-{session_id}-{qa_round}" --command debug --role qa --team solo --job "$QA_BRIEF") || exit 1
   TASK_ID=$(basename "$CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
   ```

5. Read `Agent-call parameters:` and `SPAWN_READY`. Spawn QA using only printed `subagent_type`, `name`, and `model`.

6. Select all materially helpful direct and narrowly adjacent skills from session context, errors, files, and bounded enrichment. Prefer explicit domain markers over generic stack guesses. The QA prompt starts with exactly one rendered `<skill_activation>` or `<skill_no_activation>` block from `references/skill-activation-payload.md`. If skills were selected, run `extract-skill-follow-up-files.sh` and include only its emitted follow-up block. Read only named follow-up files.

7. Use this task description after the skill block:

   ```text
   Debug session verification. Tier: {ACTIVE_TIER}. Round: {qa_round}.

   This is a debug-session QA round, not phase-scoped verification.

   Session context:
   {QA_CONTEXT}

   Verify:
   - The identified root cause is correct.
   - The fix addresses the root cause.
   - Changed files are correct and complete.
   - Modified workflows have no regression.
   - Related tests pass.

   Return PASS, FAIL, or PARTIAL with rows:
   ID | Description | Status (PASS/FAIL) | Evidence

   Return qa_verdict inline. Do not write files or run Git commands.
   ```

8. Persist the result:

   ```bash
   QA_RESULT_JSON=$(cat <<'ENDJSON'
   {
     "mode": "qa",
     "round": {qa_round},
     "result": "{PASS|FAIL|PARTIAL}",
     "checks": [
       {"id": "{check-id}", "description": "{description}", "status": "{PASS|FAIL}", "evidence": "{evidence}"}
     ]
   }
   ENDJSON
   )
   echo "$QA_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

9. Set `uat_pending` for PASS. Set `qa_failed` for FAIL or PARTIAL.

10. Present exactly:

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

For FAIL or PARTIAL, display `QA found issues. Re-investigating...`, compile QA failure context, set status to `investigating` through `write-debug-session.sh`, and re-enter investigation Step 3 with failure context prepended. After the next fix commit, QA runs again. For PASS, continue at Inline UAT.

## Inline UAT

Run UAT when QA passes, turbo skips QA, or a resumed session has `session_status=uat_pending`.

1. Resolve `AUTO_UAT` if unset:

   ```bash
   if [ -z "${AUTO_UAT:-}" ]; then
     AUTO_UAT=$(jq -r '.auto_uat // "false"' .lbwc-planning/config.json 2>/dev/null || echo "false")
   fi
   ```

2. When `AUTO_UAT` is not true, invoke AskUserQuestion as a tool call and wait:

   - Question: `QA passed. Run UAT verification now?`
   - Header: `Debug Session`
   - Options: `Yes` to run inline, `No` to resume later.

   Never print the question parameters as text. Treat clearly affirmative freeform input as Yes, negative or deferring input as No, and ask one short follow-up for ambiguity. For No, stop with `➜ Next: /lbwc:debug --resume -- Continue to UAT verification`.

3. Compile context and increment the UAT round:

   ```bash
   UAT_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" uat)
   eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-uat .lbwc-planning)"
   ```

4. Generate one to three checkpoints that require human judgment: reproduce the original bug, inspect related workflows, and verify the user-visible result. Never ask the user to run tests, lint, builds, or other automated checks. For an internal-only fix, use one checkpoint: `Does the app still work as expected from your perspective?`

5. Present one checkpoint and its AskUserQuestion tool call in the same assistant response. Wait for the response before continuing:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     CHECKPOINT {NN}/{total}, Debug Fix Verification
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   {scenario description}
   ```

   The tool question is self-contained: `Scenario: {scenario description}\n\nExpected: {expected result}\n\nDoes the behavior match this checkpoint?` Header is `UAT`; options are `Pass` and `Skip`. Map freeform Other text to an issue and infer severity: crash/broken/error=critical, wrong/missing/bug=major, minor/cosmetic=minor, otherwise major.

6. Persist all responses verbatim:

   ```bash
   UAT_RESULT_JSON=$(cat <<'ENDJSON'
   {
     "mode": "uat",
     "round": {uat_round},
     "result": "{pass|issues_found}",
     "checkpoints": [
       {"id": "{id}", "description": "{description}", "result": "pass|skip|issue", "user_response": "{verbatim}"}
     ],
     "issues": [
       {"id": "{id}", "description": "{description}", "severity": "{level}"}
     ]
   }
   ENDJSON
   )
   echo "$UAT_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

7. For no issues, set status to `complete` and run the planning Git boundary when its session-link helper exists. For issues, set status to `uat_failed`.

8. Present exactly:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug UAT: Round {uat_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Result:   {✓ COMPLETE | ✗ ISSUES FOUND}
     Passed:   {N}
     Issues:   {N}
   ```

For issues, display `UAT found issues. Re-investigating...`, compile UAT failure context, set status to `investigating` through `write-debug-session.sh`, and re-enter investigation Step 3. After the next fix commit, the QA then UAT chain runs again. For success, display `➜ Debug session complete. The fix is verified.` and stop.
