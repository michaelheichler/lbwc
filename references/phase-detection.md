# LBWC execution adaptation

This is a behavior-preserving port. The main session owns task contracts, generated-agent admission, mutable planning state, verification persistence, telemetry, git, and user-facing output. A worker may change only the exact paths in its dispatched contract. `scripts/phase-detect.sh`, `scripts/qa-result-gate.sh`, `scripts/write-verification.sh`, `scripts/remediation-round.sh`, and `references/agent-spawn-protocol.md` replace source-specific routing, persistence, and lifecycle authority.

**Phase 3 rule:** an unavailable helper named below is a required Phase 3 dependency, not a command to emulate. The full surrounding guard, evidence, recovery, and output behavior remains mandatory once the helper is supplied. Existing LBWC helpers are the only commands that run today.

Commands resolve `PLUGIN_ROOT` through the session-link contract before applying this protocol.

# LBWC Phase Auto-Detection Protocol

Single source of truth for detecting the target phase when the user omits the phase number from a command. Referenced by `$PLUGIN_ROOT/commands/vibe.md` and the QA protocol (`qa.md`, hidden from `/help`).

## Overview

When `$ARGUMENTS` contains no explicit phase number, commands use this protocol to infer the correct phase from the current planning state. Detection logic varies by command type because each command targets a different stage of the phase lifecycle.

Note: `/lbwc:vibe` has additional state detection that precedes phase scanning (see its State Detection section). The algorithms below are used once the command has determined that phase-level detection is needed.

## Resolve Phases Directory

Phases always live at `.lbwc-planning/phases/` (root-canonical).

All directory scanning below uses this path.

## Detection by Command Type

**LBWC superseder:** every command invokes `scripts/phase-detect.sh` and consumes its complete result. The command-specific rules below constrain which emitted state is actionable. They never rescan directories, recalculate a state, or replace an active remediation route.

### Planning Commands (`/lbwc:vibe --plan`, `/lbwc:vibe --discuss`, `/lbwc:vibe --assumptions`)

**Goal:** Act on the detector result that requires planning or discussion.

**Algorithm:**
1. Run the detector and require `phase_detect_complete=true`.
2. For `needs_discussion`, route to `/lbwc:discuss {NN}` only when the configured discussion gate is active.
3. For `needs_plan_and_execute`, route to `/lbwc:plan {NN}`.
4. For any state with an existing plan, require an explicit replan request. Do not choose a phase by scanning plan filenames.
5. If every phase is planned, report `All phases are planned. Specify a phase to re-plan: /lbwc:plan N` and stop.

### Discussion Gate (`require_phase_discussion` config)

When `require_phase_discussion=true`, `phase-detect.sh` emits `needs_discussion` before `needs_plan_and_execute` when a phase lacks both plan and context evidence. When discussion context exists, the detector advances to the ordinary planning state. When the config is false, commands accept the ordinary detector result without adding a local gate.

### Build Command (`/lbwc:vibe --execute`)

**Goal:** Act on the earliest detector-selected phase whose execution evidence is incomplete.

**Algorithm:**
1. Accept `needs_execute` for a root PLAN, or an active remediation execution state for its exact round PLAN.
2. Read the root or round path emitted by `scripts/remediation-round.sh current <phase-dir> <qa|uat>`.
3. Require all predecessor contract and summary evidence before a dependent task starts.
4. If all planned phases are terminally built, report `All planned phases are built. Specify a phase to rebuild: /lbwc:build N` and stop.

**Matching logic:** `phase-detect.sh` and task-contract state supersede filename-prefix matching. A terminal SUMMARY requires contract, verdict, verification, and commit evidence.

### QA Protocol (`qa.md`)

**Goal:** Act on the earliest pre-UAT phase that needs verification or QA remediation.

**Algorithm:**
1. Use the detector `first_qa_attention_phase`, `qa_attention_status`, `qa_status`, `qa_reason`, and `qa_round` when they identify an earlier QA obligation.
2. Before UAT cutover, an active QA round in `verify` is the target and uses its persisted round verification path.
3. Resolve the authoritative verification path with `scripts/resolve-verification-path.sh authoritative <phase-dir>`. A completed QA remediation uses its round verification only. A missing round artifact fails closed.
4. A pending, failed, or verify QA attention result takes priority over an older root artifact until UAT cutover.
5. If `qa_after_uat_dormant=true` or `qa_reason=uat_cutover`, keep the command in the UAT lane. Stale QA state is traceability, not a new remediation route.
6. If all built phases have fresh authoritative verification, report `All phases verified.` and stop.

**Verification result parsing:** `result:` is authoritative. A legacy `status:` is accepted only when `result:` is absent and it is PASS, FAIL, or PARTIAL. A blank or unrecognized result never falls back to status.

### Lifecycle Command (`/lbwc:vibe`)

`/lbwc:vibe` calls the detector before selecting a stage. It does not implement a second state machine. `planning_dir_exists`, `project_exists`, `phase_count`, `next_phase_state`, QA attention, UAT blockers, and milestone fields are the route authority.

**Goal:** Continue the earliest lifecycle obligation without skipping a prior remediation, verification, discussion, planning, or build state.

**Algorithm:**
1. Stop on detector error.
2. Honor active UAT remediation before ordinary phase work.
3. Honor active QA remediation before unrelated earlier planning or build work unless UAT cutover marks QA dormant.
4. Route `needs_verification` to QA or UAT according to its QA and UAT guard fields.
5. Route `needs_discussion`, `needs_plan_and_execute`, and `needs_execute` to their matching commands.
6. Treat `all_done` as complete only when no QA attention or UAT blocker retargets it.

**Matching logic:** detector output, remediation state, task contracts, generated-agent manifest entries, and terminal artifacts supersede manual plan-summary filename matching.

## Announcement

Always announce the auto-detected phase before proceeding. Format:

```
Auto-detected Phase {NN} ({slug}): {reason}
```

Reasons by command type:
- Planning: "next phase to plan"
- Build: "planned, not yet built"
- Implement: "needs plan + execute" or "planned, needs execute"
- QA: "built, not yet verified"

Then continue with the rest of the command as if the user had typed that phase number.

## Diagnostic Variables

`phase-detect.sh` emits the following diagnostic values with phase state:

- `planning_dir_exists`, `project_exists`, `phases_dir`, and `phase_count` describe the planning boundary.
- `next_phase`, `next_phase_slug`, `next_phase_state`, `next_phase_plans`, and `next_phase_summaries` identify the actionable phase.
- `qa_status`, `qa_reason`, `qa_round`, `first_qa_attention_phase`, `qa_attention_status`, and `qa_attention_reason` describe the earliest pre-UAT QA obligation.
- `qa_after_uat_dormant` blocks stale QA routing after UAT cutover.
- `uat_blocking_phase`, `uat_blocking_status`, `uat_blocking_file`, `uat_file`, and `uat_round_count` describe active human acceptance work.
- `milestone_uat_issues`, milestone fields, and shipped-milestone fields prevent archive or completion claims from skipping recovery.
- `config_effort`, `config_autonomy`, `config_auto_uat`, `config_verification_tier`, `config_context_compiler`, and `config_require_phase_discussion` report policy input. They do not override lifecycle state.

QA reason tokens include `missing_verification_artifact`, `verification_result_missing`, `verification_result_unrecognized`, `qa_gate_rerun_required`, `qa_gate_output_missing`, `working_tree_changed`, `verified_at_commit_mismatch`, `git_status_failed`, `git_log_failed`, `product_commit_unavailable`, `product_changed_after_verification`, and `freshness_baseline_unavailable`. Surface a known token in plain language. Preserve an unknown nonempty token verbatim.

**Required Phase 3 dependency:** the source misnamed-plan detector field and `scripts/normalize-plan-filenames.sh` are unavailable. A malformed or type-first plan name is a blocker. Do not rename it automatically or claim the detector repaired it.
