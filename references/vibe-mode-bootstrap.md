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

**Guard:** `.lbwc-planning/` exists but no PROJECT.md.

**Critical Rules (non-negotiable):**
- NEVER fabricate content. Only use what the user explicitly states.
- If answer doesn't match question: STOP, handle their request, let them re-run.
- No silent assumptions. Ask follow-ups for gaps.
- Phases come from the user, not you.

**Constraints:** Do NOT explore/scan codebase (that's /lbwc:map). Use existing `.lbwc-planning/codebase/` if `.lbwc-planning/codebase/META.md` exists.

**Brownfield detection:** `git ls-files` or Glob check for existing code.

**Steps:**
- **B1: PROJECT.md**: If $ARGUMENTS provided (excluding flags), use as description. Otherwise ask name + core purpose. Then call:
  ```
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-project.sh .lbwc-planning/PROJECT.md "$NAME" "$DESCRIPTION"
  ```
- **B1.5: Discovery Depth**: Read `discovery_questions` and `active_profile` from config. Map profile to depth:

  | Profile | Depth | Questions |
  | --------- | ------- | ----------- |
  | yolo | skip | 0 |
  | prototype | quick | 1-2 |
  | default | standard | 3-5 |
  | production | thorough | 5-8 |

  If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)**: Behavior depends on DISCOVERY_DEPTH:
  - **B2.1: Domain Research (if not skip):** If DISCOVERY_DEPTH != skip:

    **Research setup (steps 1-4):**
    **Step 1:** Extract domain from user's project description (the $NAME or $DESCRIPTION from B1)
    **Step 2:** Follow `references/agent-spawn-protocol.md`. Do not resolve model, effort, or turns separately. The generic generator prints the validated Agent-call parameters.
    **Step 3:** Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
    **Step 3.25:** If one or more skills were preselected, run `bash "/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the bootstrap domain-research Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
     Render the prompt prefix from `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
    **Step 4:** Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research topic, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.

    **Research execution (steps 5-8):**
    **Step 5:** Issue a solo `scout` command contract for job `bootstrap domain research` with `.lbwc-planning/domain-research.md` as the exact write allowance. Run the generic `scripts/agent-generator.sh scout` call from `references/agent-spawn-protocol.md`, advance the contract to `dispatched`, and capture its `SPAWN_READY` name. Stop and report any contract or generator failure verbatim.
    **Step 6:** Spawn the generated Scout with the exact Agent-call parameters printed by the generator. Prompt: "Research the {domain} domain. Write findings to <output_path>.lbwc-planning/domain-research.md</output_path> with ## Table Stakes, ## Common Pitfalls, ## Architecture Patterns, and ## Competitor Landscape. Use relevant MCP tools or WebSearch. Keep each section to 2-3 bullets."
    **Step 7:** Use the generated name for both `subagent_type` and `name`. Omit team and worktree fields. Do not re-resolve or override model, effort, or turns.
    **Step 8:** On success, read `.lbwc-planning/domain-research.md` (Scout wrote it directly). Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    **Step 9:** On failure, log warning "⚠ Domain research timed out, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine**: Read `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - If `.lbwc-planning/codebase/META.md` exists and `discussion_mode` in config is `"assumptions"` or `"auto"`, pass "Discussion mode: assumptions" to the engine. The engine's Step 1.7 will form evidence-backed assumptions from codebase context instead of asking questions from scratch.
    - The engine handles calibration, gray area generation, exploration, and capture. The Recommendation Principle applies during bootstrap: lead with enterprise-standard recommendations for technical decisions, present product decisions equally.
    - Output: `discovery.json` with answered/inferred/deferred arrays.
  - **If skip (yolo profile or discovery_questions=false):** Ask 2 minimal static questions sequentially, with one AskUserQuestion call per question:
    1. "What are the must-have features for this project?" Options: ["Core functionality only", "A few essential features", "Comprehensive feature set"]
    2. "Who will use this?" Options: ["Just me", "Small team (2-10 people)", "Many users (100+)"]
    Record both answers to `.lbwc-planning/discovery.json` as objects in `answered`, preserving each question and response, for example `{"answered":[{"question":"What are the must-have features for this project?","answer":"{answer1}"},{"question":"Who will use this?","answer":"{answer2}"}],"inferred":[],"deferred":[]}`. If either response is unavailable, add that question to `deferred` instead of discarding it.
  - **After discovery (all depths):** Call:
    ```
    bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-requirements.sh .lbwc-planning/REQUIREMENTS.md .lbwc-planning/discovery.json .lbwc-planning/domain-research.md
    ```

- **B3: ROADMAP.md**: Suggest 3-5 phases from requirements. If `.lbwc-planning/codebase/META.md` exists, read PATTERNS.md, ARCHITECTURE.md, and CONCERNS.md (whichever exist) from `.lbwc-planning/codebase/`. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:
  ```
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-roadmap.sh .lbwc-planning/ROADMAP.md "$PROJECT_NAME" /tmp/lbwc-phases.json
  ```
  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md**: Extract project name, milestone name, and phase count from earlier steps. Call:
  ```
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .lbwc-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```
  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary**: If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md**: Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:
  ```
  bash /tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```
  Script handles new file generation (heading + core value + LBWC sections). For existing files, it refreshes only exact canonical LBWC-owned sections already emitted by LBWC, preserves the user's title/intro/arbitrary headings verbatim, and adds `## Code Intelligence` only if no Code Intelligence heading/guidance already exists anywhere in the file. Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Planning commit boundary (conditional)**: Run:
   ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "bootstrap project files" .lbwc-planning/config.json
   else
     echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.lbwc-planning/` + `CLAUDE.md` if changed. Other modes no-op.
- **B8: Transition**: Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.

## Phase 3 Helper Dependencies

The following source helper contracts are not installed in LBWC. They define required behavior above, not available commands. Phase 3 must add each helper or wire the same behavior through a trusted existing LBWC helper before command integration.

- `scripts/bootstrap/bootstrap-claude.sh`
- `scripts/bootstrap/bootstrap-project.sh`
- `scripts/bootstrap/bootstrap-requirements.sh`
- `scripts/bootstrap/bootstrap-roadmap.sh`
- `scripts/bootstrap/bootstrap-state.sh`
- `scripts/extract-skill-follow-up-files.sh`
- `scripts/planning-git.sh`
