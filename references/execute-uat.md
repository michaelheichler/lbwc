# LBWC execution adaptation

This is a behavior-preserving port. The main session owns task contracts, generated-agent admission, mutable planning state, verification persistence, telemetry, git, and user-facing output. A worker may change only the exact paths in its dispatched contract. `scripts/phase-detect.sh`, `scripts/qa-result-gate.sh`, `scripts/write-verification.sh`, `scripts/remediation-round.sh`, and `references/agent-spawn-protocol.md` replace source-specific routing, persistence, and lifecycle authority.

**Phase 3 rule:** an unavailable helper named below is a required Phase 3 dependency, not a command to emulate. The full surrounding guard, evidence, recovery, and output behavior remains mandatory once the helper is supplied. Existing LBWC helpers are the only commands that run today.

Assume `PLUGIN_ROOT` was resolved by `references/execute-protocol.md` before this fragment runs.

**Autonomy gate:**

| Autonomy | UAT active |
| -------- | ---------- |
| cautious | YES |
| standard | YES |
| confident | OFF |
| pure-vibe | OFF |

**Override:** If `auto_uat` is `true` in config, UAT is always active regardless of autonomy level.

Read autonomy and auto_uat from config:
```bash
AUTONOMY=$(jq -r '.autonomy // "standard"' .lbwc-planning/config.json)
AUTO_UAT=$(jq -r '.auto_uat // false' .lbwc-planning/config.json)
```

If `AUTO_UAT` is not `true` and autonomy is confident or pure-vibe: display "○ UAT verification skipped (autonomy: {level})" and proceed to Step 5.

**UAT execution:**

Require a fresh authoritative root or QA-remediation verification before creating or resuming UAT. Resolve completed QA remediation with `resolve-verification-path.sh authoritative`, not `phase`. Then source the freshness helper and fail closed on every non-fresh result:

```bash
VERIFICATION_PATH=$(bash "${PLUGIN_ROOT}/scripts/resolve-verification-path.sh" authoritative "$PHASE_DIR")
[ -f "$VERIFICATION_PATH" ] || { printf '%s\n' 'LBWC: authoritative verification artifact is missing' >&2; exit 1; }
. "${PLUGIN_ROOT}/scripts/verification-freshness.sh"
if verification_is_stale "$VERIFICATION_PATH" "$PHASE_DIR" || [ "$VERIFICATION_FRESHNESS_REASON" != fresh ]; then
  printf 'LBWC: verification freshness is not proven (%s)\n' "$VERIFICATION_FRESHNESS_REASON" >&2
  exit 1
fi
```

Require the persisted result to be PASS and require a supported `qa-result-gate.sh` `PROCEED_TO_UAT` result. A UAT remediation round has no supported deterministic gate or authoritative verification resolver. It is a Phase 3 blocker, so it cannot enter UAT from this protocol.

Resolve the UAT filename before proceeding:
```bash
UAT_NAME=$(bash "${PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" uat "{phase-dir}")
```

1. Check if `{phase-dir}/${UAT_NAME}` already exists with `status: complete`. If so: "○ UAT already complete" and proceed to Step 5.
2. Generate test scenarios from the compiled UAT verification context:
  ```bash
  UAT_CONTEXT_HELPER="${PLUGIN_ROOT}/scripts/compile-verify-context-for-uat.sh"
  [ -f "$UAT_CONTEXT_HELPER" ] || { printf '%s\n' 'LBWC: UAT context helper is unavailable' >&2; exit 1; }
  UAT_VERIFY_CONTEXT=$(bash "$UAT_CONTEXT_HELPER" "{phase-dir}") || exit 1
  ```

  **Required Phase 3 dependency:** `scripts/compile-verify-context-for-uat.sh`. Until it is installed, stop here. Do not emulate its output.
  Treat this compact context as the authoritative UAT input. It includes merged PLAN/SUMMARY details, remediation scope, the correct `uat_path`, and any unsuppressed `SUMMARY_DEVIATION:` records. Do not independently re-read individual SUMMARY.md files to build UAT scope.
  - Parse `verify_scope=full` vs `verify_scope=remediation round=RR` from the compiled context.
  - Parse `uat_path=` and write the UAT file there. For full scope this is usually `${UAT_NAME}`. for remediation it is the round-scoped UAT path.
  - Parse each `SUMMARY_DEVIATION:` record (`signature`, `source_plan`, `source_path`, `text`). These records are already filtered against `{phase-dir}/remediation/uat/accepted-deviations.json`. do not re-prefill accepted records.

  **Summary deviation review prefill (NON-NEGOTIABLE):** Before generated plan checkpoints, create one `D{NN}` review checkpoint for each `SUMMARY_DEVIATION:` record, in the same stable order.
  - These are review checkpoints, not blocking issues. Start `**Result:**` empty and leave `issues: 0` in the initial frontmatter unless the human later rejects a deviation.
  - Write them before any generated `P...` or `PR...` checkpoints.
  - Include identity metadata exactly in the entry: `**Source:** Summary deviation review`, `**Deviation Signature:** {signature}`, `**Source Plan:** {source_plan}`, `**Source Summary:** {source_path}`, and `**Deviation:** {text}`.
  - Use `**Expected:** Human confirms whether this documented deviation is acceptable for this phase.`
  - Include the `D{NN}` entries in `total_tests`. they remain incomplete until the human answers.

  Generate plan/remediation scenarios from the compiled context:
  - Use each context record's built work, files modified, and must_haves
   - Generate 1-3 test scenarios per plan requiring HUMAN judgment: things only a person can verify
   - Minimum 1 test per plan. Test IDs: `P{plan}-T{NN}`
  - In remediation re-verification mode, use remediation checkpoint IDs `PR{RR}-T{NN}` (for example, `PR03-T01`) and focus on whether the original UAT issue was fixed.

   **UAT tests must require human judgment.** Good examples:
   - Open the app and navigate to screen X: does it display Y correctly?
   - Perform user workflow A → B → C: does the result look right?
   - Check that the UI reflects the change: is the label/value/layout correct?

   **NEVER generate tests that can be performed programmatically.** These belong in QA (Step 4), not UAT:
   - ✗ Grep/search files for expected content or missing imports
   - ✗ Verify file existence, deletion, or structure
   - ✗ Run a test suite or individual test (xcodebuild test, pytest, bats, jest, etc.)
   - ✗ Run a CLI command and check its exit code or output
   - ✗ Execute a script and verify it passes
   - ✗ Run a linter, type-checker, or build command

   **What belongs in UAT (ask the user):**
   - Visual/UI correctness
   - Domain-specific data validation
   - UX flows and usability
   - Behavior that requires the running app or hardware
   - Subjective quality

   **What does NOT belong in UAT (the agent or QA already handles these):**
   - Running test suites: QA runs these during execution. Do NOT ask the user to run tests.
   - Checking command output, exit codes, or build success
   - Grepping files for expected content
   - Verifying file existence or structure
   - Any check that can be performed programmatically via Bash, Grep, or Glob

   **Skill-aware exclusion:** UI automation may make an interaction programmatic. If a skill, tool, or MCP server can check it, keep it in QA. UAT includes only subjective quality, visual design, domain data judgment, or hardware behavior that available tooling cannot automate.

   Purely internal work still gets one lightweight checkpoint. Ask the user whether the app still works as expected. Do not ask the user to run automated checks.

  - Write initial UAT file at `{phase-dir}/{uat_path}` with all tests (prefilled `D{NN}` review checkpoints first, then generated `P...` or `PR...` checkpoints. all Result fields empty)
3. **CHECKPOINT loop: present ONE test at a time, wait for user response:**

   **This is a conversational loop. Do NOT present all tests at once. Do NOT end the session after presenting a test. Do NOT proceed to Step 5 until all tests are complete.**

   For the FIRST test without a result, display a CHECKPOINT followed by AskUserQuestion:

    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    CHECKPOINT {NN}/{total}: {plan-id}: {plan-title}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    {scenario description}
    ```

    Then use AskUserQuestion. Keep the modal question self-contained because it may cover the surrounding checkpoint prose:

    ```yaml
    question: "Does this checkpoint match? Scenario: {scenario description}. Expected: {expected result}."
    header: "UAT"
    multiSelect: false
    options:
      - label: "Pass"
        description: "Behavior matches expected result"
      - label: "Skip"
        description: "Cannot test right now: skip this checkpoint"
    ```

   The tool automatically provides a freeform "Other" option for the user to describe issues.

  **Summary-deviation checkpoint prompt:** A prefilled `D{NN}` review shows deviation text and source metadata instead of a product scenario.

  The terminal display and AskUserQuestion value are self-contained. Each includes `Deviation: {text}` and `Source: {source_path} ({source_plan})`. Include a signature only when it distinguishes similar deviations. The generic artifact expectation cannot be the only visible question.

  A deviation review has these visible options:
  - `Pass`: Accept this deviation as non-blocking for this phase.
  - `Track Todo`: Accept this deviation and add an LBWC todo.
  - `Skip`: Leave this deviation unaccepted for now.

  These options stay within the AskUserQuestion limit. Normal product checkpoints keep `Pass` and `Skip`. Freeform input records a UAT issue when it rejects the deviation or reports a product defect, except for high-confidence todo intent handled below.

   **STOP HERE.** Wait for the AskUserQuestion response. Do NOT continue to the next test or to Step 5.

   **After the user responds:**

   Map the AskUserQuestion response:

  **Pass:** Record pass. A prefilled deviation also gets `Disposition: accepted-process-exception`. Plain Pass accepts it without a todo.

  **Track Todo:** This is valid only for a prefilled deviation. Record `Result: pass` and `Disposition: accepted-process-exception`. Mark it accepted and tracked without adding a new Result value.

  **Skip:** Record skip. A prefilled deviation also gets `Disposition: skipped-by-user` and remains unaccepted.

  **Freeform:** Normalize case, whitespace, curly apostrophes, dash separators, and contractions. Rejection markers take precedence over todo language. Rejection records `Result: issue` and `Disposition: rejected-by-user`. Skip words record skip. A high-confidence todo request follows the accepted-and-tracked path only when no rejection marker is present. Any other response is an issue.

  Infer issue severity from the response. Crash, broken, and error are critical. Wrong, missing, and bug are major. Minor, cosmetic, and nitpick are minor. The default is major. A rejected prefilled deviation gets `Disposition: rejected-by-user`.

  **Issue description capture:** Persist the expectation, human-observed behavior, and relevant visible attachment facts. Correct typos and remove filler without changing meaning. Do not store raw images, attachment blobs, base64 data, or placeholder attachment claims. Do not invent facts, debug the project, run commands, or implement a fix during capture.

  A separate defect observation in a pass or skip response creates a new UAT issue. Scan existing `D{NN}` headings, allocate the next unused number, and never renumber an existing entry. Persist the UAT artifact immediately.
  - If the response accepts and tracks a prefilled summary-deviation checkpoint (`Track Todo` or high-confidence todo-intent freeform), run `bash "${PLUGIN_ROOT}/scripts/track-uat-deviations.sh" todo-from-uat "{phase-dir}" "{phase-dir}/{uat_path}" "{test-id}"` after writing the UAT file. Use only the helper-emitted `todo_ref` to write or update `**Tracking:** accepted deviation added to todos (ref:{todo_ref})` or `**Tracking:** accepted deviation already tracked in todos (ref:{todo_ref})`. If the helper reports `no_state_file`, `missing_metadata`, `not_accepted`, empty output, or any other failure status, keep the UAT `Result: pass` and write `**Tracking:** accepted deviation todo tracking unavailable ({status})` rather than claiming a todo was added.

**Required Phase 3 dependency:** `scripts/track-uat-deviations.sh`. Preserve this guard. Do not emulate its result, state transition, or output.
  - If the response accepts a prefilled summary-deviation checkpoint, run `bash "${PLUGIN_ROOT}/scripts/track-uat-deviations.sh" record-from-uat "{phase-dir}" "{phase-dir}/{uat_path}"` after any todo tracking update. The helper is idempotent. never hand-edit `accepted-deviations.json`.

**Required Phase 3 dependency:** `scripts/track-uat-deviations.sh`. Preserve this guard. Do not emulate its result, state transition, or output.
   - Display progress: `✓ {completed}/{total} tests`
   - If more tests remain: present the NEXT test using the same CHECKPOINT format with AskUserQuestion, then **STOP and wait again**
   - If all tests done: go to step 4

4. After all tests complete:
   - Update UAT.md frontmatter (status, completed date, final counts)
  - Run `bash "${PLUGIN_ROOT}/scripts/track-uat-deviations.sh" record-from-uat "{phase-dir}" "{phase-dir}/{uat_path}"` after finalization so accepted summary-deviation signatures are available to suppress future duplicate prefill.

**Required Phase 3 dependency:** `scripts/track-uat-deviations.sh`. Preserve this guard. Do not emulate its result, state transition, or output.
   - If no issues: proceed to Step 5
   - If issues found: display the issue summary. For an initial UAT failure, run `scripts/remediation-round.sh open "$PHASE_DIR" uat` and retain its emitted `plan_path`. For a detector-selected existing UAT round, use `scripts/remediation-round.sh current "$PHASE_DIR" uat` only to resume. Write the exact `R{RR}-PLAN.md` from `templates/REMEDIATION-PLAN.md`.
   - Validate the written UAT remediation plan before build. `scripts/validate-uat-remediation-artifact.sh plan "$PLAN_PATH"` is a required Phase 3 dependency. Until it exists and passes, report the validation blocker and do not route to build.
   - Only after validation passes, transition `plan` to `execute` with `scripts/remediation-round.sh stage "$PHASE_DIR" uat execute`. Then report `Next Up: /lbwc:build {NN}`. Stop without starting build or QA.

**Inline execution (NON-NEGOTIABLE):** The orchestrator runs the CHECKPOINT loop directly in the main conversation: this is NOT a subagent operation. Do NOT spawn a QA agent, Dev agent, or any subagent for UAT. Do NOT use TaskCreate to delegate UAT. The AskUserQuestion tool is only available to the orchestrator: subagents cannot interact with the user, so delegating UAT to a subagent bypasses user input entirely. The orchestrator must wait for user input at each checkpoint.


## Completion output and Next Up

After every checkpoint has a Result, the main session is the only writer of the UAT artifact and state. `status: complete` requires no `Result: issue` entry. `status: issues_found` requires a persisted issue description, severity, and remediation route. Never claim completion from a skipped or absent artifact.

A clean result reports the UAT path, total checkpoints, pass count, skip count, issue count, and `Next Up: /lbwc:vibe`. An issue result reports the exact UAT path, current remediation round, cap result when the round helper exits 3, and `Next Up: /lbwc:build {NN}`. A resumed UAT reports its next incomplete checkpoint and waits for the human. No worker, agent, or automatic follow-up may replace that wait.
