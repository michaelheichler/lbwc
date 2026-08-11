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

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/lbwc:vibe --plan N`"
**Milestone path guard:** If `{phases_dir}` contains `.lbwc-planning/milestones/`, STOP "Cannot plan inside archived milestones." Archived milestones are read-only.

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** Resolve CONTEXT path:
   ```bash
   CONTEXT_NAME=$(bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh context "{phase-dir}")
   ```
   If `{phase-dir}/${CONTEXT_NAME}` exists, include it in Lead agent context. If not, proceed without it. Users who want context run `/lbwc:discuss {NN}` first.
3. **Research persistence (REQ-08, graduated):** If effort != turbo:
   - Research runs for every non-`turbo` workflow effort. The detected catalog route is resolved only when the Scout is generated. If that route is unavailable, generation fails clearly. Do not skip research silently or choose a route by judgment.
   - Determine the next plan number `{MM}` and resolve artifact paths:
     ```bash
     RESOLVE_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh"
     NEXT_PLAN_NAME=$(bash "$RESOLVE_SCRIPT" plan "{phase-dir}")
     MM=$(echo "$NEXT_PLAN_NAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
     RESEARCH_NAME=$(bash "$RESOLVE_SCRIPT" phase-research "{phase-dir}")
     ```
    - Check for phase-wide research `{phase-dir}/${RESEARCH_NAME}` (preferred). If phase-wide does not exist, only treat historical `{phase-dir}/{NN}-01-RESEARCH.md` as brownfield phase research when no higher-numbered per-plan research exists. Compute it with: `OTHER_PLAN_RESEARCH=$(find "{phase-dir}" -maxdepth 1 -name "{NN}-[0-9][0-9]*-RESEARCH.md" ! -name "{NN}-01-RESEARCH.md" -print -quit 2>/dev/null); if [ -f "{phase-dir}/{NN}-01-RESEARCH.md" ] && [ -z "$OTHER_PLAN_RESEARCH" ]; then BROWNFIELD_RESEARCH="{phase-dir}/{NN}-01-RESEARCH.md"; fi`. If `$OTHER_PLAN_RESEARCH` is non-empty, leave `$BROWNFIELD_RESEARCH` empty because multiple per-plan research files remain distinct and do not count as phase-wide research.
   - **If neither exists:** If `config_context_compiler=true`, compile Scout context first: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} scout {phases_dir}`. Include `.context-scout.md` in the Scout prompt if produced, described as: "compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and phase operational context (goal, success criteria, matched requirements, conventions, changed files)."
     Read `prefer_teams` through `scripts/lbwc-config.sh get .lbwc-planning prefer_teams`.
     - **Multi-stream research:** Use this path only when `prefer_teams` is not `never` and the phase has 2 to 4 genuinely independent facets. For each facet, follow `references/agent-spawn-protocol.md`. Issue a separate solo `scout` command contract with that facet's exact `{phase-dir}/{NN}-RESEARCH-{facet-slug}.md` write allowance, run the generic `scripts/agent-generator.sh scout` call, and advance the contract to `dispatched`. Spawn all generated Scouts in one turn with their printed Agent-call parameters and no team or worktree fields. Each prompt covers one facet. The main session waits for all results, validates each file, and synthesizes canonical `{phase-dir}/${RESEARCH_NAME}` while retaining facet files as provenance.
     - **Single-Scout fallback:** Issue one solo `scout` contract with `{phase-dir}/${RESEARCH_NAME}` as its exact write allowance. Generate and spawn it through the same protocol. Use `Agent`, not the removed `Task` tool.
     - For either path, do not resolve or override model, effort, or turns. Stop and report any contract or generator failure verbatim. Evaluate relevant skills and MCP tools before composing each prompt. Render the prefix from `references/skill-activation-payload.md`, including helper-emitted follow-up files when available.
    - **If exists (phase-wide or legacy single-file brownfield):** Record the RESEARCH.md path (phase-wide `${RESEARCH_NAME}` or brownfield `${BROWNFIELD_RESEARCH}`) for inclusion in the Lead prompt. The Lead prompt MUST include the directive: `Read {research-path} for full research findings before planning.` Do NOT inline a summary of the research as a substitute. The Lead must read the file itself to get the complete, unabridged findings. Multiple per-plan research files are not phase-wide research. If no real phase-wide file exists, Scout should create `${RESEARCH_NAME}`. Lead may update the phase-wide RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
    - **Authenticated live validation policy:** Scout may validate authenticated/private read-only APIs with verified-safe Bash helper scripts or curl wrappers after preflight. Public/anonymous HTTP validation uses WebFetch. Do not route authenticated API validation through WebFetch. If a check is unsafe, mutating, or cannot be verified as read-only, Scout must flag it with `⚠ REQUIRES AUTHENTICATED LIVE VALIDATION` for Dev/Debugger. Research that runs or defers live validation must include `## Live Validation Evidence` with `command_shape`, `exit_status`, `redacted_evidence`, `expected_shape`, `confidence`, and `limitations_or_deferred_reason`.
   - If effort=turbo: skip research entirely.
4. **Research commit boundary (conditional):** If Scout was spawned in step 3 (new RESEARCH.md written):
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "research phase {NN}" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping research git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits RESEARCH.md if changed. Skipped when research was pre-existing or effort=turbo.
5. **Context compilation:** If `config_context_compiler=true`, run `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} lead {phases_dir}`. Include `.context-lead.md` in Lead agent context if produced. When including it in the Lead prompt, describe its contents: "Read `.context-lead.md` for compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and operational context (phase goal, success criteria, matched requirements, active decisions, research findings)."
6. **Turbo shortcut:** If effort=turbo, skip Lead. Resolve the plan filename:
   ```bash
   TURBO_PLAN=$(bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh plan "{phase-dir}")
   ```
   Read phase reqs from ROADMAP.md, create single lightweight plan as `${TURBO_PLAN}` in the phase directory.
7. **Other efforts:**

### Spawn Lead

  - Evaluate relevant skills and MCP tools, then render the prompt prefix from `references/skill-activation-payload.md`.
  - Follow `references/agent-spawn-protocol.md`. Issue a solo `lead` command contract for job `phase {NN} planning` with no write allowance. Run the generic `scripts/agent-generator.sh lead` call, advance the contract to `dispatched`, and use its printed Agent-call parameters and `SPAWN_READY` name exactly. Do not re-resolve model, effort, or turns.
  - The Lead returns complete plan content and proposed canonical filenames as evidence. The main session validates the dependency graph and persists the accepted PLAN files. Omit team and worktree fields.
### Lead prompt and result

   - **CRITICAL:** If a RESEARCH.md was found or created in step 3, include in the Lead prompt: `Read {research-path} for full research findings before planning.` where `{research-path}` is the per-plan or legacy path from step 3. The Lead must read the file itself. Do NOT substitute an inlined summary.
  - Required Lead guidance: "Execute may run plans as true team teammates or as serialized Dev subagents. Model real dependencies accurately. Same-wave plans must be genuinely independent and modify disjoint file sets. Linear chains are valid when dependencies are real. Do not invent independence to increase wave 1 size. Dependency-aware Execute uses teams only for real parallel delegate work, and false same-wave grouping can cause stale inputs or file conflicts."
   - **CRITICAL:** Include in the Lead prompt: `Use resolve-artifact-path.sh to compute plan filenames: bash ${RESOLVE_SCRIPT} plan "{phase-dir}" --plan-number {MM}` where `RESOLVE_SCRIPT` is the path from step 3. The script returns the canonical filename (e.g., `03-01-PLAN.md`). Call it once per plan with the plan number.
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
8. **Normalize plan filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
    This catches any misnamed files persisted from returned Lead content or created by turbo mode.
9. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
10. **Present:** Update STATE.md (phase position, plan count, status=Planned). Display the Phase Banner with its plan list and effort level. Agent settings are supplied only by the generated agent contract, never by a static profile document:
    ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ◆ Phase {NN}: {name}
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Plans: {N}
     {plan}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   ```
11. **Planning commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "plan phase {NN}" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` creates a local planning-artifact commit when changed. A remote push always requires main-session confirmation immediately before the shared mutation, regardless of `auto_push`.
12. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {NN}?" Other levels: auto-chain.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/extract-skill-follow-up-files.sh`
- `scripts/normalize-plan-filenames.sh`
- `scripts/planning-git.sh`
