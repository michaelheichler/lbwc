# LBWC execution adaptation

This is a behavior-preserving port. The main session owns task contracts, generated-agent admission, mutable planning state, verification persistence, telemetry, git, and user-facing output. A worker may change only the exact paths in its dispatched contract. `scripts/phase-detect.sh`, `scripts/qa-result-gate.sh`, `scripts/write-verification.sh`, `scripts/remediation-round.sh`, and `references/agent-spawn-protocol.md` replace source-specific routing, persistence, and lifecycle authority.

**Phase 3 rule:** an unavailable helper named below is a required Phase 3 dependency, not a command to emulate. The full surrounding guard, evidence, recovery, and output behavior remains mandatory once the helper is supplied. Existing LBWC helpers are the only commands that run today.

Assume `PLUGIN_ROOT` was resolved by `references/execute-protocol.md` before this fragment runs.

After the main session writes the validated VERIFICATION artifact, sync tracked known issues from that artifact before reading a supported gate:
```bash
bash "${PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification-output-path}"
```

A sync failure blocks the QA contract and stops routing. `promote-todos` is a required Phase 3 dependency. Do not claim that a surviving issue was promoted unless an installed helper persisted it.

- Phase-level VERIFICATION writes merge new pre-existing issues into the existing registry without clearing the execution-time backlog.
- Round-scoped `R{RR}-VERIFICATION.md` writes are authoritative for unresolved known issues only when the current remediation kind is QA.
- The current `qa-result-gate.sh` has no UAT-round scope. A UAT-round result cannot use this gate or claim `PROCEED_TO_UAT`. UAT-round deterministic gating is a required Phase 3 dependency.

After root QA or QA-round QA completes, run the supported deterministic gate:
```bash
bash "${PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
```

**Follow `qa_gate_routing` literally for root QA only:**
- **`qa_gate_routing=PROCEED_TO_UAT`:** Display `◆ QA: PASS` and route to UAT only when the result is root QA and freshness is proven.
- **`qa_gate_routing=REMEDIATION_REQUIRED`:** Display `◆ QA: ${qa_gate_result} (${qa_gate_fail_count} FAIL)`. For an initial root QA failure, open the round before reading its paths:
  ```bash
  bash "${PLUGIN_ROOT}/scripts/remediation-round.sh" open "$PHASE_DIR" qa
  ```
  Exit code 3 reports the configured cap and stops. After a successful open, use `scripts/remediation-round.sh current "$PHASE_DIR" qa` to resume the emitted round. Existing rounds use `current` only for resume.
- **`qa_gate_routing=QA_RERUN_REQUIRED`:** Display the writer and result, then create a fresh QA contract. Allow two retries. A deviation override requires every summary deviation to become a FAIL check. A coverage override requires every phase plan in `plans_verified`. After the second invalid result, stop and report manual intervention.

**QA Remediation Loop (inline, same session):**

This loop runs inline during execution. If the session ends mid-loop, `phase-detect.sh` routes to `needs_qa_remediation` on the next `/lbwc:vibe` call.

1. **Init or resume state:**
   - On an initial root QA failure, call `remediation-round.sh open "$PHASE_DIR" qa` before any `current` query.
   - On a detector-selected existing QA round, call `remediation-round.sh current "$PHASE_DIR" qa`.
   - Parse `stage`, `round`, `round_dir`, `plan_path`, `summary_path`, `verif_path`, and `uat_path` from the round helper. The state helper metadata below remains a Phase 3 blocker for source selection.

  Parse source metadata only after those steps: `source_verification_path`, `source_fail_count`, `known_issues_path`, `known_issues_count`, `input_mode`, and `verification_path`.

  **Required Phase 3 dependency and blocker:** current `qa-remediation-state.sh` does not populate source-verification, source-fail-count, known-issue, or input-mode metadata. Do not treat its empty values as evidence that no source exists. Stop the QA remediation flow here. Do not create a plan, run build, run round QA, advance state, or claim `PROCEED_TO_UAT` is reachable. Phase 3 must extend and test this helper before the source-selection branch can run.

  <qa_remediation_artifact_contract>
  `round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths. Claude Code may run subagents from `.claude/worktrees/agent-*` sidechain CWDs. pass these exact paths to Lead, Dev, and QA prompts and never rewrite them relative to the current CWD. Rewriting those paths relative to sidechain CWDs can write or read remediation artifacts from the wrong location and break resume or verification.
  </qa_remediation_artifact_contract>
  <qa_remediation_spawn_contract>
  Research and planning use sequential solo contracts. Execution uses one contracted pair or trio at a time through `references/agent-spawn-protocol.md`. Spawn every generated member together, close the group, then start the next task. Use remediation metadata paths in prompts. Do not pass isolation or worker cwd fields.
  </qa_remediation_spawn_contract>
  <qa_remediation_no_tool_circuit_breaker>
  After any QA remediation Lead, Dev, or QA subagent returns, follow the no-tool circuit breaker in `references/subagent-contracts.md` before artifact validation, deterministic gates, or state advancement. If it triggers, STOP without advancing `.qa-remediation-stage` and report the failed role and stage or task.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  </qa_remediation_no_tool_circuit_breaker>

2. **Phase 3 loop blueprint (not enabled until the metadata blocker is fixed):**

   **stage=plan:** Create `R{RR}-PLAN.md` in `{round_dir}`:
  - Read `source_verification_path` from `qa-remediation-state.sh get` metadata for failed checks when `source_fail_count>0`
  - Read `known_issues_path` when `known_issues_count>0`: this is the phase-scoped unresolved known-issues backlog that must clear before UAT

     **Source selection:**
     - Round 01 uses the phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`)
     - Round 02+ first checks the previous round's `R{RR}-VERIFICATION.md`. If that artifact still contains FAIL checks, use it. If it passed QA but the deterministic gate still required another remediation round, carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs.

    - If `source_verification_path` is empty and `known_issues_count=0`, STOP and restore the earlier verification artifact that should have carried the unresolved FAILs before planning. Do NOT silently continue when the previous round verification is missing or when the carried-forward phase-level source artifact no longer exists.

   - **Deviation Classification (NON-NEGOTIABLE):** For each FAIL check in the source VERIFICATION.md, classify as exactly one of:
      **Implementation fixes:**
      - **`code-fix`**: The code/config must change to match the plan. The remediation plan MUST include tasks that modify the executable/config/test artifacts that actually implement the fix: not just planning or documentation files.

      **Plan and process decisions:**
      - **`plan-amendment`**: The deviation was a valid improvement over the original plan. The remediation plan MUST include a task to update the original PLAN.md with the actual approach and rationale, marking the deviation as resolved-by-amendment.
      - **`process-exception`**: Genuinely non-fixable retroactive issue (e.g., cannot un-batch a historical commit without risky rebase). The remediation plan must include the exception classification with explicit reasoning why it is non-fixable.

      **Documentation fixes:**
      - **`doc-fix`**: The documentation artifact is the product surface under test. The remediation plan MUST include `path: "docs/file.md"` for the named documentation path, and the round summary must record that same path in `files_modified`.
   - **The plan MUST include at least one `code-fix`, `doc-fix`, or `plan-amendment` task if ANY FAIL check is classifiable as such.** A plan that classifies all FAIL checks as `process-exception` when code-fix, doc-fix, or plan-amendment alternatives exist is itself a defect. Documentation-only changes to SUMMARY.md deviations arrays are NOT a valid resolution for code/architecture deviations.
   - Include `fail_classifications:` YAML array in R{RR}-PLAN.md frontmatter.

     - `code-fix` / `process-exception` entries: `{id: "FAIL-ID", type: "code-fix|process-exception", rationale: "..."}`
     - `doc-fix` entries: `{id: "FAIL-ID", type: "doc-fix", path: "docs/file.md", rationale: "..."}`
     - `plan-amendment` entries MUST also identify the original plan being amended: `{id: "FAIL-ID", type: "plan-amendment", rationale: "...", source_plan: "01-01-PLAN.md"}`. `source_plan` must reference an original plan in the current phase only: never a sibling phase, archived milestone, or remediation plan.

    - Always include `known_issues_input:` and `known_issue_resolutions:` in R{RR}-PLAN.md frontmatter. When `known_issues_count=0` or `input_mode=verification`, set both to empty arrays (`known_issues_input: []` and `known_issue_resolutions: []`) rather than omitting them.
    - When `input_mode=known-issues` or `input_mode=both`, populate `known_issues_input:` with every carried known issue from `known_issues_path` using the canonical `{test,file,error}` JSON object-string shape already used for tracked issues.
    - When `input_mode=known-issues` or `input_mode=both`, populate `known_issue_resolutions:` with a matching entry for every carried known issue using `{test,file,error,disposition,rationale}` JSON object strings. Valid `disposition` values are `resolved`, `accepted-process-exception`, and `unresolved`.

     - `resolved` = this round fixes the issue and QA should no longer return it in `pre_existing_issues`
     - `accepted-process-exception` = QA must verify the issue is real but non-blocking for this phase, omit it from `pre_existing_issues`, and leave it visible via the summary/STATE backlog instead of reopening the round forever
     - `unresolved` = the issue remains blocking and the next round must continue to carry it

    - Do NOT omit the `known_issues_input` or `known_issue_resolutions` keys. Do NOT omit a carried known issue from either array. The deterministic gate treats missing coverage as a failed remediation round even if QA writes `PASS`.
   - Scope the plan to those failures: what to fix, which files, acceptance criteria
  - **LBWC Lead superseder:** The main session issues a read-only command contract for role `lead`. It passes the identical remediation brief to `scripts/agent-generator.sh lead --contract <path> --task-id <id>`, advances the contract to `dispatched`, and uses the final `SPAWN_READY` name. The Lead returns complete plan content. The main session writes `{round_dir}/R{RR}-PLAN.md`. The generated output supplies model and permitted parameters.
  - The Lead brief includes the authoritative host paths, failed-check source, known-issue source, every classification and resolution rule above, and `templates/REMEDIATION-PLAN.md`. It never receives a worker cwd or isolation option.
  - After the Lead returns, apply the no-tool circuit breaker before filename validation, plan validation, or state advance. A no-tool result leaves the round in `plan`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.

  - Normalize plan filenames before validation:
    ```bash
    NORM_SCRIPT="${PLUGIN_ROOT}/scripts/normalize-plan-filenames.sh"

**Required Phase 3 dependency:** `scripts/normalize-plan-filenames.sh`. Preserve this guard. Do not emulate its result, state transition, or output.
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{round_dir}"
    fi
    ```
  - Validate the exact QA remediation plan artifact before advancing:
    ```bash
    bash "${PLUGIN_ROOT}/scripts/validate-uat-remediation-artifact.sh" plan "{round_dir}/R{RR}-PLAN.md"

**Required Phase 3 dependency:** `scripts/validate-uat-remediation-artifact.sh`. Preserve this guard. Do not emulate its result, state transition, or output.
    ```
    If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`. Do not search for an alternate PLAN.md.
  - After plan validation passes, advance state: `bash "${PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`

   **stage=execute:** Execute `R{RR}-PLAN.md` through `/lbwc:build {NN}`.
   - The build command creates one PLAN task contract per grouping, derives agent shape from the task, and calls the generic agent generator. It replaces a role-specific source Dev generator and static model resolution.
   - QA remediation does not create a durable agent team. Each exclusive solo, pair, or trio grouping uses the normal LBWC contract and manifest lifecycle. A worktree cwd, isolation option, `team_name`, and background emulation remain prohibited.
   - The main session verifies each task, commits its observed contract-limited output, and writes `R{RR}-SUMMARY.md` from `templates/REMEDIATION-SUMMARY.md`.
   - The summary frontmatter includes aggregate `commit_hashes`, `files_modified`, and `deviations`. It records `known_issue_outcomes` for each carried known issue and uses dispositions matching the plan resolution.
   - A missing, nonterminal, or unsupported summary leaves the round in `execute`. Apply the no-tool circuit breaker before summary inspection or stage advance.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.

   - After main-session verification of the terminal summary, move the round from `execute` to `verify` through the installed remediation state transition.

   **stage=verify:** Re-run QA:
   - Run `compile-verify-context.sh --remediation-only {phase-dir}` to get compounded verification history plus the current round's plan/summary context only
   - Spawn QA through a fresh read-only LBWC command contract. QA returns `qa_verdict` evidence. The main session validates and writes it to `{verification_path}`.
     - Output path: `{round_dir}/R{RR}-VERIFICATION.md`, phase-level VERIFICATION.md stays frozen
    - After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before syncing known issues or running the deterministic gate. If it triggers, STOP without advancing `.qa-remediation-stage`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
     - After the main session persists `{verification_path}`, immediately sync tracked known issues from that round artifact:
       ```bash
       bash "${PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification_path}"
       ```
     - Do not call the unavailable `promote-todos` operation. Phase 3 must add and test it before the command can claim surviving issues were added to `STATE.md`.
    - If `compile-verify-context.sh` emits a `KNOWN ISSUES` block, include in QA's task description: "Tracked phase known issues are not informational in remediation rounds. Re-check every carried known issue from `known_issues_input` / `known_issue_resolutions`. Return only still-blocking issues in `pre_existing_issues`. If a carried issue is verified as an `accepted-process-exception`, omit it from `pre_existing_issues`, confirm that the accepted non-blocking disposition is credible for this phase, and rely on the matching `known_issue_outcomes` entry to preserve visibility after the blocking registry clears. A clean remediation QA run must return an empty `pre_existing_issues` array for all resolved or accepted non-blocking carried issues so `{phase-dir}/known-issues.json` can clear."
     - Include the compiled verify context output in QA's task description
      - **Include in QA task description:** "In addition to verifying the remediation plan's own must_haves, you MUST re-verify each original FAIL from the VERIFICATION HISTORY section. For each FAIL_ID: if classified as code-fix, verify the code now matches the plan. if classified as doc-fix, verify the named documentation path now contains the required content. if classified as plan-amendment, verify the original PLAN.md has been updated with the actual approach and rationale. if classified as process-exception, verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL. if code-fix, doc-fix, or plan-amendment still appears viable, keep the FAIL open. Any original FAIL that has not been addressed by one of these four paths is still a FAIL."
      - The deterministic gate validates structural evidence only. QA must decide whether a `process-exception` is *actually* justified during this re-verification step: documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment.
   - After QA returns, run the deterministic gate:
     ```bash
     bash "${PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
     ```
     **Phase 3 gate contract:** After Phase 3 extends and tests source metadata, follow `qa_gate_routing` literally. Until then, no QA remediation branch can report `PROCEED_TO_UAT`.
     - A future `PROCEED_TO_UAT` result advances the QA round to done only after the state helper supplied the required source metadata and the gate proved it.
     - A future `REMEDIATION_REQUIRED` result opens the next QA round with `remediation-round.sh open "$PHASE_DIR" qa`. It preserves unresolved known issues.
     - A future `QA_RERUN_REQUIRED` result creates a fresh QA contract, with at most two retries. It includes every deviation and plan-coverage correction the gate reports.

     Before Phase 3, display `⚠ QA remediation blocked: source verification metadata is unavailable.` Stop and require the helper extension and tests. Do not advance state or route to UAT.
      - **When `qa_gate_metadata_only_override=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round made no implementation changes: only planning/documentation updates. The round still depends on a code-fix path (or omitted fail_classifications), so the original failures cannot be considered resolved without implementation changes. ${qa_gate_phase_deviation_count} phase deviations remain recorded.` This override is the deterministic safety net for rounds that still depend on implementation changes. Pure plan-amendment rounds can pass when the original plan was actually updated, and pure process-exception rounds still need planning/remediation-artifact evidence: delivered docs/README changes alone do not count. The next round's `stage=plan` MUST classify each FAIL as code-fix, doc-fix, plan-amendment, or process-exception per the Deviation Classification rules above.
      - **When `qa_gate_doc_fix_evidence_missing=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round classifies a FAIL as doc-fix, but the gate cannot find a recorded change to the named documentation path. Edit the exact documentation path named in the FAIL evidence and record it in files_modified before treating the doc-fix as resolved.` This is a doc-fix-specific evidence gap, not a code-fix gap: do not ask the next round for implementation changes. Continue with a new remediation round.
      - **When `qa_gate_process_exception_evidence_missing=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round has a clean verification result, but the gate cannot find recorded remediation-artifact evidence. Record an existing remediation RNN-PLAN.md/RNN-SUMMARY.md or a valid original phase PLAN.md before treating the process-exception as resolved.` Continue with a new remediation round.
      - **When `qa_gate_round_change_evidence_empty=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Display `⚠ QA remediation round recorded no change evidence: both files_modified and commit_hashes were empty. A PASS without any recorded changed files or commits cannot resolve prior FAILs.` The next round must produce real code/plan changes or capture justified remediation evidence instead of an empty summary.
      - **When `qa_gate_round_change_evidence_unavailable=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Pure `plan-amendment` and `process-exception` rounds are validated by their own evidence paths (source-plan coverage and process-exception artifact evidence respectively) rather than by code change evidence. Display `⚠ QA remediation round recorded change evidence that could not be verified as current-round work. Either the recorded files did not match any committed or current round-local remediation-artifact changes after the source verification commit, or the referenced commit_hashes could not be proven to belong to this round, so the actual changed files could not be trusted.` Restore explicit files_modified entries and/or round-local commit evidence anchored to the remediation round before treating the failures as resolved.
