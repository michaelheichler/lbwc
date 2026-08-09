---
description: Per-phase task planning. Spawns lead to turn a scoped phase into an executable PLAN.md.
argument-hint: "<phase number or name>"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

`lead` plans one phase that already exists in `.lbwc-planning/ROADMAP.md` and `.lbwc-planning/REQUIREMENTS.md`. It does not do initial project scoping, that is `architect`'s job inside `/vibe`. If $ARGUMENTS names a phase with no `### Phase` entry in ROADMAP.md yet, stop and say so, do not spawn `lead` to invent one.

1. Resolve the target phase from $ARGUMENTS, or the first non-`complete` phase in ROADMAP.md's Progress table if $ARGUMENTS is empty.
2. Read that phase's `Goal`, `Deps`, `Reqs`, and `Success` line from ROADMAP.md, and the matching REQ entries from REQUIREMENTS.md. If a phase-scoped `RESEARCH.md` or `CONTEXT.md` already exists under `.lbwc-planning/phases/{NN}-{slug}/`, treat it as ground truth `lead` should build on, not re-derive.
3. If a genuine gray area remains after that read, meaning the phase's scope, an ambiguous dependency, or a missing acceptance criterion, ask up to 3 focused questions via AskUserQuestion. If nothing is genuinely unclear, skip straight to step 4, do not ask questions the ROADMAP and REQUIREMENTS entries already answer.
4. Build one `lead` brief from the phase goal, dependencies, requirement IDs, success criterion, and answers from step 3. Prepend `scripts/lib/deviq-digest.sh --phase <phase>`. Issue a solo `/plan` command contract for task `plan-{phase}` with the phase PLAN path as its only `--write-allowance`. Pass the same brief, contract path, task id, and allowance to the generator. Advance the contract to `dispatched`, then spawn `lead` per `@references/agent-spawn-protocol.md`.
5. `lead` writes `.lbwc-planning/phases/{NN}-{slug}/PLAN.md` from `templates/PLAN.md`: an objective, a `<tasks>` block with one `<task>` per unit of work (name, files, action, verify, done), a verification checklist, success criteria, and `must_haves` in the frontmatter (`truths`, `artifacts`, `key_links`) derived from the phase's REQ entries and success criterion, not invented independently of them.

## Review and handoff

6. When `lead` reports completion, run `bash scripts/plan-task-count.sh <phase-plan-path> .lbwc-planning/config.json` before accepting or summarizing its output. This validates the completed PLAN against the merged `max_tasks_per_plan` value. On a nonzero exit, do not spawn `lead-critic`. Relay the validator's exact error to `lead` for one revision, then rerun the validator. If the second validation fails, reject the planner output and report the exact error.
7. Only after validation succeeds, build the `lead-critic` brief from the validated PLAN path and phase inputs. Issue a read-only solo `/plan` command contract for task `review-plan-{phase}`. Pass the same brief, contract path, and task id to the generator. Advance the contract to `dispatched`, then spawn `lead-critic` per `@references/agent-spawn-protocol.md`.
8. Obey the `lead-critic` verdict.
   - On the first BLOCK, relay the findings to `lead`. Rerun task-count validation before resuming the critic. After a second BLOCK, report what remains and require PLAN revision.
   - On GREENLIGHT, list the validated tasks and route to `/build`.
   - Record each material plan choice with `deviq-record.py decision`. Record each final BLOCK finding with `deviq-record.py block` and keep its stable id for later resolution.
   - A blocked or unclear critic may use a solo `deviq` advisor. Issue a read-only solo `/plan` command contract named `deviq-plan-{phase}` from its exact brief. Advance it to `dispatched` before generation.
9. After the main session observes the final planning outcome, record exactly one telemetry event with `session-telemetry.py record --event command --outcome success|failure|blocked --phase <phase>`. Do not let `lead` or `lead-critic` write telemetry.
