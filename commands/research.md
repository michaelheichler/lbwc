---
category: advanced
disable-model-invocation: true
description: Run standalone research from Scout evidence and main-session synthesis.
argument-hint: <research-topic> [--parallel]
allowed-tools: Read, Write, Bash, Glob, Grep, WebFetch, WebSearch, AskUserQuestion, Agent, Skill, LSP, Workflow
---

# LBWC Research: $ARGUMENTS

## Shared interaction contract

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

Use native `Other` exactly as defined by that contract. For a freeform topic, path, or explanation, ask a plain-text question, wait for the response, and then resume bounded questions only when needed.

## Context

Working directory:

```text
!`pwd`
```

Plugin root:

```text
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store that value as `{plugin-root}`. Read `{plugin-root}/references/agent-spawn-protocol.md` before any Scout spawn.

Current project:

```text
!`cat .lbwc-planning/PROJECT.md 2>/dev/null || echo "No project found"`
```

## Workflow capability gate

Refresh the saved Claude capability catalog before any Scout contract or spawn:

```bash
bash "{plugin-root}/scripts/lbwc-model" refresh .lbwc-planning
```

This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`, the authority the execution-mode choice in Step 3 reads before offering or resolving `workflow`. A non-zero exit here does not stop research. It leaves `RESOLVED_BACKEND` at `in_process`, so research proceeds on whatever catalog already exists. Only a run that goes on to request or choose `workflow` can still be blocked, by step 0 of `workflow-spawn-protocol.md` and by `workflow-generator.sh`'s own live re-validation at generation time. Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.

## Guard

- If `$ARGUMENTS` is empty, STOP: `Usage: /lbwc:research <topic> [--parallel]`.
- Strip `--parallel`. If the remaining topic is empty, STOP with the same usage text.
- If the remaining topic is a bare integer, run `bash "{plugin-root}/scripts/resolve-todo-item.sh" <N> --session-snapshot --require-unfiltered --validate-live`. On `status: ok`, replace the topic with `command_text`, retain `ref`, and load its detail. On `status: error`, STOP with the helper `message`. If `state_path` is under `.lbwc-planning/milestones/`, STOP and require root `STATE.md` recovery before research.
- For a todo reference or a `(ref:HASH)` suffix, run `bash "{plugin-root}/scripts/todo-details.sh" get <hash>`. On `status: ok`, retain `detail.context` and `detail.files`. On `not_found` or `error`, run `bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning <hash>`, warn, and continue without detail. A ref-only request continues only when detail loading succeeded.

## Steps

1. **Parse:** Remove `--parallel`, resolve a numbered todo or optional `(ref:HASH)` suffix, and retain the topic, todo identity, detail context, and related files. Never include command flags or the ref tag in the Scout brief.
2. **Scope:** Use one Scout for a narrow question. Use two to four independent facets only for `--parallel` or genuinely separable research. State each facet before dispatch.
3. **Choose the execution backend:** Follow step 0 of `{plugin-root}/references/workflow-spawn-protocol.md`, with `<control-root>` bound to `.lbwc-planning`. Use these literal `AskUserQuestion` fields when that step's `ask` branch applies:

   - header: `Research execution`
   - question: `Where should this research run? Workflow run orchestrates each Scout through a committed background script. Native spawn keeps the current Scout spawn.`
   - options:
     - `Workflow run`: Research through committed workflow scripts in the background.
     - `Native spawn`: Keep the current native Scout spawn.
     - `Cancel research`: Do not research this topic now.

4. **Spawn Scout:** Before each Scout spawn, evaluate installed skills visible in system context. Derive technical domains from the topic, todo detail, project files, error text, and stack context. Select all materially helpful direct and narrowly adjacent skills, not just the single most obvious skill. State the outcome in the main-session response before spawning. The Scout prompt must begin with exactly one rendered `<skill_activation>` or `<skill_no_activation>` block.

   If skills were preselected, run:

   ```bash
   bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true
   ```

   Render `{plugin-root}/references/skill-activation-payload.md` with the ordered `skill_calls`, a task-specific `no_skill_reason` when none were selected, and the helper-emitted `follow_up_files_block` when present. Prepend the rendered bytes to the Scout prompt so its first line is the rendered skill outcome. After calling `Skill(...)`, read only the relevant follow-up files named by the skill or helper. Do not paste the template path, variables, or unresolved `@` include into the child prompt.

   Also evaluate available MCP tools in the system context before composing each brief. Note any relevant documentation, search, code-analysis, or domain-data MCP tools in that Scout's task context and instruct the Scout to prefer them for the matching lookup over generic WebFetch/WebSearch. Do not claim an MCP tool is available when it is not present.

   When `RESOLVED_BACKEND` is `in_process`, for each facet, issue a shell-owned, read-only command contract using `scripts/task-contract.sh issue` with command `research`, role `scout`, team `solo`, and the exact brief. Pass the identical brief, contract path, and task id to generic `scripts/agent-generator.sh scout`, then advance the contract to `dispatched`. The generator uses detected `lbwc-model` routing. Read its `Agent-call parameters:` block and final `SPAWN_READY` line. Spawn only with the emitted `model` and final name as `subagent_type` and `name`.

   When `RESOLVED_BACKEND` is `workflow`, follow `{plugin-root}/references/workflow-spawn-protocol.md` for one FACETS array holding each facet's exact question (one entry, the topic itself, for a non-`--parallel` run). Scout's default role permits `Write`, so a schema 3 contract for it requires either a granted write capability or an explicit `--read-only-role scout` declaration. No facet writes any file: issue every contract read-only.

   ```bash
   PROJECT_ROOT=$(pwd)
   CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
   FACETS=("{exact question or facet text, one entry per facet}")
   CONTRACT_PATHS=(); TASK_IDS=(); SCRIPT_PATHS=()
   for FACET in "${FACETS[@]}"; do
     SCOUT_BRIEF="research: ${FACET}"
     CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "research-{slug}" --command research --role scout --team solo --job "$SCOUT_BRIEF" --control-root "$CONTROL_ROOT" --requested-backend workflow --resolved-backend workflow --read-only-role scout) || exit 1
     TASK_ID=$(basename "$CONTRACT_PATH" .json)
     GENERATOR_OUTPUT=$(bash "{plugin-root}/scripts/agent-generator.sh" scout --job "$SCOUT_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --control-root "$CONTROL_ROOT" --execution-backend workflow) || exit 1
     NAME=$(printf '%s\n' "$GENERATOR_OUTPUT" | awk '/^SPAWN_READY/{print $2}')
     WORKFLOW_OUTPUT=$(bash "{plugin-root}/scripts/workflow-generator.sh" solo scout --job "$SCOUT_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --name "$NAME" --control-root "$CONTROL_ROOT") || exit 1
     bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
     CONTRACT_PATHS+=("$CONTRACT_PATH"); TASK_IDS+=("$TASK_ID")
     SCRIPT_PATHS+=("$(printf '%s\n' "$WORKFLOW_OUTPUT" | awk '/^  path:/{print $2}')")
   done
   ```

   Read each generation's own `Agent-call parameters:` and `SPAWN_READY <name>` line, captured above as `NAME`, and use only that printed name, never an invented one. Read each script's own `Workflow-call parameters:` block and `WORKFLOW_READY <task-id>` line. Call `Workflow` once per entry in `SCRIPT_PATHS`, passing only that entry's own `scriptPath`. Never pass `script`, and never inline or paraphrase a rendered file into the call. Launch every facet's run before waiting on any of them. Wait for every launched run's own terminal result before Step 5 (Synthesize). A `user_decision_required` result is the only path back to the user for that facet: ask one bounded `AskUserQuestion` about it. Any other terminal result carries that facet's evidence report, handled exactly like the `in_process` branch above.

   Use this literal prompt structure after the rendered skill block for every Scout:

   ```text
   <task_context>
   Research: {topic or facet}.
   Project context: {relevant project facts and constraints from PROJECT.md}.
   Extended todo context (only when detail loaded): {detail.context}.
   Related files (only when detail loaded): {detail.files, comma-separated}.
   MCP tools evaluated for this task: {relevant available MCP tools, or "none"}.
   MCP priority: {which lookup each relevant MCP tool should handle, or "Use the ordinary read-only route."}.
   </task_context>

   <research_scope>
   Answer only the assigned question: {exact question or facet}.
   Use cited source paths or URLs for every material claim. Separate observed facts,
   inferences, and unresolved contradictions. Do not expand into unrelated topics.
   </research_scope>

   <output_format>
   Return findings in your response text; do not create or edit research artifacts.
   Use this structure:
   ## {Topic}
   ### Key Findings
   - {claim} — Source: {path or URL}
   ### Confidence
   {high|medium|low}: {justification}
   ### Limitations
   - {uncertainty, contradiction, or missing evidence}
   ### Relevance
   {how the evidence answers the assigned question}
   </output_format>
   ```

   Each Scout is read-only. Require a report with sources, claims, confidence, limitations, and live-validation evidence when external facts matter. The live-validation evidence includes `command_shape`, `exit_status`, `redacted_evidence`, `expected_shape`, `confidence`, and `limitations_or_deferred_reason`. Public validation may use WebFetch. Authenticated or mutating validation is deferred unless a verified-safe read-only helper applies. Scouts return findings and evidence only, they do not create or edit research artifacts.
5. **Synthesize:** The main session compares all reports, resolves or exposes contradictions, and presents conclusions ranked by confidence. Do not treat an uncited Scout claim as established fact.
6. **Persist:** Ask `Save findings?` through AskUserQuestion with explicit bounded choices. On save, the main session writes the artifact. For an active phase use `.lbwc-planning/phases/{phase-dir}/RESEARCH.md`. Otherwise derive `RESEARCH_SLUG` from the topic, run `bash "{plugin-root}/scripts/research-session-state.sh" start .lbwc-planning "$RESEARCH_SLUG"`, and use its `research_file`. Preserve the YAML frontmatter between the opening and closing `---` markers, update `title` and `confidence`, write findings below it, then run `bash "{plugin-root}/scripts/research-session-state.sh" complete .lbwc-planning "$research_id"`. Do not delegate an artifact write.

## Failure and recovery

If contract issuance, generic generation, or spawning fails, report the helper error verbatim and do not substitute a static model, role-specific generator, or hand-written agent. If a Scout report is incomplete, research that facet inline or save only the supported findings. If persistence fails, leave session state incomplete and report the exact path and command failure.

If the workflow generator fails or a `Workflow` call is denied for a facet, leave that facet's contract `planned`, report the failure verbatim, and do not fall back to `in_process`. Research that facet inline instead, or save only the supported findings.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md. Use a findings banner, `✓` high confidence, `○` medium confidence, `⚠` low confidence, source links or paths, and no ANSI color codes.

## Next Up

```text
➜ Next Up
  /lbwc:vibe --plan {NN} - plan using research findings
  /lbwc:vibe --discuss {NN} - discuss the phase approach
  /lbwc:debug "description mentioning {topic}" - investigate an implementation symptom
  /lbwc:fix "description mentioning {topic}" - apply a focused fix when research identifies one
```
