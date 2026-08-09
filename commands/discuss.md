---
description: Phase discussion. Builds a {NN}-CONTEXT.md decision record for one phase before /plan runs.
argument-hint: "[phase number or name] [--assumptions]"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

Pure orchestrator work. Do not spawn anyone: discussion is a conversation with the user, run inline per `@references/discussion-engine.md`. The output is `.lbwc-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md`, which `/plan` then treats as ground truth.

## Guards

1. No `.lbwc-planning/` directory: stop, tell the user to run `/init` first.
2. No `### Phase` sections in ROADMAP.md: stop, "No phases defined. Run `/vibe` first."

## Phase resolution

1. If `$ARGUMENTS` names a phase, target it. Confirm it has a `### Phase` entry in ROADMAP.md first. If not, say so and stop.
2. Otherwise target the first phase directory under `.lbwc-planning/phases/` lacking a canonical `[0-9]*-CONTEXT.md` file. If every phase already has one, stop: "All phases discussed. Name a phase to deepen an existing discussion."
3. If the target phase already has a CONTEXT.md, this is a continuation discussion. Say so in one line. The engine's Step 1.5 handles the merge semantics.

## Mode resolution

First match wins:

1. `--assumptions` in `$ARGUMENTS` → assumptions path
2. `discussion_mode` in `.lbwc-planning/config.json` is `"assumptions"` → assumptions path
3. `discussion_mode` is `"auto"` (or unset) and `.lbwc-planning/codebase/META.md` exists → assumptions path
4. Otherwise → questions path

## Execute

Read `@references/discussion-engine.md` and follow it for the target phase: calibrate, detect continuation, orient on phase-specific gray areas, explore each selected area with recommendation-led questions, then capture into `{NN}-CONTEXT.md` from `templates/CONTEXT.md`.

## After the discussion

Report which gray areas were decided, which were left open at your discretion, and anything captured under Deferred Ideas. Tell the user to run `/plan <phase>` next. If the discussion resolved a decision that was previously recorded as an open DevIQ block for this phase, note the block id so the user can resolve it via `/build`, `/qa`, or `/uat` when the work lands.
