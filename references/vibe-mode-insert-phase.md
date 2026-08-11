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

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/lbwc:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. **Codebase context:** If `.lbwc-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.lbwc-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
2. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated). Format the position as a zero-padded two-digit `{NN}` (for example, position 3 is `03`).
3. Identify renumbering: all phases >= position shift up by 1.
4. Renumber dirs in REVERSE order: rename dir `{NN}-{slug}` -> `{NN+1}-{slug}`, rename every number-prefixed internal artifact (`PLAN`, `SUMMARY`, `RESEARCH`, `CONTEXT`, `UAT`, `VERIFICATION`, and per-plan `{NN}-{MM}-*` files), update `phase:` frontmatter, update `depends_on` references.
5. Create dir: `mkdir -p .lbwc-planning/phases/{NN}-{slug}/` (with `{NN}` zero-padded).
6. **Problem research (conditional):** If the arguments include a problem description, follow `references/agent-spawn-protocol.md`. Issue a solo `scout` command contract for job `research inserted phase {NN}` with `{phase-dir}/{NN}-RESEARCH.md` as its exact write allowance. Run the generic `scripts/agent-generator.sh scout` call, advance the contract to `dispatched`, and spawn it with the printed Agent-call parameters. Omit team and worktree fields. Do not re-resolve model, effort, or turns. Evaluate relevant skills and MCP tools, then render `references/skill-activation-payload.md`. After Scout completes, validate the file before using it. Stop and report a contract or generator failure verbatim.
  If one or more skills were preselected, run `bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the insert-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Render the prompt prefix from `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
7. Update ROADMAP.md: insert new phase entry + details at position (using Scout findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
8. If `.lbwc-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
9. Update STATE.md phase total: `bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .lbwc-planning --inserted {position}` (where {position} is the insert position from step 2).
10. **Phase mutation commit boundary (conditional):**
    ```bash
   PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
    if [ -f "$PG_SCRIPT" ]; then
      bash "$PG_SCRIPT" commit-boundary "insert phase {NN}-{slug} at position {position}" .lbwc-planning/config.json
    else
      echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
    fi
    ```
    Behavior: `planning_tracking=commit` commits `.lbwc-planning/` if changed. Other modes no-op.
11. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/extract-skill-follow-up-files.sh`
- `scripts/planning-git.sh`
- `scripts/update-phase-total.sh`
