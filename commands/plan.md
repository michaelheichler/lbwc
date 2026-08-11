---
name: lbwc:plan
category: core
description: Plan one existing phase through the full Vibe Plan protocol.
argument-hint: "<phase number or name>"
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, Agent
disable-model-invocation: true
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

## Context

The main session owns all planning state, user questions, contracts, generated-agent admission, artifact persistence, validation, telemetry, Git boundaries, and output. `lead`, `lead-critic`, `scout`, and any advisor work only through the generic spawn protocol and their issued contracts.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

Initialized, roadmap exists, phase exists. If every phase is planned, stop with `All phases planned. Specify phase: /lbwc:vibe --plan N`. If the phase directory is inside `.lbwc-planning/milestones/`, stop with `Cannot plan inside archived milestones.` Archived milestones are read-only.

## Steps

Follow `@references/vibe-mode-plan.md` in full. It is the authoritative Vibe Plan protocol for phase detection, effort selection, research, context compilation, generated-agent contracts, planning, filename normalization, validation, state updates, commit boundaries, and autonomy handling. Do not replace its required Phase 3 helper guards with local approximations.

## Review and handoff

Follow the reference's validation and presentation sequence. Accept planning output only after its required validation succeeds. Preserve every documented main-session decision handoff, worker boundary, and generated-agent authority rule.

## Failure and recovery

Follow the reference's failure behavior exactly. Stop and report contract, generator, helper, artifact, validation, or archive-guard failures. Where the reference explicitly permits planning to continue without research, log that warning and retain the documented scope. Do not silently choose a route, model, effort, or artifact path.

## Output Format

Use the Phase Banner and planning output defined in `@references/vibe-mode-plan.md`, including plans, titles, waves, task counts, and effort. Report any allowed research warning or blocking failure plainly.

## Next Up

When planning completes, use the reference's autonomy gate. If execution is approved or auto-chained, direct the user to `Next Up: /lbwc:build <phase>`. On a cautious stop or blocker, show only the documented next action.
