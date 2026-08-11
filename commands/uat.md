---
name: lbwc:uat
category: core
description: Run the full main-session human UAT checkpoint protocol for a phase.
argument-hint: "<phase number or name>"
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
disable-model-invocation: true
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

## Context

UAT is a main-session human checkpoint loop. The main session alone owns UAT artifact and state writes, AskUserQuestion calls, remediation routing, telemetry, and output. Never spawn a worker, agent, advisor, or task for UAT.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

Resolve the target phase and follow the autonomy, authoritative verification, freshness, persisted PASS result, and deterministic QA-gate requirements in `@references/execute-uat.md`. Stop when a required helper is unavailable. Do not emulate a required Phase 3 helper or enter UAT from an unsupported remediation route.

## Steps

Follow `@references/execute-uat.md` in full in the main session. Generate only human-judgment checkpoints from the compiled UAT verification context, present one checkpoint at a time through native AskUserQuestion, persist each response before continuing, and use its required remediation and telemetry behavior.

## Failure and recovery

Follow the reference's failure behavior exactly. A missing, stale, non-PASS, or unsupported authoritative verification blocks UAT and routes to the required QA recovery. A missing Phase 3 helper is a blocker, not behavior to recreate. A remediation cap result stops the command. Never replace a required human response with an agent or automatic follow-up.

## Output Format

Use the checkpoint and completion output defined in `@references/execute-uat.md`. Report the UAT path, completed checkpoints, pass, skip, and issue counts, current remediation round when applicable, and the observed telemetry outcome.

## Next Up

On a clean completion, end with `Next Up: /lbwc:vibe`. On issues with a validated remediation plan, end with `Next Up: /lbwc:build <phase>`. On a resumed UAT, present only the next incomplete checkpoint and wait for the human.
