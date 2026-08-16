---
category: lifecycle
disable-model-invocation: true
description: Set up environment, scaffold .lbwc-planning, detect project context, and bootstrap project-defining files.
argument-hint: "none"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, Agent, LSP
---

# LBWC Init

<!-- Full init flow: Steps 0-4 handle environment/scaffold/hooks/mapping/summary -->
<!-- Steps 5-8 handle auto-bootstrap: detect scenario, run inference (brownfield/GSD), confirm with user, generate project files -->

## Shared interaction contract

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Init interaction boundary

Use structured @${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md for bounded bootstrap/config/setup choices. Use intentional freeform/no-options input for project names, requirements, phases, field corrections, and other high-cardinality user-authored content. If `Other` or `Let me explain...` signals freeform intent, follow the shared contract: ask plain text, wait for the response, process it, then resume structured prompts only if another bounded decision remains.

## Context

Working directory (store as `{PROJECT_ROOT}`):

```bash
!`pwd`
```

Plugin root (self-contained, shell variables do not survive across directives):

```bash
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.lbwc-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; LINK=$(bash "$R" --require-script indexer-sync.sh) || exit 1; printf 'Plugin root: %s\n' "$LINK"`
```

Store the returned `Plugin root` value as `{LINK}` and `{plugin-root}` for every later literal helper invocation. Never guess a plugin path or substitute a missing helper with an inline approximation. Replace `{plugin-root}` with that value whenever a step below references a script, template, command, or reference file.

Existing state:

```bash
!`ls -la .lbwc-planning 2>/dev/null || echo "No .lbwc-planning directory"`
```

Project files:

```bash
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml mix.exs 2>/dev/null || echo "No detected project files"`
```

Skills:

```bash
!`if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then _cd="$CLAUDE_CONFIG_DIR"; elif [ -d "$HOME/.config/claude-code" ]; then _cd="$HOME/.config/claude-code"; else _cd="$HOME/.claude"; fi; ls "$_cd/skills/" 2>/dev/null || echo "No global skills"`
```

```bash
!`ls .claude/skills/ 2>/dev/null || echo "No project skills"`
```

## Index freshness gate

Before environment setup, scaffold, or any bootstrap write, run exactly:

```bash
bash "{LINK}/scripts/indexer-sync.sh" --project-root "{PROJECT_ROOT}"
```

This is mandatory. Stop before Guard when the helper exits non-zero.

## Guard

1. **Already initialized:** If .lbwc-planning/config.json exists, STOP: "LBWC is already initialized. Use /lbwc:config to modify settings or /lbwc:vibe to start building."
2. **jq required:** `command -v jq` via Bash. If missing, STOP: "LBWC requires jq. Install: macOS `brew install jq`, Linux `apt install jq`, Manual: <https://jqlang.github.io/jq/download/>. Then re-run /lbwc:init." Do NOT proceed without jq.
3. **Brownfield detection:** Check for existing source files (stop at first match):
   - Git repo: `git ls-files --error-unmatch . 2>/dev/null | head -5`. Any output means BROWNFIELD=true.
   - No git: Glob `**/*.*` excluding `.lbwc-planning/`, `.claude/`, `node_modules/`, `.git/`. Any match means BROWNFIELD=true.
   - All file types count (shell, config, markdown, C++, Rust, CSS, etc.)

## Steps

Agent Teams can always be enabled, but it is not enabled by default. The command `/lbwc:team` owns its explicit consent and restart flow.

<!-- Steps 0-4: Infrastructure setup (environment, scaffold, hooks, mapping, summary) -->

### Step 0: Environment setup (settings.json)

**Required order:** Complete Step 0, including writing `settings.json`, before Step 1. Ask any bounded environment/setup questions, wait for answers, write `settings.json`, then proceed so configuration is stable before scaffold files are created. For native `Other` or freeform setup input, follow the shared interaction contract.

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set, even if directory does not yet exist), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`. Use it for all config paths in this command.

Read `CLAUDE_DIR/settings.json` (create `{}` if missing).

**0a. Detected routing:** Run `bash "{plugin-root}/scripts/lbwc-model" --json refresh .lbwc-planning` after the planning directory exists. Before then, defer routing refresh to Step 1.8. Do not enable experimental source teams or create static model settings.

**0b. Statusline:** Read `statusLine` (may be string or object with `command` field).

| State | Condition | Action |
| ------- | ----------- | -------- |
| HAS_LBWC | Value contains `lbwc-statusline` | Display "✓ Statusline: installed", skip to 0c |
| HAS_OTHER | Non-empty, no `lbwc-statusline` | AskUserQuestion (mention replacement) |
| EMPTY | Missing/null/empty | AskUserQuestion |

AskUserQuestion text: "○ LBWC includes a custom status line showing phase progress, context usage, cost, duration, and more. It updates after every response. Install it?" (If HAS_OTHER, mention existing statusline would be replaced.)

If approved, set `statusLine` to:

```json
{"type": "command", "command": "bash -c 'for _d in \"${CLAUDE_CONFIG_DIR:-}\" \"$HOME/.config/claude-code\" \"$HOME/.claude\"\ndo\n  [ -z \"$_d\" ] && continue\n  f=$(ls -1 \"$_d\"/plugins/cache/lbwc-marketplace/lbwc/*/scripts/lbwc-statusline.sh 2>/dev/null | sort -V | tail -1 || true)\n  [ -f \"$f\" ] && exec bash \"$f\"\ndone'"}
```

Object format with `type`+`command` is **required**: plain string fails silently.
If declined: display "○ Skipped. Run /lbwc:config to install it later."

**0c. Write settings.json** if changed (single write). Display summary:

```text
Environment setup complete:
  {✓ or ○} Statusline {add "(restart to activate)" if newly installed}
  ○ Routing refresh deferred until planning scaffold exists
```

### Step 0.5: External plan redirect

Before scaffold, check for `.planning/` or an explicit external plan path in the invocation. If neither exists, continue silently.

When found, ask one bounded choice: `Import external plan`, `Start fresh initialization`, or `Cancel`.

- `Import external plan`: display `Run /lbwc:import .planning` or the explicit source path, then STOP before creating `.lbwc-planning`.
- `Start fresh initialization`: continue to Step 1 without reading, copying, indexing, or modifying the external source.
- `Cancel`: leave settings and project artifacts unchanged, then STOP.

`/lbwc:import` is the only import authority. Init never copies `.planning`, creates a GSD archive, generates an import index, infers GSD state, or promotes imported artifacts.

### Step 1: Scaffold directory

Read each template from `{plugin-root}/templates/` and write to .lbwc-planning/:

| Target | Source |
| -------- | -------- |
| .lbwc-planning/PROJECT.md | `{plugin-root}/templates/PROJECT.md` |
| .lbwc-planning/REQUIREMENTS.md | `{plugin-root}/templates/REQUIREMENTS.md` |
| .lbwc-planning/ROADMAP.md | `{plugin-root}/templates/ROADMAP.md` |
| .lbwc-planning/STATE.md | `{plugin-root}/templates/STATE.md` |

Create `.lbwc-planning/phases/`, then initialize configuration and detected routing as one fail-closed sequence:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-config.sh" init .lbwc-planning || exit 1
if ! bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-model" refresh .lbwc-planning; then
  printf '%s\n' 'LBWC model catalog and routing refresh failed.' >&2
  exit 1
fi
```

Do not hand-write routing fields. A configuration failure stops before model refresh. A model refresh failure leaves the initialized config available for explicit recovery but stops all later bootstrap writes.

AskUserQuestion (single select):

- "How should LBWC planning artifacts be tracked in git?"
  - `manual` (default): don't auto-ignore the whole `.lbwc-planning/` directory or auto-commit planning files
  - `ignore`: keep the whole `.lbwc-planning/` directory ignored in root `.gitignore`
  - `commit`: track `.lbwc-planning/` + `CLAUDE.md` at helper-backed planning boundaries (bootstrap, planning checkpoints, todo adds, archive)

AskUserQuestion (single select):

- "When should LBWC push commits?"
  - `never` (default)
  - `after_phase` (push once after a phase completes)
  - `always` (push after each commit when upstream exists)

Write selected values to `.lbwc-planning/config.json`:

```bash
jq '.planning_tracking = "'"$PLANNING_TRACKING"'" | .auto_push = "'"$AUTO_PUSH"'"' .lbwc-planning/config.json > .lbwc-planning/config.json.tmp && mv .lbwc-planning/config.json.tmp .lbwc-planning/config.json
```

Then align git ignore behavior with config:

```bash
PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" sync-ignore .lbwc-planning/config.json
else
  echo "⚠ LBWC: planning-git.sh unavailable. Skipping .gitignore sync." >&2
fi
```

This applies any mode-specific root `.gitignore` behavior and keeps `.lbwc-planning/.gitignore` current for transient runtime files in every tracking mode.

### Step 1.5: Install git hooks

1. `git rev-parse --git-dir`: if not a git repo, display "○ Git hooks skipped (not a git repository)" and skip
2. Run `bash "{plugin-root}/scripts/install-hooks.sh"`, display based on output:
   - Contains "Installed": `✓ Git hooks installed (pre-push)`
   - Contains "already installed": `✓ Git hooks (already installed)`

### Step 1.8: Detect and initialize routing profiles

Run `bash "{plugin-root}/scripts/lbwc-model" --json refresh .lbwc-planning`, then `bash "{plugin-root}/scripts/lbwc-model" --json show .lbwc-planning`. These helpers detect the current Claude catalog and install valid built-in routing profiles. Do not read or create static model, price, alias, reasoning, or matrix files.

Show the detected selectors and the built-in `quality`, `balanced`, and `budget` profiles. Ask one bounded question: keep the recommended active profile, choose another detected built-in profile, or defer model setup. Claude Code supplies native Other. Accept Other only when it exactly names a profile returned by `show`.

When the user selects a profile, run `lbwc-model activate .lbwc-planning <profile>` and `lbwc-model validate .lbwc-planning`. On failure, preserve the prior active profile and stop with the helper error. On defer, leave the default installed profile active. A custom profile is configured later through `/lbwc:config` or `/lbwc:profile`, never hand-written during init.

### Step 2: Brownfield detection + discovery

**2a.** If BROWNFIELD=true:

- Count source files by extension (Glob), excluding .lbwc-planning/, node_modules/, .git/, vendor/, dist/, build/, target/, .next/, **pycache**/, .venv/, coverage/
- Store SOURCE_FILE_COUNT. Check for test files, CI/CD, Docker, monorepo indicators.
- Add Codebase Profile to STATE.md.

**2b.** Run `bash "{plugin-root}/scripts/detect-stack.sh" "$(pwd)"`. Save full JSON. Display: `✓ Stack: {comma-separated detected_stack items}`

**2.5. LSP setup (language servers + Claude plugins):**

Run `bash "{plugin-root}/scripts/resolve-lsp.sh"` with the `detected_stack` JSON array from Step 2b and `CLAUDE_DIR/settings.json` path. Capture the JSON output.

If `env_needed=false` AND all plugins have `plugin_enabled=true`: display `✓ LSP: already configured`, skip to 2c.

Otherwise, display detected languages and recommended LSP plugins, then proceed through sub-steps:

**2.5a (env flag):** If `env_needed=true`:

- AskUserQuestion: "○ LSP Tools\n\nEnable LSP tools for Claude Code? This adds ENABLE_LSP_TOOL=1 to settings.json,\ngiving Claude access to goToDefinition, findReferences, and other code navigation tools."
  - Approved: set `env.ENABLE_LSP_TOOL` to `"1"` in `CLAUDE_DIR/settings.json` (same write pattern as Step 0c)
  - Declined: display "○ LSP env flag skipped"

**2.5b (binary check):** For each plugin where `binary_installed=false`:

- If `install_cmd` is not null: AskUserQuestion: "Install {description} language server?\nCommand: `{install_cmd}`"
  - Approved: run command via Bash
  - Declined: display "○ {description}: skipped"
- If `install_cmd` is null (install_url only): display "○ {description}: manual install: {install_url}"

**2.5c (marketplace catalog):** If any plugins have `plugin_enabled=false`:

- Check catalog: `unset CLAUDECODE && claude plugin marketplace list 2>&1 | grep -q "{org}"` (using the `org` from the first pending plugin)
- If catalog missing: AskUserQuestion: "LSP plugins are published on the `{org}` marketplace catalog. Add it?"
  - Approved: run `unset CLAUDECODE && claude plugin marketplace add {org} 2>&1`
  - Declined or fails: display "○ Marketplace catalog not available: skipping plugin installs" and skip 2.5d

**2.5d (plugin install):** For plugins where `plugin_enabled=false`:

- AskUserQuestion: "Install Claude LSP plugins for: {comma-separated descriptions}?"
  - Approved: run `unset CLAUDECODE && claude plugin marketplace update {org} 2>&1` once, then for each: `unset CLAUDECODE && claude plugin install {plugin} 2>&1`
  - Declined: display "○ LSP plugins: skipped"

Display summary: `✓ LSP: {N} language server(s) configured` or `○ LSP: skipped`
If any settings.json changes or plugins installed: display `(restart Claude Code to activate LSP)`

**2c. Codebase mapping (adaptive):**

- Greenfield (BROWNFIELD=false): skip. Display: `○ Greenfield: skipping codebase mapping`
- SOURCE_FILE_COUNT < 200: run map **inline**: read `{plugin-root}/commands/map.md` and follow directly
- SOURCE_FILE_COUNT >= 200: run map **inline** (blocking): display: `◆ Codebase mapping started ({SOURCE_FILE_COUNT} files)`. **Do NOT run in background.** The map MUST complete before proceeding to Step 3.

### Step 3: Convergence: augment and search

**3a.** Verify mapping completed. Display `✓ Codebase mapped ({document-count} documents)`. If skipped (greenfield): proceed immediately.

**3b.** If `.lbwc-planning/codebase/STACK.md` exists, read it and merge additional stack components into detected_stack[].

**3b2. Auto-detect conventions:** If `.lbwc-planning/codebase/PATTERNS.md` exists:

- Read PATTERNS.md, ARCHITECTURE.md, STACK.md, CONCERNS.md
- Extract conventions per `{plugin-root}/commands/teach.md` (Step R2)
- Write `.lbwc-planning/conventions.json`. Display: `✓ {count} conventions auto-detected from codebase`

If greenfield: write `{"conventions": []}`. Display: `○ Conventions: none yet (add with /lbwc:teach)`

**3c. Parallel registry search:** run `npx skills find "<stack-item>"` for ALL detected_stack items **in parallel** (multiple concurrent Bash calls). Deduplicate against installed skills. If detected_stack empty, search by project type. Display results with `(registry)` tag. If the skills CLI is unavailable (npx missing or the command fails), skip the search.

**3d. Unified skill prompt:** Combine curated (from 2b) + registry (from 3c) results into single AskUserQuestion multiSelect. Tag `(curated)` or `(registry)`. Use max 4 visible choices total, including `Skip`. If more than 3 skills are candidates, show the top 3 plus `Skip` and point broader discovery to `/lbwc:skills`. Install selected into the current project: `npx skills add <skill> -y`.

### Step 3.5: Generate bootstrap CLAUDE.md

LBWC needs its rules and state sections in a CLAUDE.md file. /lbwc:vibe regenerates later with project content.

**Brownfield handling:** Read root `CLAUDE.md` via the Read tool.

- **Exists:** The user already has a CLAUDE.md. Do NOT overwrite it and do NOT assume the first heading/core-value lines belong to LBWC. Preserve all user-authored content verbatim. Only refresh exact canonical LBWC-owned sections already emitted by LBWC (`## Active Context`, `## LBWC Rules`, `## Plugin Isolation`) and add `## Code Intelligence` only if no Code Intelligence heading/guidance already exists anywhere in the file. Display `✓ CLAUDE.md (LBWC sections refreshed in place)`.
- **Does not exist:** Create a new `CLAUDE.md` via `bootstrap-claude.sh` during Step 7f. Do NOT hand-compose the file here.

Do not append `## Project Conventions` or `## Commands` to `CLAUDE.md`.

### Step 4: Present summary

Display Phase Banner then file checklist (✓ for each created file).

Then show conditional lines for statusline, codebase mapping, conventions, and skills.

<!-- Steps 5-8: Auto-bootstrap (scenario detection, inference, bootstrap execution, completion) -->
<!-- Auto-bootstrap flow begins here: seamless continuation from infrastructure setup -->

### Step 5: Scenario detection

<!-- Scenario detection uses BROWNFIELD flag (Guard) and codebase/ (Step 2c). -->
<!-- HYBRID is an edge case fallback: should not occur after Step 2c mapping completes -->

Display transition message: `◆ Infrastructure complete. Defining project...`

Detect the initialization scenario based on flags set in earlier steps:

1. **GREENFIELD:** BROWNFIELD=false (set in Guard step). No existing codebase to infer from.
2. **BROWNFIELD:** BROWNFIELD=true AND `.lbwc-planning/codebase/` directory exists (created in Step 2c mapping). Has codebase context to infer from.
3. **HYBRID:** BROWNFIELD=true but `.lbwc-planning/codebase/` does not exist. This should not occur after Step 2c. Handle it as GREENFIELD.

Check conditions in order:

```bash
if [ "$BROWNFIELD" = "true" ] && [ -d .lbwc-planning/codebase ]; then SCENARIO=BROWNFIELD
elif [ "$BROWNFIELD" = "true" ]; then SCENARIO=HYBRID
else SCENARIO=GREENFIELD
fi
```

Display the detected scenario:

```text
- GREENFIELD: `○ Scenario: Greenfield (new project)`
```

```text
- BROWNFIELD: `◆ Scenario: Brownfield (existing codebase detected)`
```

```text
- HYBRID: `○ Scenario: Hybrid (treating as greenfield, no mapping)`
```

No user interaction in this step. Proceed immediately to Step 6.

### Step 6: Inference & confirmation

<!-- Inference scripts: infer-project-context.sh outputs {name, tech_stack, architecture, purpose, features} -->
<!-- Each field has {value, source} for attribution. Null value = not detected but still displayed (REQ-03) -->
<!-- Confirmation UX: 3 options prevent NL misinterpretation. A field picker handles targeted corrections. -->

Run inference scripts based on the detected scenario, display results, and confirm with the user. Always show inferred data even if fields are null (REQ-03).

**6a. Greenfield branch** (SCENARIO=GREENFIELD or SCENARIO=HYBRID):

- Display: `○ Greenfield: no codebase context to infer`
- Set SKIP_INFERENCE=true
- Skip to Step 7 (discovery questions will be asked inline)

**6b. Brownfield branch** (SCENARIO=BROWNFIELD):

- Run inference: `bash "{plugin-root}/scripts/infer-project-context.sh" .lbwc-planning/codebase/ "$(pwd)"`
- Capture JSON output to `.lbwc-planning/inference.json` via Bash
- Parse the JSON and display inferred fields:

  ```text
  ◆ Inferred project context:
    Name:         {name.value} (source: {name.source})
    Tech stack:   {tech_stack.value | join(", ")} (source: {tech_stack.source})
    Architecture: {architecture.value} (source: {architecture.source})
    Purpose:      {purpose.value} (source: {purpose.source})
    Features:     {features.value | join(", ")} (source: {features.source})
  ```

- For null fields, always display: `{field}: (not detected)`

**6d. Confirmation UX** (all non-greenfield scenarios):

Use AskUserQuestion to confirm inferred data:

"Does this look right?"

Options:

- **"Yes, looks right"** → Proceed to Step 7 with inferred data as-is
- **"Close, but needs adjustments"** → Enter correction flow (6e)
- **"Define from scratch"** → Set SKIP_INFERENCE=true, proceed to Step 7

**6e. Correction flow** (when user picks "Close, but needs adjustments"):

Display all fields as a numbered list. Ask as intentional freeform/no-options input: "Which fields would you like to correct?" Enter comma-separated field numbers (for example, 1,3,5). This is freeform input. In this flow, do not format the field list as a structured options array.

For each selected field, use AskUserQuestion to ask the user for the corrected value. Update the inference JSON with corrected values.

After all corrections, display updated summary and proceed to Step 7 with corrected data.

Write the final confirmed/corrected data to `.lbwc-planning/inference.json` for Step 7 consumption.

### Step 7: Bootstrap execution

<!-- Bootstrap scripts expect specific argument formats: see each script's usage header -->
<!-- bootstrap-project.sh: OUTPUT_PATH NAME DESCRIPTION -->
<!-- bootstrap-requirements.sh: OUTPUT_PATH DISCOVERY_JSON_PATH (discovery.json: {answered[], inferred[]}) -->
<!-- bootstrap-roadmap.sh: OUTPUT_PATH PROJECT_NAME PHASES_JSON (phases.json: [{name, goal, requirements[], success_criteria[]}]) -->
<!-- bootstrap-state.sh: OUTPUT_PATH PROJECT_NAME MILESTONE_NAME PHASE_COUNT -->
<!-- bootstrap-claude.sh: OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH] -->
<!-- Temporary JSON files (discovery.json, phases.json, inference.json) are cleaned up in 7g -->

Generate all project-defining files using confirmed data from Step 6 or discovery questions.

Display: `◆ Generating project files...`

**7a. Gather project data:**

If SKIP_INFERENCE=true (greenfield or user chose "Define from scratch"):

- Ask intentional freeform/no-options discovery questions:
  1. "What is your project name?"
  2. "Describe your project in one sentence."
  3. "What are the key requirements? (one per line)"
  4. "What phases do you envision? For each, give a name and goal. (e.g., 'Auth: User login and registration')"
- Store answers for bootstrap script input

If SKIP_INFERENCE=false (confirmed/corrected inference data):

- Read `.lbwc-planning/inference.json` to get confirmed project context
- Extract: NAME from `name.value`, DESCRIPTION from `purpose.value`
- Ask intentional freeform/no-options questions for any remaining user-authored content not covered by inference:
  1. "What are the key requirements?" (pre-fill from inferred features if available)
  2. "What phases do you envision?" (pre-fill from GSD recent_phases if available)

**7b. Generate PROJECT.md:**

- Run: `bash "{plugin-root}/scripts/bootstrap/bootstrap-project.sh" .lbwc-planning/PROJECT.md "$NAME" "$DESCRIPTION"`
- Display: `✓ PROJECT.md`

**7c. Generate discovery.json and phases.json through a contracted Architect:**

Follow `{plugin-root}/references/agent-spawn-protocol.md`. Build one complete brief from the gathered project data in 7a. Issue a solo, read-only `architect` command contract for `initial requirements and roadmap`. Run generic `scripts/agent-generator.sh architect` with the identical brief, contract path, and task id. The generator routes through detected `lbwc-model` configuration. Advance the contract to `dispatched`. Spawn only with the emitted `model` and final `SPAWN_READY` name as `subagent_type` and `name`.

Render the prompt prefix through `{plugin-root}/references/skill-activation-payload.md`. Ask the Architect to return exactly two complete JSON values in its report: discovery data shaped as `{"answered": [requirement strings], "inferred": [{"text":..., "priority":"Must-have"}]}` and phases shaped as `[{"name":..., "goal":..., "requirements":[...], "success_criteria":[...]}]`. The Architect is read-only and returns content and evidence only. It does not create, edit, stage, commit, or write planning files.

Apply the no-tool invariant from `references/subagent-contracts.md`. Validate both JSON values, unique phase names, nonempty goals and success criteria, requirement coverage, and dependency order. The main session writes `.lbwc-planning/discovery.json` and `.lbwc-planning/phases.json` atomically only after validation. A malformed or incomplete return stops before 7d and leaves existing artifacts unchanged.

Display `◆ Spawning Architect agent...` followed by `✓ Architect agent complete` only after validation and persistence.

**7d. Generate REQUIREMENTS.md and ROADMAP.md:**

- Run: `bash "{plugin-root}/scripts/bootstrap/bootstrap-requirements.sh" .lbwc-planning/REQUIREMENTS.md .lbwc-planning/discovery.json`
- Display: `✓ REQUIREMENTS.md`
- Run: `bash "{plugin-root}/scripts/bootstrap/bootstrap-roadmap.sh" .lbwc-planning/ROADMAP.md "$NAME" .lbwc-planning/phases.json`
- Display: `✓ ROADMAP.md`

**7e. Generate STATE.md:**

- Determine MILESTONE_NAME: use NAME or first milestone from GSD inference
- Determine PHASE_COUNT from phases.json length
- Run: `bash "{plugin-root}/scripts/bootstrap/bootstrap-state.sh" .lbwc-planning/STATE.md "$NAME" "$MILESTONE_NAME" "$PHASE_COUNT"`
- Display: `✓ STATE.md`

**7f. Generate/update CLAUDE.md:**

- Extract `CORE_VALUE` from `.lbwc-planning/PROJECT.md` (`grep -m1 '^\*\*Core value:\*\*' .lbwc-planning/PROJECT.md | sed 's/^\*\*Core value:\*\* *//'`)
- If root CLAUDE.md exists: pass it as EXISTING_PATH to preserve non-LBWC content
- Run: `bash "{plugin-root}/scripts/bootstrap/bootstrap-claude.sh" CLAUDE.md "$NAME" "$CORE_VALUE" "CLAUDE.md"`
  - If CLAUDE.md does not exist yet, omit the last argument
- Display: `✓ CLAUDE.md`

**7g. Cleanup temporary files:**

- Remove `.lbwc-planning/discovery.json`, `.lbwc-planning/phases.json`, `.lbwc-planning/inference.json`, `.lbwc-planning/gsd-inference.json` (if they exist)
- These are intermediate build artifacts, not project state

**7h. Planning commit boundary (conditional):**

- Run:

  ```bash
  PG_SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
  if [ -f "$PG_SCRIPT" ]; then
    bash "$PG_SCRIPT" commit-boundary "bootstrap project files" .lbwc-planning/config.json
  else
    echo "⚠ LBWC: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
  fi
  ```

- Behavior:
  - `planning_tracking=commit`: stages `.lbwc-planning/` + `CLAUDE.md` and commits if there are changes
  - `planning_tracking=manual|ignore`: no-op
  - If `auto_push=always`, pushes when branch has an upstream

### Step 8: Completion summary

<!-- Final summary replaces old Step 4 auto-launch of /lbwc:vibe -->
<!-- User now has full project-defining files and can run /lbwc:vibe when ready -->

Display a banner per @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md with the title "LBWC Initialization Complete".

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LBWC Initialization Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**File checklist:** Display all created or updated files.

**Core project artifacts:**

- `✓ .lbwc-planning/PROJECT.md`
- `✓ .lbwc-planning/REQUIREMENTS.md`
- `✓ .lbwc-planning/ROADMAP.md`
- `✓ .lbwc-planning/STATE.md`

**Configuration and instructions:**

- `✓ CLAUDE.md`
- `✓ .lbwc-planning/config.json`

**Conditional artifacts:**

- If planning_tracking=commit and changes existed: `✓ Bootstrap planning artifacts committed`
- If BROWNFIELD=true: `✓ Codebase mapped`

**Next steps:**

```text
➜ Next: Run /lbwc:vibe to start planning your first milestone
  Or:   Run /lbwc:status to review project state
```

## Failure and recovery

If `lbwc-model`, task-contract, or agent-generator fails, stop and show its error verbatim. Do not substitute a static model file, role-specific generator, source team, or unsupported Agent field. If the Architect response fails validation, leave project-defining artifacts unchanged, report the rejected value, and ask the user to retry or provide corrected freeform input under the shared interaction contract.

## Next Up

```text
➜ Next Up
  /lbwc:vibe - start planning the first milestone
  /lbwc:status - review project state
```

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md

Use a Phase Banner (double-line box), File Checklist (✓), ○ for pending, Next Up Block, and no ANSI color codes.
