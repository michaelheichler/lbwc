# Workflow Probe Findings

Empirical results for the two unknowns gating the workflow-first execution backend plan. Produced by Task 1. No production file other than this one was touched to reach these findings. All probing happened in scratch directories outside this repository.

Host: Claude Code 2.1.233 (`claude --version`), same version the plan cites.

## Unknown A: does a `PreToolUse` matcher fire for the `Workflow` tool, and does exit 2 block it

**Method.** Built a throwaway project at `/private/tmp/.../scratchpad/workflow-probe-a`, outside this repository, with its own `.claude/settings.json` declaring a `PreToolUse` hook with `"matcher": "Workflow"`. Ran a nested, non-interactive `claude -p` session in that directory (`--dangerously-skip-permissions --debug hooks --output-format stream-json --verbose`) and asked it to call the `Workflow` tool once with a trivial inline `script`.

**Run 1, hook exits 0 and appends the hook's stdin to a file.** The hook fired and its stdin was the exact `PreToolUse` payload for the `Workflow` call:

```json
{"session_id":"c94983a6-...","cwd":"/private/tmp/.../workflow-probe-a","prompt_id":"2e62f96b-...","permission_mode":"bypassPermissions","hook_event_name":"PreToolUse","tool_name":"Workflow","tool_input":{"script":"export const meta = {\n  name: 'probe',\n  description: 'Trivial probe workflow',\n}\n\nawait log('probe')"},"tool_use_id":"toolu_01Bx1zcNFXu65Bvuowr68WHU"}
```

**Run 2, hook exits 2 with a stderr message.** The tool call was denied. The `tool_result` for the `Workflow` call carried `"is_error":true` and the hook's stderr text verbatim:

```json
{"type":"tool_result","content":"PreToolUse:Workflow hook error: [...]: PROBE DENY: workflow calls are blocked in this test\n","is_error":true,"tool_use_id":"toolu_01B2xMtD1R1owNojqrXhVSvg"}
```

The turn's usage record also carried a `permission_denials` entry naming the tool:

```json
"permission_denials":[{"tool_name":"Workflow","tool_use_id":"toolu_01B2xMtD1R1owNojqrXhVSvg", ...}]
```

The model's own summary confirmed the denial: "Workflow tool call blocked. Hook output: `PROBE DENY: workflow calls are blocked in this test`." No workflow ran. There is no `journal.jsonl` for this attempt, because the call never reached the runtime.

**Answer: YES.** A `PreToolUse` matcher on `"Workflow"` fires exactly like it does for any other tool, and exit code 2 blocks the call through the same `permission_denials` / `is_error` mechanism documented for other tools. The trust model's layer 1 guard (the `PreToolUse` guard on `Workflow`) is viable on this host version.

## Unknown B: does the subagent's own `PreToolUse` payload carry the generated name in `agent_type`

**Method.** Built a second throwaway project at `/private/tmp/.../scratchpad/workflow-probe-b`, outside this repository, containing:
- `.claude/agents/lbwc-probe-writer-quiet-amber-otter.md`, a real subagent definition file with `tools: "Write"` and a one-line instruction to write a fixed string to `probe-output.txt`.
- `.claude/settings.json` with two non-blocking `PreToolUse` hooks (`Workflow` and `Write`), each appending its own stdin to a log file.

Asked a nested `claude -p` session to call `Workflow` once with an inline script that runs a single `agent()` step against `agentType: "lbwc-probe-writer-quiet-amber-otter"`.

**First attempt failed for an unrelated reason.** The first script passed a single options object as the sole argument to `agent({...})`. The runtime serialized `label` and `prompt` as the literal string `"[object]"` in `wf_*.json`, and the subagent received the literal text `"[object]"` as its prompt. `agent-*.meta.json` recorded `"agentType":"workflow-subagent"`, the runtime's generic default, and 0 tool calls happened. This is a call-shape bug in the probe script, not a finding about `agent_type`, and it produced no Write call to inspect. The corrected shape is a positional prompt string plus an options object: `agent(promptString, { agentType, label, phase })`. That call succeeded, and the subagent ran and used its `Write` tool.

**Confirmed run.** With the corrected call shape, `probe-output.txt` was written with the expected content, and the `Write` hook's captured `PreToolUse` payload was:

```json
{"session_id":"3b1c73a6-...","cwd":"/private/tmp/.../workflow-probe-b","prompt_id":"9728da81-...","permission_mode":"bypassPermissions","agent_id":"ad8264fa168912605","agent_type":"lbwc-probe-writer-quiet-amber-otter","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/private/tmp/.../workflow-probe-b/probe-output.txt","content":"workflow probe payload two"},"tool_use_id":"toolu_016eKC2stFhJJH6fkvBAbDBx"}
```

`agent_type` is exactly the generated subagent definition name (`lbwc-probe-writer-quiet-amber-otter`), the same identifier LBWC would generate for a real role and register in the manifest, and the same field `hooks/test_scope_guard.py` reads through `_agent_identifier`.

**Answer: YES.** A workflow-spawned subagent's `Write` call carries the subagent's definition name in `agent_type`, matching the subagents documentation and matching what `skill_gate.py` and `test_scope_guard.py` already key on. No change to the role-resolution logic in those two guards is required for the workflow backend.

## Incidental observation, not one of the two gated unknowns

The public docs, and the plan's own note that this surface is "documented only in the tool schema," leave the `agent()` call shape unspecified. Empirically on this host, `agent()` takes a **positional prompt string first**, then an **options object** (`agentType`, `label`, `phase`, and by extension the other documented option-list keys). Passing a single combined object as the only argument silently misroutes: the whole object stringifies to `"[object]"` as the prompt, `agentType` is not honored, and the runtime falls back to a generic `"workflow-subagent"` agent type with zero tool calls. Task 5, which renders `templates/workflows/*.js.tpl`, needs this exact call shape. Record it there rather than re-deriving it.

## Unknown C: how a workflow script surfaces its final result to the calling session

Raised during Task 5 review: the first draft of the coding-shape templates emitted their final status through `await log(JSON.stringify(...))`, and it was unconfirmed whether `log()` output is the channel the calling session reads, or whether a top-level `return` is required instead.

**Method.** Built a third throwaway project at `/private/tmp/.../scratchpad/workflow-probe-c`, outside this repository, containing only a `PreToolUse` hook on `Workflow` that appends its stdin to a log file (non-blocking). Ran a nested `claude -p` session asking it to call `Workflow` once with an inline script that calls `await log("BEFORE_RETURN_MARKER")` and then executes a top-level `return { probeMarker: "RETURN_VALUE_MARKER_789", status: "complete" }`.

**Result.** `Workflow` runs asynchronously in the background and its own tool result only reports the launch (`taskId`, `runId`, `transcriptDir`, `scriptPath`), not the run's outcome. The run's own state file, `workflows/wf_<id>.json` under the session's project directory, recorded:

```json
{"result":{"probeMarker":"RETURN_VALUE_MARKER_789","status":"complete"},"logs":["BEFORE_RETURN_MARKER"],"status":"completed", ...}
```

**Answer.** `result` and `logs` are two separate fields. A top-level `return` populates `result`, and `log()` calls populate `logs` and nothing else. `log()` is not the return channel. This matches the plan's own wording ("the script stops and returns a `user_decision_required` payload," Design > The gate loop) and is why `solo.js.tpl`, `pair.js.tpl` and `trio.js.tpl` end every branch with `return`, never `log()`.

## Unknown D: does a workflow's `agent()` step fire `SubagentStart`/`SubagentStop`, matching what `agent-lifecycle.sh` reads

Raised during Task 10 review of `commands/build.md`'s Plan waves section. That section claimed a workflow-spawned member reaches `used` through the same `SubagentStart`/`SubagentStop` hook lifecycle a native member does, citing Unknown B as support. Unknown B probed a `PreToolUse` payload on a `Write` call, a different hook event with a different emitter, and said nothing about `SubagentStart` or `SubagentStop`. `scripts/agent-lifecycle.sh:touch_agent` only advances a manifest entry to `running` or `used` when `hook_event_name` equals exactly `SubagentStart` or `SubagentStop` (`agent-lifecycle.sh:157-166`), so the claim needed its own probe.

**Method.** Built a fourth throwaway project at `/private/tmp/.../scratchpad/workflow-probe-d`, outside this repository, containing:
- `.claude/agents/lbwc-probe-writer-quiet-amber-otter.md`, a real subagent definition file with `tools: Write` and a one-line instruction to write a fixed string to `probe-output.txt`.
- `.claude/settings.json` with two non-blocking hooks, `SubagentStart` and `SubagentStop` (no matcher, so both fire for any subagent), each appending its stdin plus a `---` separator to its own log file.

Ran a nested `claude -p` session asking it to call `Workflow` once with an inline script running a single `agent()` step, using the corrected positional-prompt call shape from Unknown B, against `agentType: "lbwc-probe-writer-quiet-amber-otter"`. Told it to wait for the run's own terminal result before ending its turn.

**Result.** `probe-output.txt` was written with the expected content. `subagent-start.log` recorded exactly one entry:

```json
{"session_id":"877d171a-...","agent_id":"a3d479ee285a414b2","agent_type":"lbwc-probe-writer-quiet-amber-otter","hook_event_name":"SubagentStart"}
```

`subagent-stop.log` recorded nine entries, all for the same `agent_id` and the same `agent_type":"lbwc-probe-writer-quiet-amber-otter"`, `hook_event_name":"SubagentStop"` in every one. The first carried `stop_hook_active:false`. The remaining eight carried `stop_hook_active:true` and an unchanged `last_assistant_message`, while `background_tasks[0].status` still read `"running"` in several of the later entries even though the file had already been written. The outer session was polling for the workflow's terminal result across several turns, and each turn re-emitted a `SubagentStop` payload for the same already-finished agent rather than emitting it once.

**Answer: YES, with a duplication caveat.** A workflow's `agent()` step does fire both `SubagentStart` and `SubagentStop`, and both payloads carry the registered subagent definition name in `agent_type`, exactly matching what `extract_known_agent_name` reads and what a native `Agent`-tool spawn produces. The `SubagentStart`/`SubagentStop` sentence in `commands/build.md` is now evidence-backed by this probe, not by Unknown B.

The duplication is a real platform quirk, not a probe artifact. `SubagentStop` can fire more than once for one already-completed agent while the enclosing session keeps polling a still-running workflow. It does not corrupt LBWC's admission state, because `stop_manifest_entry` (`agent-lifecycle.sh:129-137`) unconditionally sets `.state = "used"` on every firing rather than incrementing a counter or toggling based on prior state, so a repeat `SubagentStop` for the same name is a harmless no-op re-write. Nothing in this probe exercises a run with more than one distinct workflow-spawned name in flight at once, so cross-agent interleaving of the duplicate firings was not tested.

## Scratch artifacts

The probe directories are outside the repository under `/private/tmp/claude-501/-Users-michael-dev-skills-lbwc/341d9af2-9484-47a8-95af-cb8eab681e8c/scratchpad/` (`workflow-probe-a`, `workflow-probe-b`, `workflow-probe-c`, `workflow-probe-d`) and are not part of this repository's history.
