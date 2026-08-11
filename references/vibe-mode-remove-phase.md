## Main-session Decision Handoffs

Only the main session may call `AskUserQuestion`. Before every confirmation or
checkpoint, follow `references/lbwc-brand-essentials.md`, then call it from the
main session. A worker that reaches a decision boundary returns
`user_decision_required` JSON defined in `references/subagent-contracts.md`. It does not mutate state, claim a todo, or start
the next stage until the main session supplies the response. A declined choice
preserves state and reports the documented Next Up command.

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/lbwc:vibe --remove <phase-number>`"
Not found: STOP "Phase {NN} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {NN} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {NN}."

**Steps:**
1. Parse args: extract phase number, validate, look up name/slug.
2. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
3. Remove dir: `rm -rf .lbwc-planning/phases/{NN}-{slug}/`
4. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
5. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
6. If `.lbwc-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
7. Update STATE.md phase total: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .lbwc-planning --removed {NN}` (where {NN} is the removed phase number from step 1).
8. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "remove phase {NN}" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.lbwc-planning/` if changed. Other modes no-op.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/planning-git.sh`
- `scripts/update-phase-total.sh`
