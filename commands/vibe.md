---
description: The main entry point. Detects the single next missing artifact in .lbwc-planning/ and either resumes in-flight work or advances the project one step.
argument-hint: "[task description] [--yolo]"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

This command never spawns directly except for the one-time scope step below. It detects state, then dispatches to the one command that owns that step. That is the whole job: find the single next missing artifact (phase-detection.md's principle, generalized), name it, confirm, dispatch.

Detect state in this exact order, stop at the first match:

1. Read `.lbwc-planning/.agent-manifest.json`. If any entry has a `pair_id` and not every member of that pair or trio has reached `used` or `expired`, that pair or trio is open. Report its members and their states, tell the user to run `/status` or let it finish, and stop. Do not start anything new while a pair or trio is open, `agent-spawn-guard.sh` will block it anyway.
2. Run `scripts/phase-detect.sh` as a query. If it reports `needs_milestone_rename=true`, the main session itself must run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/rename-default-milestone.sh" .lbwc-planning`. Do not delegate this write. Re-run phase detection, then restart at step 1.
3. If `.lbwc-planning/PROJECT.md` does not exist, tell the user to run `/init` and stop.
4. If ROADMAP has no phase sections, build a neutral scope brief and confirm it unless `--yolo` is present. Issue a solo `/vibe` command contract named `initial-scope`. Its exact allowances are `.lbwc-planning/ROADMAP.md`, `.lbwc-planning/PROJECT.md`, and `.lbwc-planning/REQUIREMENTS.md`. Pass the same brief, contract path, task id, and allowances to the generator. Advance the contract to `dispatched`, then spawn `architect` per `@references/agent-spawn-protocol.md`. Report what it wrote and stop.

## Phase routing

5. If $ARGUMENTS names a specific phase, confirm it has a `### Phase` entry in ROADMAP.md before proceeding. If it does not, say so and stop rather than guessing which phase was meant. Otherwise pick the first phase in ROADMAP.md's Progress table that is not `complete`. Within the resolved phase, check its artifacts under `.lbwc-planning/phases/{NN}-{slug}/` in this order, stop at the first one that applies:
   - `require_phase_discussion` is true in the merged config and the phase has no canonical `{NN}-CONTEXT.md`: run `/discuss <phase>`.
   - No `PLAN.md` yet: run `/plan <phase>`.
   - `PLAN.md` exists but `SUMMARY.md` is missing or its `status` isn't `complete`: run `/build <phase>`.
   - `SUMMARY.md` is `complete` but `VERIFICATION.md` is missing or its `result` isn't `PASS`: run `/qa <phase>`. The same applies inside an active remediation round: `stage=plan` or `stage=execute` with no complete `R{NN}-SUMMARY.md` routes to `/build <phase>`, `stage=verify` (round summary done, no passing `R{NN}-VERIFICATION.md` yet) routes to `/qa <phase>`.
   - `VERIFICATION.md` is `PASS` but `UAT.md` is missing or its `status` isn't `complete`: run `/uat <phase>`. An active UAT remediation round at `stage=plan` routes to `/build <phase>`, and a completed round UAT (`R{NN}-UAT.md`) still showing `issues_found` routes to `/uat <phase>` to open the next round.
   - All four are done: mark the phase `complete` in ROADMAP.md's Progress table and re-run this detection for the next phase.
6. If every phase is `complete`, report the roadmap finished. There is nothing to dispatch.

Before dispatching in step 4 or 5, state the phase, the artifact that is missing, and which command you are about to run. Ask for confirmation unless `--yolo` is in $ARGUMENTS. If $ARGUMENTS carries a task description rather than a flag, treat it as the brief for whichever command step 4 or 5 lands on. Do not let a described task skip the detection itself. It still has to land on the right artifact.
