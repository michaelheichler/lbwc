## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

## Generated Agent Authority

For every agent spawn, follow `references/agent-spawn-protocol.md`. The main
session issues the command contract, runs `scripts/agent-generator.sh`, and
uses its `SPAWN_READY` name and printed settings exactly. Generated output is
the sole authority for name, model, effort, and turn limit. Do not select them
from a static model profile. Every spawn below uses the generic contract-issuing
generator protocol.

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/lbwc:vibe --add <phase-name>`"

**Steps:**

**Phase setup (steps 1-4):**
**Step 1, codebase context:** If `.lbwc-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.lbwc-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
**Step 2, parse arguments:** Phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
**Step 3, next number:** Highest in ROADMAP.md + 1, zero-padded.
**Step 4, create directory:** `mkdir -p .lbwc-planning/phases/{NN}-{slug}/`
5. **Problem research (conditional):** If $ARGUMENTS contain a problem description (bug report, feature request, multi-sentence intent) rather than just a bare phase name:
  **Scout contract and spawn:** Follow `references/agent-spawn-protocol.md`. Issue a solo `scout` command contract for job `research added phase {NN}` with `{phase-dir}/{NN}-RESEARCH.md` as the exact write allowance. Run the generic `scripts/agent-generator.sh scout` call, advance the contract to `dispatched`, and use the printed Agent-call parameters and `SPAWN_READY` name exactly. Omit team and worktree fields. Do not re-resolve model, effort, or turns. Stop and report a contract or generator failure instead of silently running an uncontracted fallback.
  Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so the contracted Scout writes its findings directly.
  **Skill selection:** Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  **Skill follow-up files:** If one or more skills were preselected, run `bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the add-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Render the prompt prefix from `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
  **MCP context:** Also evaluate available MCP tools. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context.
  - After Scout completes, confirm the file exists (read first line).
  - Use Scout findings to write an informed phase goal and success criteria in ROADMAP.md.
  - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
  - **This eliminates duplicate research.** Plan mode step 3 checks for existing RESEARCH.md and skips Scout if found.
6. Update ROADMAP.md: append phase list entry, append Phase Details section (using Scout findings if available), add progress row.
7. If `.lbwc-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
8. Update STATE.md phase total: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .lbwc-planning`
9. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "add phase {NN}-{slug}" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.lbwc-planning/` if changed. Other modes no-op.
10. Present: Phase Banner with position, goal. Checklist for roadmap update + dir creation. Next Up: `/lbwc:vibe --discuss` or `/lbwc:vibe --plan`.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/extract-skill-follow-up-files.sh`
- `scripts/planning-git.sh`
- `scripts/update-phase-total.sh`
