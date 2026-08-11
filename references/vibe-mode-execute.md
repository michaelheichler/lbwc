## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

**Execute-mode invariant:** Parallel execution is only valid when dependency-aware routing finds real parallel delegate work and the live tool set can create real team-scoped teammates. If routing selects serialized subagents, turbo/internal direct, or real team semantics cannot be established, execute mode must fall back to explicit non-team execution. Never simulate a team with background `Agent` spawns that lack `team_name`.

Read `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/execute-protocol.md` and follow it.

This mode delegates entirely to the protocol file. **Orchestrator read-scope:** Do NOT read product source files. Your job is orchestration: read plans, check summaries, and spawn Dev for remaining work. If you need product-code understanding to route or sequence, delegate that to Dev.

Before reading:
**Step 0, pre-normalize filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
**Step 1, parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /lbwc:init first."
   - No PLAN.md in phase dir: STOP "Phase {NN} has no plans. Run `/lbwc:vibe --plan {NN}` first."
   - All plans have SUMMARY.md: cautious/standard -> WARN + confirm. Confident/pure-vibe -> warn + auto-continue.
   - **Milestone path guard:** If `{phase_dir}` contains `.lbwc-planning/milestones/`, STOP "Cannot execute inside archived milestones." This prevents writing artifacts into shipped milestone directories.
3. **Compile context:** If `config_context_compiler=true`, run:
   - `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
   - `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} qa {phases_dir}`
   Include compiled context paths in Dev and QA task descriptions. When referencing `.context-dev.md`, describe it as: "compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions). It also includes phase operational context (goal, conventions, active plan, research findings, changed files, code slices)." When referencing `.context-qa.md`, describe it as: "compiled context. It includes milestone scope decisions and phase verification context (success criteria, requirements, conventions to check)."
  If `TODO_SELECTED_JSON` already exists from the numbered-todo path and `DETAIL_STATUS=ok`, reuse the already-loaded detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.`

  Otherwise, if a ref hash was extracted during Input Parsing, load extended detail now:
   ```bash
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh get {hash}
   ```
  Parse the JSON output. If `status` is `"ok"`, include the detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.` If `status` is `"not_found"` or `"error"`, run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh detail-warning {hash}` and continue without detail. Do not block. This provides the executing agent with the rich context that motivated the work item.

Then Read the protocol file and execute Steps 2-5 as written.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/normalize-plan-filenames.sh`
- `scripts/todo-details.sh`
- `scripts/todo-lifecycle.sh`
