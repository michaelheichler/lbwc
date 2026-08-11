---
name: lbwc:fix
category: supporting
disable-model-invocation: true
description: Apply a quick fix or small change with commit discipline. Turbo mode, no planning ceremony.
argument-hint: "<description of what to fix or change>"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, Skill, LSP
---

# LBWC Fix: $ARGUMENTS

## Context

Working directory:

```
!`pwd`
```

Plugin root:

```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

@${CLAUDE_PLUGIN_ROOT}/references/agent-spawn-protocol.md

Config: Pre-injected by SessionStart hook.

## Guard

- Not initialized (no .lbwc-planning/ dir): STOP "Run /lbwc:init first."
- No $ARGUMENTS: STOP "Usage: /lbwc:fix \"description of what to fix\""

## Steps

1. **Resolve todo number:** If $ARGUMENTS is a bare integer (matches `^[0-9]+$` with no other text or flags), preserve the original numeric-selection marker before rewriting anything. Resolve the todo item against the persisted session snapshot of the last `/lbwc:list-todos` view:

    ```bash

  bash "{plugin-root}/scripts/resolve-todo-item.sh" <N> --session-snapshot --require-unfiltered --validate-live
    ```
    Parse the JSON output. If `status` is `"ok"`, store the full payload as `TODO_SELECTED_JSON`, preserve `TODO_SELECTED=true`, and replace $ARGUMENTS with the item's `command_text` value (not the old duplicated `description` form). If the resolved `state_path` points under `.lbwc-planning/milestones/`, STOP with: `This todo came from archived milestone state. Restore the writable root STATE.md first by restarting so session-start.sh can run migration, or run 'bash scripts/migrate-orphaned-state.sh .lbwc-planning'.` Do not continue using the archived description as live work input. If `status` is `"error"`, STOP with the `message` value.

1. **Parse:** Entire $ARGUMENTS (minus flags) = fix description. If `TODO_SELECTED_JSON` exists, treat its `command_text` as the fix description and its `ref` as the already-resolved ref before any additional parsing. Otherwise, if the description contains a `(ref:HASH)` suffix (8 hex characters), extract the hash and strip the ref tag from the description before further processing. If a ref was found, load extended detail:

    ```bash

  bash "{plugin-root}/scripts/todo-details.sh" get <hash>
    ```
Command shape: `bash "{plugin-root}/scripts/todo-details.sh" get <hash>`.
  Parse the JSON output. If `status` is `"ok"`, store the `detail.context` and `detail.files` values for use in step 5 and record `DETAIL_STATUS=ok`. If `status` is `"not_found"` or `"error"`, record `DETAIL_STATUS` to match and run:
    ```bash
    bash "{plugin-root}/scripts/todo-lifecycle.sh" detail-warning {hash}
    ```
    In all cases, continue without detail.
    **Post-parse validation:** If the fix description is empty or whitespace-only after stripping flags and ref, check whether a ref was found AND its detail loaded successfully (status `"ok"`). If yes, proceed, the detail provides the fix context. If no ref was found, or the ref detail failed to load, STOP: `"Usage: /lbwc:fix \"description of what to fix\""`.

1. **State:** Use `.lbwc-planning/STATE.md`.

2. **Set delegation marker:** Before spawning Dev, activate the delegation guard so the orchestrator cannot accidentally write product files directly:

    ```bash

  bash "{plugin-root}/scripts/delegated-workflow.sh" set fix turbo
    ```

- **Immediate todo pickup (numeric selections only):** If `TODO_SELECTED=true`, claim the todo now, after fix has passed its own parse/guard steps, and before Dev is spawned. Pipe `TODO_SELECTED_JSON` into:

     ```bash

    bash "{plugin-root}/scripts/todo-lifecycle.sh" pickup /lbwc:fix {DETAIL_STATUS} {cleanup_policy}
     ```

    Use `safe` for `{cleanup_policy}` when `DETAIL_STATUS=ok`, otherwise use `keep`. If the helper returns `status="error"`, STOP with its `message` value. If it returns `status="partial"`, continue but surface its `warning` value in the final result so cleanup state is explicit. This pickup path only applies to true numeric todo selections, never to manual text or manual `(ref:HASH)` inputs.

1. **Spawn Dev:** Follow `{plugin-root}/references/agent-spawn-protocol.md`. The main session owns planning files, Git, verification, and user questions. The Dev contract allows writes only to exact product paths identified from the parsed fix description, todo detail, and repository evidence. Do not use a directory, glob, or planning artifact as an allowance.

    ```bash
    PROJECT_ROOT=$(pwd)
    DEV_BRIEF="{fix description from Step 1}"
    CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "fix-{task-slug}" --command fix --role coding-dijkstra --team solo --job "$DEV_BRIEF" --write-allowance "{exact diagnosed product path}") || exit 1
    TASK_ID=$(basename "$CONTRACT_PATH" .json)
    bash "{plugin-root}/scripts/agent-generator.sh" coding-dijkstra --job "$DEV_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --write-allowance "{exact diagnosed product path}" || exit 1
    bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
    ```

    Read the emitted `Agent-call parameters:` and `SPAWN_READY` line. Spawn the generated Dev with only its printed `subagent_type`, `name`, and `model`. Do not add any other Agent-call fields.

    Before composing the Dev task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful skills for this fix, including adjacent or supporting skills surfaced by the prompt, logs, error text, related files, or stack context. Do not choose only the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response. If the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test and build skills. After calling `Skill(...)`, read any relevant follow-up files named by that skill before reasoning or acting. Do not scan entire skill folders or read unrelated references.

    If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the Dev. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

    **Discover research context** (optional, from prior `/lbwc:research`):
    ```bash
    RESEARCH_CONTEXT=$(bash "{plugin-root}/scripts/compile-research-context.sh" .lbwc-planning "{fix description from Step 1}" 2>/dev/null || echo "")
    ```
    Replace `{fix description from Step 1}` with the actual parsed fix description. If `RESEARCH_CONTEXT` is non-empty, include it in the Dev task prompt below. If empty, omit the `<standalone_research_context>` block entirely.

    Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line.

    ```text
    Quick fix (Turbo mode). Effort: low.
    Task: {fix description}.
    {Include RESEARCH_CONTEXT and loaded todo detail only when present.}
    Write only the exact product paths in the dispatched task contract. If `.lbwc-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.lbwc-planning/codebase/` before implementing.
    Implement and report changed files, tests run, and any pre-existing issues. Do not write planning artifacts, ask the user questions, or run Git commands. The main session verifies and commits.
    If ambiguous or requires architectural decisions, stop and report back.
    ```

6. **Clear delegation marker + Verify + present:** Clear the marker first, then check results:
    ```bash
  bash "{plugin-root}/scripts/delegated-workflow.sh" clear
    ```
    Validate the Dev report and run the relevant verification in the main session. The main session creates the one atomic `fix(quick): {brief description}` commit only after verification passes. Check the resulting `git log --oneline -1` and Dev response for pre-existing issues.
    Committed, no discovered issues:

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}
    ```

    Run `bash "{plugin-root}/scripts/write-fix-marker.sh" .lbwc-planning 2>/dev/null || true` silently, this persists fix context for inline QA/UAT.
    Run `bash "{plugin-root}/scripts/suggest-next.sh" fix` and display.

    Committed, with discovered issues (Dev reported pre-existing failures):

    De-duplicate by test name and file (keep first error message when the same
    test+file pair has different messages). Cap the list at 20 entries, if more
    exist, show the first 20 and append `... and {N} more`.

    ```text
    ✓ Fix applied
      {commit hash} {commit message}
      Files: {changed files}

      Discovered Issues:
        ⚠ testName (path/to/file): error message
        ⚠ testName (path/to/file): error message
      Suggest: /lbwc:todo <description> to track
    ```

    This is **display-only**. Do NOT edit STATE.md, do NOT add todos, do NOT
    invoke /lbwc:todo, and do NOT enter an interactive loop. The user decides
    whether to track these. If no discovered issues: omit the section entirely.
    After displaying discovered issues, **STOP. Do not take further action** on discovered issues (no auto-fix, no auto-track, no investigation),just display them.
    Run `bash "{plugin-root}/scripts/write-fix-marker.sh" .lbwc-planning 2>/dev/null || true` silently, this persists fix context for inline QA/UAT.
    Run `bash "{plugin-root}/scripts/suggest-next.sh" fix` and display.

    Dev stopped:

    ```text
    ⚠ Fix could not be applied automatically
      {reason from Dev agent}
    ```

    Run `bash "{plugin-root}/scripts/suggest-next.sh" debug` and display.

## Failure and recovery

- If contract issuance, generation, spawn, or verification fails, clear the delegation marker, preserve the working tree, and report the failure verbatim. Do not create an uncontracted fallback.
- If the Dev reports ambiguity, stop without a commit and direct the user to `/lbwc:debug`.

## Output Format

Use the existing success, discovered-issues, and stopped result blocks above. Include the main-session commit only after it exists.

## Next Up

Use `suggest-next.sh` output. For an unresolved issue, recommend `/lbwc:debug`.
