---
name: lbwc:debug
category: supporting
disable-model-invocation: true
description: Investigate a bug using the Debugger agent's scientific method protocol.
argument-hint: "bug description | todo number | --resume | --session ID"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, Skill, LSP, AskUserQuestion
---

# LBWC Debug: $ARGUMENTS

## Context

Working directory:

```
!`pwd`
```

Plugin root:

```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Recent commits:

```text
!`git log --oneline -10 2>/dev/null || echo "No git history"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

@${CLAUDE_PLUGIN_ROOT}/references/agent-spawn-protocol.md
@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

Every Debugger and QA spawn follows `{plugin-root}/references/agent-spawn-protocol.md`. Issue each contract with `scripts/task-contract.sh`, generate it with generic `scripts/agent-generator.sh`, then advance the contract to `dispatched`. The main session owns planning files, Git, verification, and user questions.

## Guard

- Not initialized (no .lbwc-planning/ dir): STOP "Run /lbwc:init first."
- No $ARGUMENTS and no `--resume` flag and no `--session` flag: STOP "Usage: `/lbwc:debug \"description of the bug or error message\" [--competing|--parallel|--serial]` | `/lbwc:debug <todo-number> [--competing|--parallel|--serial]` | `/lbwc:debug --resume` | `/lbwc:debug --session <id>`"

## Resolve selected todo number

<selected_todo_start_helper>
Selected-todo mode applies when `$ARGUMENTS`, after removing only supported routing flags (`--competing`, `--parallel`, `--serial`), contains exactly one numeric token and no other freeform text. Preserve those supported routing flags and pass them through to the helper. Any other text stays on the manual/freeform debug path.

When selected-todo mode applies, call the deterministic helper exactly once:

```bash
bash "{plugin-root}/scripts/debug-start-selected-todo.sh" .lbwc-planning <N> [--competing|--parallel|--serial]
```

Treat the helper stdout as `helper_output`, the single source of truth for selected-todo startup. The helper owns numbered selection resolution, optional detail loading, completed-session stale-state repair, debug session creation, `## Source Todo` persistence, and selected-todo pickup from writable root `STATE.md`. Do not reimplement those state transitions in command markdown.

Helper output schema is status-variant. Always parse `.status` before reading branch-specific fields.

- Common discriminator: `status` is `ok`, `already_complete`, or `error`.
- Success-like payloads (`ok` and `already_complete`) include the full selected-todo payload: `mode`, `todo_selected`, `bug_desc`, `routing_flags`, `selected`, `ref`, `detail_status`, `detail`, `detail_has_signal`, `accepted_exception_markers`, `detail_warning`, `session`, `pickup`, and `message` when applicable. `pickup` contains `status`, `warning`, `auto_note`, and `result`.
- No-session errors may carry only `status`, `code`, and `message`, plus any resolver-owned error fields. Do not assume `mode`, `bug_desc`, `routing_flags`, `selected`, `ref`, `detail_*`, `accepted_exception_markers`, `session`, or `pickup` exists on this branch.
- Session-bearing errors carry `status`, `code`, `message`, `mode`, `todo_selected`, `session`, and usually `pickup` so the command can expose partial lifecycle state. Do not require success-only selected/detail fields on this branch.

Parse `.status` first and branch explicitly:

- If `.status == "ok"`: store `SELECTED_TODO_MODE=true`, store `SELECTED_TODO_START_JSON=helper_output`, replace `$ARGUMENTS` with `.bug_desc`, set `session_id=.session.id`, `session_file=.session.file`, and `session_status=.session.status`, then continue the workflow using helper-provided fields.
- If `.status == "already_complete"`: show the completed session id/file/status, the helper message, and any pickup warning. STOP. Do not create, resume, or investigate another session.
- If `.status == "error"` and `.session` exists: show that a debug session already exists or was created before the pickup/session error, include `.session.id`, `.session.file`, `.session.status`, surface `.message`, and tell the user to inspect or resume that session instead of implying no session exists. STOP.
- For any other error: STOP with `.message // "Selected todo startup failed. Rerun /lbwc:list-todos and try again."`.

All selected-todo consumers below must read `SELECTED_TODO_START_JSON`: parse/effort uses `.bug_desc` and `.ref`, sparse enrichment uses `.detail_has_signal`, `.detail.context`, and `.detail.files`, accepted-exception prompt text uses `.accepted_exception_markers`, pickup UX uses `.pickup.*`. The command must not preserve selected-todo JSON variables, preserve raw detail-helper JSON for the selected path, or pipe selected-todo JSON between resolver/detail/session/pickup helpers.
</selected_todo_start_helper>

## Debug Session Resolution

<debug_session_routing>
Resolve or create the debug session before any investigation. Order of precedence:

1. **Explicit `--session <id>`:** Extract `SESSION_ID`, the token immediately following `--session` in $ARGUMENTS. If `--session` is present but no id follows it, STOP: `"--session requires a session id."` Resume the named session:

   ```bash

  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" resume .lbwc-planning "$SESSION_ID")"

   ```
   If the session file is missing, STOP with error.

2. **`--resume` flag (no explicit session):** Resume the active session or latest unresolved.
   ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" get-or-latest .lbwc-planning)"
   ```

  If `active_session=none`, STOP "No active debug session to resume. Use `/lbwc:debug --session <id>` to open a specific session, or start one with `/lbwc:debug \"description of the bug or error message\"` or `/lbwc:debug <todo-number>`."
  If `active_session=fallback`, inform user which session was auto-selected (no `.active-session` pointer was set, so the latest unresolved session was chosen automatically).
  For metadata-read helper calls (`resume`, `get-or-latest`), use `active_session`, `session_id`, `session_file`, and `session_status` after `eval`. Use `session_status` for lifecycle checks after `eval`, do not rely on a bare `status` variable.

1. **New session (no --resume, no --session):** If `SELECTED_TODO_MODE=true`, the selected-todo helper has already created or identified the session and has already handled Source Todo persistence plus root `STATE.md` pickup. Reuse `session_id`, `session_file`, and `session_status` from `SELECTED_TODO_START_JSON`, do not create another session and do not run selected-todo pickup in markdown.

   For manual/freeform starts only, create a fresh session from $ARGUMENTS. Strip known flags (`--competing`, `--parallel`, `--serial`) and any `(ref:HASH)` suffix from $ARGUMENTS before computing the slug, these are routing/ref metadata, not part of the bug description.

   ```bash
   BUG_DESC=$(printf '%s' "$ARGUMENTS" | sed -E 's/[[:space:]]*\(ref:[^)]+\)//g' | sed -E 's/(^|[[:space:]])--(competing|parallel|serial)([[:space:]]|$)/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -s '[:space:]' ' ')
   SLUG=$(printf '%s' "$BUG_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 50)
   MANUAL_REF="${REF_HASH:-none}"
   MANUAL_DETAIL_CONTEXT=""
   MANUAL_DETAIL_FILES='[]'
   if [ "${DETAIL_STATUS:-none}" = "ok" ] && [ -n "${DETAIL_RESULT_JSON:-}" ]; then
     MANUAL_DETAIL_CONTEXT=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -r '.detail.context // empty' 2>/dev/null || echo "")
     MANUAL_DETAIL_FILES=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -c '(.detail.files // []) | if type == "array" then . else [] end' 2>/dev/null || printf '[]')
   fi
   eval "$(jq -cn \
     --arg mode "source-todo" \
     --arg text "$BUG_DESC" \
     --arg raw_line "none" \
     --arg ref "$MANUAL_REF" \
     --arg detail_status "${DETAIL_STATUS:-none}" \
     --argjson related_files "$MANUAL_DETAIL_FILES" \
     --arg detail_context "$MANUAL_DETAIL_CONTEXT" \
     '{mode:$mode, text:$text, raw_line:$raw_line, ref:$ref, detail_status:$detail_status, related_files:$related_files, detail_context:$detail_context}' \
     | bash "{plugin-root}/scripts/debug-session-state.sh" start-with-source-todo .lbwc-planning "$SLUG")"
   ```

   Keep manual/freeform debug starts on the existing `start-with-source-todo` path. The selected helper owns deterministic selected-todo state mutation and returns pickup presentation fields under `.pickup`.

Store the resolved `session_id` and `session_file` for use in Steps below.

If resuming a session with `session_status=qa_pending` or `session_status=fix_applied`: skip investigation, jump directly to `<debug_inline_qa>` below to run QA inline.
If resuming a session with `session_status=qa_failed`: load failure context:

  ```bash
  FAILURE_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa 2>/dev/null || echo "")
  ```

  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed QA checks and findings. Use this format in the task prompt: `Previous QA failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `session_status=uat_pending`: skip investigation, jump directly to `<debug_inline_uat>` below to run UAT inline.
If resuming a session with `session_status=uat_failed`: load failure context:

  ```bash
  FAILURE_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" uat 2>/dev/null || echo "")
  ```

  Update status to `investigating` via `write-debug-session.sh` (mode=status), then continue investigation from Step 3. When composing the debugger task prompt in Step 4, prepend the compiled `FAILURE_CONTEXT` to the bug report so the debugger has the specific failed UAT issues and findings. Use this format in the task prompt: `Previous UAT failed. Failure context:\n{FAILURE_CONTEXT}\n\nOriginal bug report: {description}`.
If resuming a session with `session_status=complete`: STOP "This debug session is already complete. Use `/lbwc:debug --session <id>` to inspect another session, or start a new one with `/lbwc:debug \"description of the bug or error message\"` or `/lbwc:debug <todo-number>`."
</debug_session_routing>

## Steps

1. **Parse + effort:** Strip any known flags (`--competing`, `--parallel`, `--serial`) from $ARGUMENTS and store them separately for Step 2 routing. If `SELECTED_TODO_START_JSON` exists from the selected helper, reuse `.bug_desc` as the bug description, `.ref` as the selected ref, `.detail_status`, `.detail.context`, `.detail.files`, `.detail_has_signal`, `.accepted_exception_markers`, and `.routing_flags`, do not call `todo-details.sh` a second time and do not inspect raw selected-todo JSON to rediscover these fields. Otherwise, if the remaining $ARGUMENTS contains a `(ref:HASH)` suffix (8 hex characters), extract the hash as `REF_HASH` and strip the ref tag. Store remaining text (minus flags and ref) as the bug description. If a ref was found, load extended detail:

   ```bash
   bash "{plugin-root}/scripts/todo-details.sh" get {hash}
   ```

  Parse the JSON output. If `status` is `"ok"`, store `DETAIL_STATUS=ok`, store the exact helper stdout as `DETAIL_RESULT_JSON`, and store `detail.context` plus `detail.files` for use in Step 4. If `status` is `"not_found"` or `"error"`, clear `DETAIL_RESULT_JSON`, record the matching `DETAIL_STATUS` value, and run:

   ```bash
   bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning {hash}
   ```

   In all cases, continue without detail.
  If no ref suffix, $ARGUMENTS minus flags = bug description, `DETAIL_STATUS=none`, and `DETAIL_RESULT_JSON=""`.
  **Post-parse validation:** If the bug description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed, the detail provides the investigation context. If no ref was found, or the ref detail failed to load, STOP: "Usage: `/lbwc:debug \"description of the bug or error message\" [--competing|--parallel|--serial]` | `/lbwc:debug <todo-number> [--competing|--parallel|--serial]` | `/lbwc:debug --resume` | `/lbwc:debug --session <id>`".
   Map effort: thorough=high, balanced/fast=medium, turbo=low.
   Keep effort profile as `EFFORT_PROFILE` (thorough|balanced|fast|turbo).
   Read `{plugin-root}/references/effort-profile-{profile}.md`.

   **Bounded sparse-context enrichment (detail-first, then tiny helper):** Treat `DETAIL_STATUS=ok` as “lookup succeeded,” not automatically as “detail is useful.” For selected-todo mode, consume helper-provided `detail_has_signal` directly. For manual/freeform ref mode, compute the same value from `DETAIL_RESULT_JSON`: true only when loaded detail has actual signal, a non-empty `detail.context` or at least one related file. Otherwise, keep treating the item as sparse and run one bounded enrichment pass before final skill preselection:

   ```bash
   DETAIL_HAS_SIGNAL=false
   if [ "${SELECTED_TODO_MODE:-false}" = "true" ]; then
     DETAIL_HAS_SIGNAL=$(printf '%s' "$SELECTED_TODO_START_JSON" | jq -r '.detail_has_signal // false' 2>/dev/null || printf 'false')
   elif [ "${DETAIL_STATUS:-none}" = "ok" ] && [ -n "${DETAIL_RESULT_JSON:-}" ]; then
    DETAIL_CONTEXT_FOR_ENRICHMENT=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -r '.detail.context // ""' 2>/dev/null || printf '')
    DETAIL_FILE_COUNT_FOR_ENRICHMENT=$(printf '%s' "$DETAIL_RESULT_JSON" | jq -r '(.detail.files // []) | if type == "array" then length else 0 end' 2>/dev/null || printf '0')
     if [ -n "$DETAIL_CONTEXT_FOR_ENRICHMENT" ] || [ "${DETAIL_FILE_COUNT_FOR_ENRICHMENT:-0}" -gt 0 ]; then
       DETAIL_HAS_SIGNAL=true
     fi
   fi

   SPARSE_SKILL_ENRICHMENT_STATUS="skipped"
   SPARSE_SKILL_ENRICHMENT_SUMMARY=""
   SPARSE_SKILL_ENRICHMENT_FILES=""
   SPARSE_SKILL_ENRICHMENT_MARKERS=""
   if [ "$DETAIL_HAS_SIGNAL" != "true" ]; then
     SPARSE_SKILL_ENRICHMENT_JSON=$(printf '%s' "$BUG_DESC" | bash "{plugin-root}/scripts/debug-skill-enrichment.sh")
     SPARSE_SKILL_ENRICHMENT_STATUS=$(printf '%s' "$SPARSE_SKILL_ENRICHMENT_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")
     if [ "$SPARSE_SKILL_ENRICHMENT_STATUS" = "ok" ]; then
       SPARSE_SKILL_ENRICHMENT_SUMMARY=$(printf '%s' "$SPARSE_SKILL_ENRICHMENT_JSON" | jq -r '.summary // empty' 2>/dev/null || echo "")
       SPARSE_SKILL_ENRICHMENT_FILES=$(printf '%s' "$SPARSE_SKILL_ENRICHMENT_JSON" | jq -r '(.matched_files // []) | join(", ")' 2>/dev/null || echo "")
       SPARSE_SKILL_ENRICHMENT_MARKERS=$(printf '%s' "$SPARSE_SKILL_ENRICHMENT_JSON" | jq -r '(.markers // []) | join(", ")' 2>/dev/null || echo "")
     fi
   fi
   ```

   The helper is allowed to return `no_signal` or `no_match`, treat those as bounded no-ops and continue. Prefer existing selected-todo metadata first, then this helper's 1-3 likely files / framework markers, then the raw description. Do not turn this into a broad repo scan.

  <accepted_exception_debug_semantics>
  Accepted exception/backlog markers are historical phase/round waivers and backlog pointers, not proof that the underlying issue is fixed. Known-issue sources include `[KNOWN-ISSUE]`, `Disposition: accepted-process-exception`, and `known_issue_signature.disposition`. UAT-deviation sources include `[UAT-DEVIATION]`, `source: "uat-deviation"`, an `uat_deviation` object, and the phrase `Accepted UAT summary deviation`. When the user selects the item with `/lbwc:debug <todo-number>`, treat it as an active remediation request. Do not set or accept `already_fixed` solely because source metadata says accepted, non-blocking, UAT deviation, process exception, or backlog. `already_fixed` requires fresh current evidence that the underlying issue no longer reproduces or the current branch already contains a real fix. If still actionable, use `resolution_observation=needs_change`, if impossible or unsafe without more input, use `resolution_observation=inconclusive`, Step 5 will normalize that field and map the no-commit session to `INVESTIGATION_OUTCOME=no_fix_yet`.

  When selected helper output includes `accepted_exception_markers`, include one compact source-metadata sentence near this block using those labels. For manual/freeform detail, include the same kind of sentence when `DETAIL_RESULT_JSON` contains visible accepted-exception markers. Do not paste full JSON into spawned prompts.
  </accepted_exception_debug_semantics>

1. **Classify ambiguity:** 2+ signals = ambiguous.
  Keywords: "intermittent/sometimes/random/unclear/inconsistent/flaky/sporadic/nondeterministic",
  multiple root cause areas, generic/missing error, previous reverted fixes in
  git log. Overrides: `--competing`/`--parallel` = always ambiguous,
  `--serial` = never.

2. **Routing decision + delegation marker:** Classify ambiguity as above, but do not create a source team or use team preference routing. Set `INVESTIGATION_MODE=parallel` when the ambiguity classifier is true, and `INVESTIGATION_MODE=serial` otherwise. The `--serial` flag therefore always selects the single-debugger path; `--competing`/`--parallel` or 2+ ambiguity signals select three independent solo debuggers. Before spawning, activate the delegation guard:

   ```bash
   bash "{plugin-root}/scripts/delegated-workflow.sh" set debug "$EFFORT_PROFILE"
   HEAD_BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "")
   ```

3. **Spawn investigation:** Follow `{plugin-root}/references/agent-spawn-protocol.md`. Every debugger in this step is read-only and receives no write allowance. Preserve rejected-hypothesis evidence, contributing factors, and de-duplicated pre-existing issues in the returned reports. `--serial` and the non-ambiguous default keep today's single sequential debugger path, investigating the strongest initial hypothesis unless new evidence requires another.

   For the ambiguous path (`INVESTIGATION_MODE=parallel`), create three independent solo command contracts with distinct hypothesis-focused task briefs. Issue the contracts three times, once for each hypothesis, and generate and dispatch each contract before any live spawn:

   ```bash
   PROJECT_ROOT=$(pwd)
   BUG_DESC="{bug description from Step 1}"
   RESEARCH_CONTEXT=$(bash "{plugin-root}/scripts/compile-research-context.sh" .lbwc-planning "$BUG_DESC" 2>/dev/null || echo "")
   CAUSE_BRIEF="Hypothesis: cause. Investigate the most likely root cause of $BUG_DESC; gather evidence for and against this cause. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context."
   AREA_BRIEF="Hypothesis: codebase area. Investigate which codebase area, component, boundary, or execution path owns $BUG_DESC; gather evidence for and against this area. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context."
   EVIDENCE_BRIEF="Hypothesis: confirming evidence. Investigate which reproduction, log, test, trace, or other evidence would confirm or reject the competing explanations for $BUG_DESC; gather that evidence. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context."

   CAUSE_CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-investigate-{task-slug}-cause" --command debug --role debugger --team solo --job "$CAUSE_BRIEF") || exit 1
   CAUSE_TASK_ID=$(basename "$CAUSE_CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" debugger --job "$CAUSE_BRIEF" --contract "$CAUSE_CONTRACT_PATH" --task-id "$CAUSE_TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$CAUSE_TASK_ID" dispatched >/dev/null || exit 1

   AREA_CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-investigate-{task-slug}-area" --command debug --role debugger --team solo --job "$AREA_BRIEF") || exit 1
   AREA_TASK_ID=$(basename "$AREA_CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" debugger --job "$AREA_BRIEF" --contract "$AREA_CONTRACT_PATH" --task-id "$AREA_TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$AREA_TASK_ID" dispatched >/dev/null || exit 1

   EVIDENCE_CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-investigate-{task-slug}-evidence" --command debug --role debugger --team solo --job "$EVIDENCE_BRIEF") || exit 1
   EVIDENCE_TASK_ID=$(basename "$EVIDENCE_CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" debugger --job "$EVIDENCE_BRIEF" --contract "$EVIDENCE_CONTRACT_PATH" --task-id "$EVIDENCE_TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$EVIDENCE_TASK_ID" dispatched >/dev/null || exit 1
   ```

   Keep `RESEARCH_CONTEXT` only when non-empty. Include it, the accepted-exception semantics, compact source metadata, todo detail, or sparse enrichment only when present. Each report must include the no-tool circuit breaker result for unrelated failures.

   Read every emitted `Agent-call parameters:` block and `SPAWN_READY` line. In one assistant message/turn, spawn all three named contracts with three parallel Agent-call blocks, one per generated debugger. Use only each printed `subagent_type`, `name`, and `model`; do not add any other Agent-call fields. These three debuggers investigate simultaneously. Wait for all three `debugger_report`s before choosing an implementation or issuing an implementation contract.

   Before composing each parallel Debugger task description, evaluate installed skills visible in system context in two passes. Derive technical domains from the assigned hypothesis, issue metadata, logs, errors, files, and bounded enrichment. Prefer these signals to generic stack guesses. Select all materially helpful direct skills and narrowly adjacent support skills. The task description for each debugger MUST begin with exactly one explicit `<skill_activation>` or `<skill_no_activation>` block, then name its assigned hypothesis. State the skill outcome in each response and cite bounded enrichment when it influenced the choice. After calling `Skill(...)`, read only relevant follow-up files named by the skill. Do not scan entire skill folders or read unrelated references.

   If skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` for each assigned hypothesis. Render `{plugin-root}/references/skill-activation-payload.md` and prepend it to each child prompt. Include research context only when `compile-research-context.sh` returns content. Include todo detail or sparse enrichment only when it has signal.

   Use this task description for each of the three parallel debuggers, replacing `{assigned hypothesis}` and `{hypothesis brief}` with that contract's values:

   ```text
   Bug investigation. Effort: {EFFORT_PROFILE}.
   <skill_activation>
   {Rendered skill activation payload for this assigned hypothesis.}
   </skill_activation>
   Assigned hypothesis: {assigned hypothesis}.
   Hypothesis brief: {hypothesis brief}.
   <accepted_exception_debug_semantics>
   {Paste the shared accepted-exception semantics from Step 1.}
   </accepted_exception_debug_semantics>
   Bug report: {description}.
   {Include research, detail, and sparse enrichment only when present.}
   Working directory: {pwd}.
   If `.lbwc-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) before investigating.
   Evaluate the assigned hypothesis, reproduce, gather evidence, and diagnose. Return `debugger_report` using `{plugin-root}/references/handoff-schemas.md`, with an explicit `resolution_observation` of `already_fixed`, `needs_change`, or `inconclusive`, exact diagnosed product file paths, proposed changes, verification commands, and pre-existing issues. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context.
   Do not edit files, write planning artifacts, run mutating Bash or Git commands, ask user questions, or claim final session ownership.
   ```

   After all three reports return, the main session performs the synthesis sequentially. Compare the reports and produce confidence-ranked evidence for each hypothesis, explicitly marking each as `confirmed` or `rejected`, retaining the evidence that supports or contradicts it, and de-duplicating contributing factors and pre-existing issues. Only after this synthesis may the main session select the validated root cause and decide whether to issue the contract-scoped implementation debugger.

   For the serial path (`INVESTIGATION_MODE=serial`), compile optional prior research with `compile-research-context.sh` using the parsed bug description. Keep it only when non-empty. Include the accepted-exception semantics and compact source metadata when present. The report must include the no-tool circuit breaker result for unrelated failures.

   ```bash
   PROJECT_ROOT=$(pwd)
   DEBUG_BRIEF="{bug description from Step 1}"
   CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-investigate-{task-slug}" --command debug --role debugger --team solo --job "$DEBUG_BRIEF") || exit 1
   TASK_ID=$(basename "$CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" debugger --job "$DEBUG_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
   ```

   Read the emitted `Agent-call parameters:` and `SPAWN_READY` line. Spawn the Debugger with only its printed `subagent_type`, `name`, and `model`. Do not add any other Agent-call fields. This single debugger investigates sequentially. Before composing its task description, evaluate available MCP tools in your system context relevant to this investigation and note them in the task context. The serial task description must also include exactly one explicit `<skill_activation>` or `<skill_no_activation>` block and follow the same bounded skill-selection, research, detail, and no-tool-circuit-breaker requirements above.

   Use this task description for the serial debugger:

   ```text
   Bug investigation. Effort: {EFFORT_PROFILE}.
   <skill_activation>
   {Rendered skill activation payload, or the explicit no-activation outcome.}
   </skill_activation>
   <accepted_exception_debug_semantics>
   {Paste the shared accepted-exception semantics from Step 1.}
   </accepted_exception_debug_semantics>
   Bug report: {description}.
   {Include research, detail, and sparse enrichment only when present.}
   Working directory: {pwd}.
   If `.lbwc-planning/codebase/META.md` exists, read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) before investigating.
   Evaluate all relevant hypotheses, reproduce, gather evidence, and diagnose. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context. Return `debugger_report` using `{plugin-root}/references/handoff-schemas.md`, with an explicit `resolution_observation` of `already_fixed`, `needs_change`, or `inconclusive`, exact diagnosed product file paths, proposed changes, verification commands, and pre-existing issues. Include the no-tool circuit breaker result for unrelated failures.
   Do not edit files, write planning artifacts, run mutating Bash or Git commands, ask user questions, or claim final session ownership.
   ```

   **Implementation after diagnosis:** If the validated `debugger_report` says `needs_change`, the main session must derive a de-duplicated list of exact existing or new product file paths from the report. Reject empty, directory, glob, planning-artifact, test-path, or unverified paths. Issue a new solo Debugger contract once per implementation job, repeating each exact path as a `--write-allowance` on both helpers:

   ```bash
   IMPL_BRIEF="implement diagnosed debug fix: {one-line plan}. Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context."
   CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-implement-{task-slug}" --command debug --role debugger --team solo --job "$IMPL_BRIEF" --write-allowance "{exact diagnosed product path}" [--write-allowance "{another exact diagnosed product path}"]) || exit 1
   TASK_ID=$(basename "$CONTRACT_PATH" .json)
   bash "{plugin-root}/scripts/agent-generator.sh" debugger --job "$IMPL_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --write-allowance "{exact diagnosed product path}" [--write-allowance "{another exact diagnosed product path}"] || exit 1
   bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
   ```

   Read its emitted spawn values and invoke only printed `subagent_type`, `name`, and `model`. The implementation prompt names the exact contract paths, diagnosis, rejected hypotheses, verification commands, and states: implement only those paths, report evidence, do not write planning artifacts, ask user questions, or run Git commands. The implementation prompt MUST begin with exactly one explicit `<skill_activation>` or `<skill_no_activation>` block and must also evaluate available MCP tools relevant to this investigation. Include this exact instruction in the implementation task context: `Also evaluate available MCP tools in your system context relevant to this investigation and note them in the task context.` The main session runs verification and creates the fix commit after it passes. If the report is `already_fixed` or `inconclusive`, do not issue an implementation contract.

5. **Persist to debug session + Clear delegation marker + Present:**

   <debug_session_persistence>
   After the report-only investigation and any contract-scoped implementation complete, the main session runs verification and, only if it passes, creates the product fix commit. Capture the post-investigation HEAD before classifying the outcome:

   ```bash
   HEAD_AFTER=$(git rev-parse HEAD 2>/dev/null || echo "")
   ```

   Resolve one authoritative analysis-scoped `RESOLUTION_OBSERVATION` before persisting anything. Use the validated single `debugger_report.payload.resolution_observation`. Normalize it to exactly one of `already_fixed`, `needs_change`, or `inconclusive`. Do **not** infer `already_fixed` from free-text phrasing or from commit presence alone.

    Before mapping `already_fixed` to `INVESTIGATION_OUTCOME=already_fixed`, verify fresh current evidence of actual resolution.
    For selected known issues, UAT deviations, or accepted-process-exception details, accepted disposition alone is insufficient. Use `needs_change` when remediation remains, or `inconclusive` when no safe fix can be applied.
    A no-commit session may still complete as `already_fixed` when fresh evidence proves the branch already contains a real fix.

   Then compute the command-local three-way outcome: new commit created now (`HEAD_BEFORE` != `HEAD_AFTER`) → `INVESTIGATION_OUTCOME=fixed_now`, no new commit now + `RESOLUTION_OBSERVATION=already_fixed` → `INVESTIGATION_OUTCOME=already_fixed`, no new commit now + `RESOLUTION_OBSERVATION=needs_change|inconclusive` → `INVESTIGATION_OUTCOME=no_fix_yet`.

   Persist branch-specific investigation wording, do not collapse `already_fixed` and `no_fix_yet` into the same `"No fix applied"` text.

   Build the investigation JSON payload:

   ```bash
   INVESTIGATION_JSON=$(cat <<'ENDJSON'
   {
     "mode": "investigation",
     "title": "{one-line bug summary}",
     "issue": "{bug description from user}",
     "hypotheses": [
       {
         "description": "{hypothesis description}",
         "status": "confirmed|rejected",
         "evidence_for": "{supporting evidence}",
         "evidence_against": "{contradicting evidence}",
         "conclusion": "{why chosen or rejected}"
       }
     ],
     "root_cause": "{confirmed root cause with file references}",
     "plan": "{chosen fix approach}",
     "implementation": "{summary of changes, or branch-specific text: fixed_now = changes applied now. already_fixed = no new changes were required because the current branch already contained the fix. no_fix_yet = investigation completed without applying a new fix in this run}",
     "changed_files": ["{file1}", "{file2}"],
     "commit": "{fixed_now = commit hash and message. already_fixed = 'Already fixed before this investigation, no new fix commit was required. If planning_tracking=commit, this completion path may create a planning-artifact commit.'; no_fix_yet = 'No new commit created during this investigation.'}"
   }
   ENDJSON
   )
   echo "$INVESTIGATION_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

   Then update session state from `INVESTIGATION_OUTCOME`. For `fixed_now`, set status to `qa_pending`:

   ```bash
   bash "{plugin-root}/scripts/debug-session-state.sh" set-status .lbwc-planning qa_pending
   ```

   For `already_fixed`, mark the investigation complete using the existing completed-session workflow:

   ```bash
   bash "{plugin-root}/scripts/debug-session-state.sh" set-status .lbwc-planning complete
   PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "complete debug session" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```

   For `no_fix_yet`, do **not** set `fix_applied`, keep the session status as `investigating`.
   </debug_session_persistence>

   Always clear the marker, regardless of outcome:

   ```bash
   bash "{plugin-root}/scripts/delegated-workflow.sh" clear
   ```

   Per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Bug Investigation Complete
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Mode:       {INVESTIGATION_MODE=parallel: "Competing Hypotheses (3 parallel)" + confirmed/rejected outcome per hypothesis | INVESTIGATION_MODE=serial: "Standard (single debugger)"}, report-only diagnosis followed by contract-scoped implementation when needed
     Issue:      {one-line summary}
     Root Cause: {from report}
     Outcome:    {fixed_now | already_fixed | no_fix_yet}
     Resolution: {fixed_now = "Applied now in {commit hash + message}" | already_fixed = "Already fixed on the current branch, no new fix commit was required. this completion path may still create a planning-artifact commit when planning_tracking=commit" | no_fix_yet = "No new commit created, further implementation still required"}

     Files Modified: {list}
   ```

  If `SELECTED_TODO_MODE=true`, any numbered list captured before pickup is stale because helper pickup has already changed `STATE.md`. Use `SELECTED_TODO_START_JSON.pickup.status`, `.pickup.warning`, and `.pickup.auto_note` instead of inventing fresh numbered cleanup advice. Never tell the user to `remove N` for the selected todo, `/lbwc:debug` already picked it up automatically. The helper auto note says the selected todo was picked up automatically. emit `.pickup.auto_note` verbatim. Never cite a remaining todo number unless you first refresh through the existing snapshot/resolver flow. Default low-token UX: unnumbered prose only, emit `.pickup.auto_note` and, when related backlog items may still exist, say `Rerun /lbwc:list-todos for fresh numbering.` If `.pickup.status` is `partial` and `.pickup.warning` is non-empty, surface that warning explicitly.

**Discovered Issues:** If the Debugger reported pre-existing failures, out-of-scope bugs, or issues unrelated to the investigated bug, append after the result box. Cap the list at 20 entries. if more exist, show the first 20 and append `... and {N} more`:

```text
  Discovered Issues:
    ⚠ testName (path/to/file): error message
    ⚠ testName (path/to/file): error message
  Suggest: /lbwc:todo <description> to track
```

This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT invoke /lbwc:todo, and do NOT enter an interactive loop. The user decides whether to track these. If no discovered issues: omit the section entirely.

If `INVESTIGATION_OUTCOME=no_fix_yet` (session status is still `investigating`): STOP with `➜ Next: /lbwc:debug --resume -- Continue investigation and apply fix`. Do not enter inline QA.

If `INVESTIGATION_OUTCOME=already_fixed`: STOP with `➜ Debug session complete. Investigation confirmed the fix was already present.` Do not enter inline QA.

If `INVESTIGATION_OUTCOME=fixed_now` and session status is `qa_pending`: proceed to `<debug_inline_qa>` below (even if discovered issues were displayed above, they are informational only and do not gate the QA lifecycle).

<debug_inline_qa>
**Inline QA, runs automatically after a fix is committed.**

Read the `auto_uat` config:

```bash
AUTO_UAT=$(jq -r '.auto_uat // "false"' .lbwc-planning/config.json 2>/dev/null || echo "false")
```

Resolve effort profile if not already set (needed for tier resolution):

```bash
if [ -z "${EFFORT_PROFILE:-}" ]; then
  EFFORT_PROFILE=$(jq -r '.effort // "balanced"' .lbwc-planning/config.json 2>/dev/null || echo "balanced")
fi
```

**QA orchestration (absorbed from /lbwc:qa debug-session mode):**

1. Compile QA context:

  ```bash
  QA_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" qa)
  ```

1. Resolve tier from effort profile: fast=quick, balanced=standard, thorough=deep. Store as `ACTIVE_TIER`. If turbo:

  ```bash
  bash "{plugin-root}/scripts/debug-session-state.sh" set-status .lbwc-planning uat_pending
  ```

   Then jump directly to `<debug_inline_uat>` below, skip all remaining QA steps (do not increment QA round).

1. Increment QA round:

  ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-qa .lbwc-planning)"
  ```

1. Issue a read-only QA contract and generate it with the generic helper:

  ```bash
  PROJECT_ROOT=$(pwd)
  QA_BRIEF="debug-session verification, round {qa_round}"
  CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "debug-qa-{session_id}-{qa_round}" --command debug --role qa --team solo --job "$QA_BRIEF") || exit 1
  TASK_ID=$(basename "$CONTRACT_PATH" .json)
  bash "{plugin-root}/scripts/agent-generator.sh" qa --job "$QA_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" || exit 1
  bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
  ```

  Read `Agent-call parameters:` and `SPAWN_READY`. Spawn QA using only printed `subagent_type`, `name`, and `model`. Do not add any other Agent-call fields.

    Before composing the QA task description, evaluate installed skills visible in your system context in two passes. First derive technical domains from session context, errors, files, and bounded enrichment. Prefer those signals over generic stack guesses. If they mention SwiftData markers, select `swiftdata`. Select `core-data` only when the evidence names Core Data APIs.
    Select all materially helpful direct skills and narrowly adjacent support skills. Do not select only the single most direct skill. The QA prompt MUST begin with exactly one explicit `<skill_activation>` or `<skill_no_activation>` block. Silent omission is invalid. State the skill outcome in your response. Cite bounded enrichment when it influenced the choice.
    After calling `Skill(...)`, read only relevant follow-up files named by the skill. Do not scan entire skill folders or read unrelated references.

    If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the inline debug-session QA agent. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

  Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.

   Task description for debug-session QA:

   ```text
   Debug session verification. Tier: {ACTIVE_TIER}. Round: {qa_round}.

   This is a debug-session QA round, NOT a phase-scoped verification. You are verifying
   a standalone debug fix, there are no phase PLAN.md or SUMMARY.md files.

   Session context (issue, investigation, plan, implementation, prior QA rounds):
   {QA_CONTEXT}

   Verification targets:
   - The root cause identified in the investigation is correct
   - The fix addresses the root cause (not just the symptom)
   - Changed files are correct and complete
   - No regressions introduced in modified files
   - Related tests pass

   Output your verdict as PASS, FAIL, or PARTIAL with a checks table.
   Return a structured qa_verdict inline. Do not write files or run Git commands. The main session validates and persists the round.
   Format each check as: ID | Description | Status (PASS/FAIL) | Evidence
   ```

1. Process the QA result:
   Parse the verdict (PASS/FAIL/PARTIAL) from the QA agent's response.

   Write the QA round to the session file:

   ```bash
   QA_RESULT_JSON=$(cat <<'ENDJSON'
   {
     "mode": "qa",
     "round": {qa_round},
     "result": "{PASS|FAIL|PARTIAL}",
     "checks": [
       {"id": "{check-id}", "description": "{check description}", "status": "{PASS|FAIL}", "evidence": "{evidence}"}
     ]
   }
   ENDJSON
   )
   echo "$QA_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

   Update session status based on result:
   - PASS → `bash .../debug-session-state.sh set-status .lbwc-planning uat_pending`
   - FAIL or PARTIAL → `bash .../debug-session-state.sh set-status .lbwc-planning qa_failed`

2. Present debug-session QA result:
   Per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug QA: Round {qa_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Tier:     {quick|standard|deep}
     Result:   {✓ PASS | ✗ FAIL | ◆ PARTIAL}
     Checks:   {passed}/{total}
     Failed:   {list or "None"}

   ```

**QA failure handling:** If FAIL or PARTIAL:

- Display: `QA found issues. Re-investigating...`
- Load failure context: `FAILURE_CONTEXT=$(bash .../compile-debug-session-context.sh "$session_file" qa 2>/dev/null || echo "")`
- Update status to `investigating` via `write-debug-session.sh` (mode=status)
- Re-enter investigation from Step 3 with the failure context prepended to the bug report (same pattern as `--resume` from `qa_failed`). After the next fix commit, inline QA fires again automatically.

**QA pass:** If PASS, proceed to `<debug_inline_uat>` below.
</debug_inline_qa>

<debug_inline_uat>
**Inline UAT, prompt-gated by default (`auto_uat`), runs automatically when `auto_uat=true`.**

Resolve `AUTO_UAT` if not already set (needed when entering via `--resume` from `uat_pending`):

```bash
if [ -z "${AUTO_UAT:-}" ]; then
  AUTO_UAT=$(jq -r '.auto_uat // "false"' .lbwc-planning/config.json 2>/dev/null || echo "false")
fi
```

**Prompt gate:** If `AUTO_UAT` is not `"true"`, call AskUserQuestion:

```yaml
question: "QA passed. Run UAT verification now?"
header: "Debug Session"
multiSelect: false
options:
  - label: "Yes"
    description: "Run UAT checkpoints inline"
  - label: "No"
    description: "Skip, I'll resume later with /lbwc:debug --resume"
```

**AskUserQuestion is a tool call (NON-NEGOTIABLE):** You MUST invoke AskUserQuestion via the tool_use mechanism, never emit the question parameters as text, YAML, or any other inline format in your response body. If AskUserQuestion appears in your text output instead of as a tool call, the prompt will not be presented to the user and the session will end prematurely. **STOP HERE.** Wait for the AskUserQuestion response before processing the answer.

If the user selects "No": STOP with `➜ Next: /lbwc:debug --resume -- Continue to UAT verification`.
If the user selects "Yes": proceed.
If the user provides freeform input: proceed only when the response is clearly affirmative (e.g., "yes", "y", "sure", "go ahead"). If the response is negative or deferring (e.g., "no", "not now", "later", "skip"): treat as "No" and STOP. If ambiguous: ask a brief follow-up to confirm before proceeding.

If `AUTO_UAT` is `"true"`: skip the prompt and proceed directly.

**UAT orchestration (absorbed from /lbwc:verify debug-session mode):**

1. Compile UAT context:

  ```bash
  UAT_CONTEXT=$(bash "{plugin-root}/scripts/compile-debug-session-context.sh" "$session_file" uat)
  ```

1. Increment UAT round:

  ```bash
  eval "$(bash "{plugin-root}/scripts/debug-session-state.sh" increment-uat .lbwc-planning)"
  ```

1. Generate 1-3 UAT checkpoints from the session context. These must require HUMAN judgment:
   - Reproduce the original bug, is it fixed?
   - Check related workflows, any regressions visible?
   - Verify the fix from the user's perspective

   **Guardrails:** Never ask the user to run automated checks (tests, lint, build commands), those belong in QA. If the fix is purely internal (test-infra, script-only, non-user-facing), fall back to a single lightweight checkpoint: "Does the app still work as expected from your perspective?" rather than generating inapplicable user-facing scenarios.

2. Present checkpoints one at a time using CHECKPOINT + AskUserQuestion:

    **Checkpoint presentation boundary (NON-NEGOTIABLE):** The debug UAT checkpoint loop is conversational and blocking. Each cycle presents exactly one checkpoint, and the CHECKPOINT display plus the `AskUserQuestion` tool_use MUST be emitted in the same assistant response. Treat the checkpoint display and tool call as one atomic presentation step: never split them across turns. A text-only checkpoint is invalid because it gives the user no structured response path and can let the turn end prematurely. Do NOT end the turn after displaying checkpoint text. the only valid pause is waiting for the blocking `AskUserQuestion` response. Do not process an answer, advance to later checkpoints, persist UAT state, or finalize the session until that tool response is available.

   Per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md:

    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      CHECKPOINT {NN}/{total}, Debug Fix Verification
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    {scenario description}
    ```

    Then call AskUserQuestion. Keep the modal question self-contained because it may cover the surrounding checkpoint prose:

    ```yaml
    question: "Scenario: {scenario description}\n\nExpected: {expected result}\n\nDoes the behavior match this checkpoint?"
    header: "UAT"
    multiSelect: false
    options:
      - label: "Pass"
        description: "Behavior matches expected result"
      - label: "Skip"
        description: "Cannot test right now, skip this checkpoint"
    ```

   **AskUserQuestion is a tool call (NON-NEGOTIABLE).** Invoke it through the tool_use mechanism. Never emit its parameters as text, YAML, or inline response content.
   If the question appears in text instead of a tool call, the checkpoint will not reach the user. Stop and wait for the user after each checkpoint.

3. Response mapping (same rules as /lbwc:verify. AskUserQuestion automatically provides a freeform "Other" option):
   - "Pass" → record as passed
   - "Skip" → record as skipped
   - Freeform text via "Other" → treat as issue description, infer severity from keywords (crash/broken/error=critical, wrong/missing/bug=major, minor/cosmetic=minor, default=major)

4. After all checkpoints, persist the UAT round:

   ```bash
   UAT_RESULT_JSON=$(cat <<'ENDJSON'
   {
     "mode": "uat",
     "round": {uat_round},
     "result": "{pass|issues_found}",
     "checkpoints": [
       {"id": "{id}", "description": "{desc}", "result": "pass|skip|issue", "user_response": "{verbatim}"}
     ],
     "issues": [
       {"id": "{id}", "description": "{desc}", "severity": "{level}"}
     ]
   }
   ENDJSON
   )
   echo "$UAT_RESULT_JSON" | bash "{plugin-root}/scripts/write-debug-session.sh" "$session_file"
   ```

5. Update session status:
   - All checkpoints pass (no issues):

     ```bash
     bash "{plugin-root}/scripts/debug-session-state.sh" set-status .lbwc-planning complete
     PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
     if [ -f "$PG_SCRIPT" ]; then
       bash "$PG_SCRIPT" commit-boundary "complete debug session" .lbwc-planning/config.json
     else
       echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
     fi
     ```

   - Any issues found → `bash .../debug-session-state.sh set-status .lbwc-planning uat_failed`

6. Present debug-session UAT result:
   Per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md:

   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Debug UAT: Round {uat_round}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

     Session:  {session_id}
     Result:   {✓ COMPLETE | ✗ ISSUES FOUND}
     Passed:   {N}
     Issues:   {N}

   ```

**UAT failure handling:** If issues found:

- Display: `UAT found issues. Re-investigating...`
- Load failure context: `FAILURE_CONTEXT=$(bash .../compile-debug-session-context.sh "$session_file" uat 2>/dev/null || echo "")`
- Update status to `investigating` via `write-debug-session.sh` (mode=status)
- Re-enter investigation from Step 3 with the failure context prepended (same pattern as `--resume` from `uat_failed`). After the next fix commit, the inline QA → UAT chain fires again automatically.

**UAT pass:** If all checkpoints pass:

- Move session to completed: the `complete` status set above handles this.
- Display: `➜ Debug session complete. The fix is verified.`
- STOP.
</debug_inline_uat>

<debug_session_next_step>
Session-aware next step (only shown when the inline flow did not run):

- If investigation completed but no fix was applied (session status is `investigating`):
  `➜ Next: /lbwc:debug --resume -- Continue investigation and apply fix`
- If session was not created (error or guard stopped execution):
  `➜ Next: /lbwc:status -- View project status`
</debug_session_next_step>

## Failure and recovery

- If a contract, generator, spawn, payload validation, implementation verification, or main-session commit fails, clear the delegation marker and report the failure verbatim. Do not create an uncontracted fallback.
- Preserve the debug session as `investigating` until a validated implementation has passed main-session verification.

## Output Format

Use the existing investigation, QA, and UAT result blocks. Report the main-session commit only after it exists.

## Next Up

Use the session-aware next steps above and `suggest-next.sh`.
