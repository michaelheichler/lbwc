# Shared Subagent Contracts

This document is the canonical source for the team-shutdown contract, the non-team spawn shape, and the no-tool circuit breaker. `references/handoff-schemas.md` remains the authority for V2 message schemas. Do not duplicate those schemas here.

Keep this material local at call sites:

- Role-specific stop tails
- Debugger checkpointing
- The Architect shutdown exclusion
- Actual-team-mode gating and teardown sequencing
- Residual-cleanup ordering
- UAT artifact-path guidance
- Text pasted verbatim into child prompt payloads

## Team-Shutdown Contract

When a message contains `"type":"shutdown_request"` or `shutdown_request` in its text:

1. Finish any in-progress tool call.
2. Call the SendMessage tool with this JSON body. Fill in the current status and echo the request ID.

   ```json
   {"type": "shutdown_response", "approved": true, "request_id": "<id from shutdown_request>", "final_status": "complete"}
   ```

   Use `final_status` value `"complete"`, `"idle"`, or `"in_progress"` as appropriate.
3. Then stop. Do not start new work or take any further action.

**CRITICAL: Plain text acknowledgement is NOT sufficient.** You MUST call the SendMessage tool. The orchestrator cannot proceed with team shutdown until it receives a tool-call `shutdown_response` from every teammate.

The orchestrator must wait for each `shutdown_response` with `approved: true`, delivered through a teammate SendMessage tool call. Send at most three `shutdown_request` attempts per teammate, counting the initial request. If a teammate responds in plain text instead of calling SendMessage or rejects the request, re-send it immediately while attempts remain. If the teammate has not approved after the third attempt, log a warning and proceed to residual cleanup.

Call sites must copy this invariant byte-for-byte:

```text
Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.
```

## Non-Team Spawn Shape

Non-team spawn shape: omit `team_name`, `run_in_background`, `isolation`, and worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). The `name` field is optional label-only metadata. Never use it for routing, lifecycle state, or team semantics.

Call sites must copy this invariant byte-for-byte:

```text
Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.
```

For generated LBWC agents, issue the PLAN or command contract. Then run `scripts/agent-generator.sh <role> --job "{job}" --contract <path> --task-id <id>` (see `references/agent-spawn-protocol.md`) and capture the final `SPAWN_READY <name>` line. Advance the contract to `dispatched` before the spawn. Use that generated name as both `subagent_type` and `name` on the spawn call. Do not invent a role-based or namespaced value such as `lbwc:lbwc-dev`. The spawn guard accepts only the registered generated name with a valid dispatched contract.

## User Decision Escalation

Only the main session may ask the user a question or change decision state. A generated agent that reaches a user-owned choice must stop at that boundary and return exactly one JSON object to the main session. This shape matches the handoff in `commands/teach.md`:

```json
{
  "status": "user_decision_required",
  "decision": "storage_lifetime",
  "question": "Which storage lifetime should this feature use?",
  "choices": ["Keep 30 days", "Keep longer"],
  "context": "Existing records expire after 30 days, but the new audit requirement is ambiguous."
}
```

For an unbounded choice, return an empty `choices` array. Do not invent bounded options. The main session turns that report into one plain-text follow-up. For a bounded choice, return 2 to 4 choices so the main session can issue one single-select AskUserQuestion call. Claude Code provides native `Other`, so the handoff does not duplicate it.

An agent may explain evidence and recommend an option, but it has no authority to select one. It must not call AskUserQuestion, write a decision artifact, invoke a decision-state command, or run a trusted shell transition that advances the workflow. It must leave the workflow pending until the main session receives the user response. A dismissed dialog leaves the decision pending and blocks decision-dependent work.

## No-Tool Circuit Breaker

At every non-team subagent return site, inspect returned text before artifact validation, summary finalization, deterministic gates, or state advancement. If it says tools, shell/Bash, filesystem, edits, or API-session access are unavailable, treat that as a platform/tool provisioning failure. Stop without advancing state, report the failed role and stage or task, and do not retry the same prompt. Do not consume the normal retry budget. Repeating a no-tool spawn cannot fix tool provisioning and wastes tokens.

Call sites must copy this invariant byte-for-byte:

```text
No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
```

## Effort Routing Contract

- Model routing is enforced by the spawn guard and passed as the documented Agent tool `model` parameter.
- Reasoning effort is enforced at the hook/frontmatter layer. It is not a documented Agent tool parameter.
- Orchestrators must not claim reasoning effort was or was not applied based on tool schema visibility or agent self-report. Subagents cannot introspect their own reasoning effort.
- Evidence for actual routing lives in session and subagent transcripts.
- Workflow effort (`thorough`, `balanced`, `fast`, `turbo`) is a matrix key distinct from reasoning effort (`low` through `max`).

## Generated Agent Lifecycle

During execution, spawn only names returned by the role generator and registered in the manifest (`scripts/lib/agent-manifest.sh`). The spawn guard denies unregistered names.

Each generated name is single-use: the manifest's state machine (`registered` -> `running` -> `used`/`expired`) blocks re-spawning a name that already reached `running`. Generated definition files are ephemeral. `scripts/agent-lifecycle.sh sweep` cleans them after use or expiry.

Reused or missing generated names require a fresh generator invocation. Do not bypass the manifest with a role-based or namespaced `subagent_type`.

The generator flow is the source of the generated name, Agent `model`, frontmatter reasoning effort, and internal turn limit. Pass only documented Agent fields. Use the printed `model` and exact `SPAWN_READY` name on the spawn call. Do not pass effort, max-turn, or timeout fields that the Agent schema does not expose.
