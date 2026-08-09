---
description: Deterministic verification gate. Spawns qa to check PLAN.md must-haves against SUMMARY.md, then the main session persists VERIFICATION.md.
argument-hint: "<phase number or name>"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

`qa` is read-only: it cannot `Write`, `Edit`, or `NotebookEdit`. It derives a verdict, it does not fix anything itself. A `FAIL` routes back to `/build` or `/debug`, never to `qa` fixing it inline.

1. Resolve the target phase from $ARGUMENTS, or the first non-`complete` phase in ROADMAP.md's Progress table if $ARGUMENTS is empty. Read `.lbwc-planning/phases/{NN}-{slug}/PLAN.md` and `SUMMARY.md`. If `SUMMARY.md` is missing or its `status` isn't `complete`, stop and tell the user to run `/build <phase>` first.
2. Build the exact QA brief from the DevIQ digest, PLAN must_haves, SUMMARY `ac_results`, and deviations. Issue a read-only solo `/qa` command contract named `qa-{phase}`. Pass the same brief, contract path, and task id to the generator. Advance the contract to `dispatched`, then spawn one `qa` agent per `@references/agent-spawn-protocol.md`. Do not summarize or pre-judge deviations.
3. `qa` works goal-backward: for each must-have truth, artifact, and key_link, it independently checks the current repo state, not just SUMMARY.md's own claimed verdicts. Every deviation SUMMARY.md listed becomes its own checked criterion, a deviation is never silently accepted as fine.
4. `qa` returns structured `qa_verdict` evidence only: one row per must-have and artifact check, a `result` of `PASS`, `FAIL`, or `PARTIAL`, and the verification `tier` it ran at. It does not write files or invoke a Bash writer. The sole main-session orchestrator persists VERIFICATION.md only after validating the payload's result, counters, plan references, and deterministic table format. Only the main session runs:
   ```bash
   printf '%s' "$QA_VERDICT_JSON" | bash "$CLAUDE_PLUGIN_ROOT/scripts/write-verification.sh" "$PHASE_DIR/VERIFICATION.md"
   ```

## Outcomes and remediation rounds

5. Obey the `result` literally.
   - `PASS` routes to `/uat`.
   - `FAIL` or `PARTIAL` reports each failed check and opens a QA remediation round. Exit code 3 means the configured round cap was reached, so report it and stop.
   - Write `R{NN}-PLAN.md` from the remediation template with one classified task per failed must-have. Do not rerun QA hoping for another verdict or override a failure by judgment.
   - Record one `deviq-record.py block` per failed must-have and keep its stable id. A PASS records no decision or evidence entry.
   - If QA is blocked on an unclear check, build an exact advisor brief. Issue a read-only solo `/qa` command contract named `deviq-qa-{phase}`. Advance it to `dispatched` before generation.

6. When a round summary is terminal, run `scripts/remediation-round.sh stage <phase-dir> qa verify`. Build the new exact QA brief from `compile-verify-context.sh` plus the DevIQ digest. Issue a new read-only solo `/qa` command contract named `qa-{phase}-round-{NN}`, then generate and dispatch it as in step 2. The main session validates and persists the returned evidence. On `PASS`, mark the round done and route to `/uat`. On `FAIL` or `PARTIAL`, open the next round per step 5.
7. After the main session validates the QA payload and observes the resulting PASS, FAIL, or PARTIAL path, record one telemetry event with `session-telemetry.py record --event command --outcome success|partial|failure|blocked --phase <phase>`. The `qa` agent returns evidence only and never writes telemetry.
