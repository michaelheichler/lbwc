# Workflow API Contract

This file pins the Workflow tool's script API as LBWC relies on it. The public Claude Code documentation does not specify this surface. It defers to the Agent SDK reference, and that reference has no Workflow section. `parallel()`, `phase()`, `log()`, `workflow()`, the `budget` global, and the full `agent()` option list are documented only in the Workflow tool's own schema, the definition Claude Code loads into a session when the tool is available, not in any published guide.

Treat every symbol below as pinned from that schema and from empirical probing on this host, not from public documentation. The probe ran against Claude Code 2.1.233, recorded in `references/workflow-probe-findings.md`. If the schema changes on a future host, this file is the one place that needs re-verification. `scripts/tests/workflow-generator-core.sh` is the contract test that would catch a drift.

## Script shape

A saved workflow script is a `meta` block followed by a plain JavaScript body with top-level `await`.

```js
export const meta = { name: "...", description: "...", phases: ["..."] };

await phase("...");
const result = await agent("...", { agentType: "...", ... });

return { status: "complete", ... };
```

`meta` is a plain object literal, never a function call or a template-derived value. LBWC's renderer builds it with `jq -nc` and writes it as line 1, so its purity is verified by feeding that line back through `jq -e .`.

A top-level `return` ends the script and populates the run's `result` field. This is legal in a workflow script and illegal in an ES module, confirmed empirically in `references/workflow-probe-findings.md` (Unknown C). The run's own state file separates `result` (from the top-level `return`) from `logs` (from `log()` calls), and `log()` output never reaches `result`. LBWC's committed templates always end every branch with `return`, never `log()`, because of this.

## `agent()`

Verified call shape: a positional prompt string first, then an options object.

```js
await agent(promptString, { agentType, label, phase, schema, model, effort });
```

Passing a single combined object as the only argument silently misroutes. `references/workflow-probe-findings.md` records the failure mode empirically: the whole object stringifies to `"[object]"` as the prompt, `agentType` is not honored, and the runtime falls back to a generic `workflow-subagent` agent type with zero tool calls. Always use the positional-prompt shape.

The option keys LBWC's committed templates use:

- `agentType`. The generated `lbwc-<role>-<adj>-<adj>-<noun>` definition name, the same identity a native or tmux teammate carries. The spawned subagent's own tool calls carry this in `agent_type`, confirmed on this host in `references/workflow-probe-findings.md` (Unknown B).
- `label`. A short human-readable tag for the run's transcript, not a routing input.
- `phase`. The enclosing `phase()` title this call belongs to.
- `schema`. A JSON Schema object. LBWC uses the typed payloads already defined in `references/handoff-schemas.md` (`execution_update`, `tests_ready`, `qa_verdict`, the critic's binary verdict) so the agent's structured return matches LBWC's existing envelopes.
- `model` and `effort`. The exact values `agent-generator.sh` resolved and wrote into that agent's own definition file at generation time. The workflow script never re-derives or overrides them, so the routing resolver stays the only model authority, other than the `CLAUDE_CODE_SUBAGENT_MODEL` override documented below.

Documented only in the tool schema, not exercised by any committed LBWC template today: `parallel()`, `log()`, `workflow()`, and the `budget` global. A future template that wants one of these must re-verify its contract the same way this file was produced, by probing the live schema and citing the result here, not by assuming training-data knowledge of the Workflow tool.

## Platform facts a template author must not violate

- Spawned subagents always run in `acceptEdits` mode, inheriting the session tool allowlist, regardless of session permission mode.
- A subagent definition resolves `disallowedTools` first, then resolves `tools` against what remains. The definition file governs the final tool set, not the workflow script.
- The workflow script has no filesystem or shell access itself, and no module loading. `import()` fails before the run starts.
- `CLAUDE_CODE_SUBAGENT_MODEL` overrides both the session model and any per-stage model the script routes through `agent()`'s `model` option. This contradicts LBWC's rule that the routing resolver is the only model authority. `scripts/claude-capabilities.sh` detects it and marks the workflow backend unavailable with a reason naming it. `references/workflow-spawn-protocol.md` step 1 requires that check before a snapshot ever freezes to `workflow`. **Known gap.** The variable is a Claude Code session setting, not a workflow-only one, so it can equally override a resolver-selected model on the `in_process` or `tmux` backends. `scripts/claude-capabilities.sh` only detects and fails closed on it for the `workflow` probe today. The `in_process` and `tmux` paths carry no equivalent check. Closing that gap means a routing-level check in `scripts/lbwc-routing.sh` or `scripts/runtime-snapshot.sh`, which is out of this file's scope and untouched by this change.
- `scripts/claude-capabilities.sh`'s `disableWorkflows` probe reads only the resolved user-level Claude Code settings file (`$CLAUDE_CONFIG_DIR/settings.json`, or `~/.claude/settings.json`). **Known gap.** It does not read project-level `.claude/settings.json` or `.claude/settings.local.json`, nor enterprise managed settings, any of which can also set `disableWorkflows`. Where one of those disables workflows and the user-level file does not, the probe reports `available: true` and `commands/team.md` still offers `Workflow run`, and the run then fails only when the host itself refuses the `Workflow` tool call. Closing this gap means merging all four settings scopes in probe order, which is a larger, separately scoped change.
- `CLAUDE_CODE_DISABLE_WORKFLOWS`'s exact truthy spelling is not pinned by any citation in `references/workflow-probe-findings.md`. Only `=1` appears in the plan's own platform-facts research, itself sourced from a documentation fan-out rather than a live probe on this host. Because this gate must fail closed, `scripts/claude-capabilities.sh` treats any non-empty value as disabling, not only the literal `1`. Re-verify the host's actual parsing rule if it is ever cited from a primary source, and narrow this check to match.
- Up to 16 concurrent agents, fewer with fewer CPUs, and 1000 agents total per run. LBWC's `solo`, `pair`, and `trio` shapes stay far below either bound.
- Resume works only within the same session. Replay follows start order. Cached results stop at the first agent that did not finish, and every agent started after it reruns even if it had completed.

## Hooks inside a run

- `PreToolUse` fires for a workflow-spawned subagent's own tool calls exactly as it does for a native or tmux teammate, and can block with exit code 2.
- `SubagentStart` cannot block a workflow-spawned agent. Exit 2 only shows stderr to the user, and the subagent still starts. This is why `scripts/workflow-spawn-guard.sh` sits on the `Workflow` tool call itself, not on each `agent()` step, and why per-agent revalidation inside a running workflow stays detective rather than preventive.
- Documented `PreToolUse` identity fields are `agent_id` and `agent_type` only. LBWC's existing `test_scope_guard.py` and `skill_gate.py` already key on `agent_type`, so they need no change for this backend.
