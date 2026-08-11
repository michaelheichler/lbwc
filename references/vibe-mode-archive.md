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

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/lbwc:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Hard UAT gate (always, non-bypassable):**
Before any audit/bypass handling, run:
```bash
bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/archive-uat-guard.sh
```
If exit code is 2: STOP. Unresolved UAT (active or milestone) blocks archive regardless of `--skip-audit` or `--force`.

**Hard state-consistency gate (always, non-bypassable):**
After the UAT gate passes, run:
```bash
bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/verify-state-consistency.sh .lbwc-planning --mode archive
```
If exit code is non-zero: STOP. If exit code is 2, state misalignment at archive means the archived milestone record may be unreliable. Phase counts, completion markers, or project metadata could be inconsistent. Surface the JSON output's `failed_checks` array so the user can fix the drift before retrying. For any other non-zero exit, treat the verifier as failed unexpectedly and do not proceed with archive.

**Pre-gate audit (unless --skip-audit or --force):**
Run 7-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: authoritative QA verification exists and is fresh PASS. Missing=WARN, failed=FAIL. After QA remediation reaches `done`, the authoritative artifact is the round-scoped `R{RR}-VERIFICATION.md`. The frozen phase-level VERIFICATION.md must not be reused.
6. UAT status: any `*-UAT.md` with `status: issues_found` = FAIL. Unresolved UAT issues must be remediated before archiving.
7. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. **Derive milestone slug deterministically (do NOT invent a slug):**
   ```bash
   MILESTONE_SLUG=$(bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .lbwc-planning)
   ```
  This reads ROADMAP.md phase names and outputs a numbered kebab-case slug (e.g., `01-setup-api-layer`). Keep this milestone slug separate from any custom git tag passed via `--tag`. **Never use a hardcoded slug like "default". Always use the script output.**
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `rolling_summary=true` in config:
   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-rolling-summary.sh \
     .lbwc-planning/phases .lbwc-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `rolling_summary=false`: skip.
5. Archive: `mkdir -p .lbwc-planning/milestones/{SLUG}`. Move ROADMAP.md, STATE.md, and phases/ to milestones/{SLUG}/. If `.lbwc-planning/CONTEXT.md` exists, move it to milestones/{SLUG}/CONTEXT.md. Use the **Write** tool (not Bash) to create `.lbwc-planning/milestones/{SLUG}/SHIPPED.md`. This ensures PostToolUse hooks fire for artifact tracking. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/persist-state-after-ship.sh \
     .lbwc-planning/milestones/{SLUG}/STATE.md .lbwc-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "archive milestone {SLUG}" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Regenerate CLAUDE.md: follow `references/agent-spawn-protocol.md`. Issue a solo `docs` command contract for job `regenerate CLAUDE.md for milestone {SLUG} ship` with `CLAUDE.md` as its exact write allowance. Run the generic `scripts/agent-generator.sh docs` call, advance the contract to `dispatched`, and capture its `SPAWN_READY` name. Render the prompt prefix from `references/skill-activation-payload.md`.
   Task it: "Update root CLAUDE.md's `## Active Context` section for the just-shipped milestone {SLUG}. Remove references to now-shipped work. Preserve all non-LBWC content verbatim. Only replace canonical LBWC-managed sections already present in the file."
   Use the generated name and Agent-call parameters exactly as printed. Omit team and worktree fields. Do not re-resolve or override model, effort, or turns.
   Wait for completion before continuing to step 9b.
9b. Post-archive hook (non-blocking): after successful archive completion, run:
   ```bash
   bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/post-archive-hook.sh "{SLUG}" ".lbwc-planning/milestones/{SLUG}" "{tag}" .lbwc-planning/config.json
   ```
   Use the tag selected in step 8, or an empty third argument when `--no-tag` was used. Repos without `hooks.post_archive` configured no-op through the dispatcher. Any warnings are non-blocking.
10. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/archive-uat-guard.sh`
- `scripts/compile-rolling-summary.sh`
- `scripts/derive-milestone-slug.sh`
- `scripts/persist-state-after-ship.sh`
- `scripts/planning-git.sh`
- `scripts/post-archive-hook.sh`
- `scripts/suggest-next.sh`
