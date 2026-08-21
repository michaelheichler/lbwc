---
category: advanced
disable-model-invocation: true
description: Produce a structured codebase map from inline analysis and Scout evidence.
argument-hint: "[--incremental] [--package=name] [--tier=solo|duo|quad]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, Skill, LSP, AskUserQuestion, Workflow
---

# LBWC Map: $ARGUMENTS

## Context

Working directory:

```text
!`pwd`
```

Plugin root:

```text
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store that value as `{plugin-root}`. Read `{plugin-root}/references/agent-spawn-protocol.md` before any Scout spawn.

Existing mapping:

```text
!`ls .lbwc-planning/codebase/ 2>/dev/null || echo "No codebase mapping found"`
```

META.md:

```text
!`cat .lbwc-planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```

Project files:

```text
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"`
```

Git HEAD:

```text
!`git rev-parse HEAD 2>/dev/null || echo "no-git"`
```

## Workflow capability gate

Refresh the saved Claude capability catalog before any Scout contract or spawn:

```bash
bash "{plugin-root}/scripts/lbwc-model" refresh .lbwc-planning
```

This persists workflow-backend availability as `.workflow` on `.lbwc-planning/claude-capabilities.json`, the authority the execution-mode choice in Step 3 reads before offering or resolving `workflow`. A non-zero exit here does not stop mapping. It leaves `RESOLVED_BACKEND` at `in_process`, so mapping proceeds on whatever catalog already exists. Only a run that goes on to request or choose `workflow` can still be blocked, by step 0 of `workflow-spawn-protocol.md` and by `workflow-generator.sh`'s own live re-validation at generation time. Skip this gate when `.lbwc-planning/` is missing. Do not create a planning directory here.

## Guard

1. If `.lbwc-planning/` is absent, STOP: `Run /lbwc:init first.`
2. If the project has no source files, STOP: `No source code found to map.`
3. If Git is unavailable, warn that incremental mapping is disabled and continue in full mode.
4. Parse only `--incremental`, `--package=name`, and `--tier=solo|duo|quad`. STOP on another flag or an invalid tier.

## Steps

### Step 1: Parse arguments and detect mode

Use `--incremental` when supplied. Otherwise compare `META.md` `git_hash` with HEAD when both exist. Fewer than 20 percent changed source files selects incremental mode. All other cases select full mode. Store `MAPPING_MODE` and `CHANGED_FILES`.

### Step 1.5: Size codebase and select tier

Count source files, excluding `.lbwc-planning/`, `node_modules/`, `.git/`, `vendor/`, `dist/`, `build/`, `target/`, `.next/`, `__pycache__/`, `.venv/`, and `coverage/`. Scope the count to `--package` when supplied.

| Tier | Files | Strategy | Scouts |
| --- | ---: | --- | ---: |
| solo | under 200 | Main session maps inline | 0 |
| duo | 200 to 1000 | Two read-only Scouts return evidence | 2 |
| quad | 1000 or more | Four read-only Scouts return evidence | 4 |

A valid `--tier` overrides the detected tier. Display `◆ Sizing: {SOURCE_FILE_COUNT} source files, {tier} mode`.

### Step 2: Detect monorepo

Check `lerna.json`, `pnpm-workspace.yaml`, workspace manifests, and distinct build roots. Scope to `--package` when supplied. Record whether the project is a monorepo.

### Map Document Format

Every document written by the main session uses these required headings and shapes. Do not rename them.

**STACK.md:**

```markdown
# Stack

## Purpose

{First non-empty paragraph describing the product purpose.}

## Languages

| Language | Evidence |
| --- | --- |
| {Language} | {Files or tooling that establish its use} |

## Key Technologies

- **{Technology}**: {Role and evidence}
```

**ARCHITECTURE.md:**

```markdown
# Architecture

## Overview

{First non-empty paragraph summarizing the architecture.}
```

**INDEX.md:**

```markdown
# Codebase Map Index

## Cross-Cutting Themes

- **{Theme}**: {Description}
```

**META.md:**

```yaml
# Codebase Map META

mapped_at: {UTC ISO 8601 timestamp}
git_hash: {Full git HEAD hash or no-git}
file_count: {Positive SOURCE_FILE_COUNT integer}
mode: {full or incremental}
monorepo: {true or false}
mapping_tier: {solo, duo, or quad}
mcp_tools_used: {Comma-separated tool names or none}
documents:
  - STACK.md
  - DEPENDENCIES.md
  - ARCHITECTURE.md
  - STRUCTURE.md
  - CONVENTIONS.md
  - TESTING.md
  - CONCERNS.md
  - INDEX.md
  - PATTERNS.md
```

Top-level META keys begin in column one.

### Step 3: Execute mapping (tier-branched)

**Scout pre-spawn evaluation (duo and quad only):** Before composing each Scout brief, evaluate installed skills visible in system context. Derive the relevant technical domains from the project files, package metadata, existing map, and assigned mapping domain. Select all materially helpful direct and narrowly adjacent skills, not just the single most obvious skill, and state the outcome before spawning.

The Scout prompt must begin with exactly one rendered `<skill_activation>` or `<skill_no_activation>` block. For selected skills, run:

```bash
bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true
```

Render `{plugin-root}/references/skill-activation-payload.md` with the ordered `skill_calls`, the task-specific `no_skill_reason` when none were selected, and any helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt. After calling `Skill(...)`, read only relevant follow-up files named by the skill or helper. Do not paste the template path, variables, or unresolved `@` include into the prompt.

Also evaluate available MCP tools in the system context before each Scout spawn. Note relevant documentation, search, code-analysis, or domain-data MCP tools in the Scout brief and tell it to prefer those tools for matching lookups over generic WebFetch/WebSearch. Do not name a tool that is not available.

Use this prompt structure after the rendered skill block:

```text
<task_context>
Map domain: {exact assigned domain}.
Project root: {pwd}.
Project context: {relevant PROJECT.md, package, and existing META.md facts}.
MCP tools evaluated: {relevant available tools, or "none"}.
</task_context>

<research_scope>
Return only cited evidence for {exact assigned domain}. Include file paths,
concrete observations, uncertainty, and contradictions. Do not edit, create,
commit, or stage map artifacts.
</research_scope>
```

**Step 3-solo:** Analyze stack, dependencies, architecture, structure, conventions, testing, and concerns inline. The main session writes all seven domain documents under `.lbwc-planning/codebase/`.

**Choose the execution backend (duo and quad only):** Solo-tier mapping analyzes inline and spawns no Scout, so this choice never applies to it. For duo and quad, follow step 0 of `{plugin-root}/references/workflow-spawn-protocol.md`, with `<control-root>` bound to `.lbwc-planning`. Use these literal `AskUserQuestion` fields when that step's `ask` branch applies:

- header: `Map execution`
- question: `Where should Scout evidence gathering run? Workflow run orchestrates each Scout through a committed background script. Native spawn keeps the current multi-agent Scout spawn.`
- options:
  - `Workflow run`: Gather evidence through committed workflow scripts in the background.
  - `Native spawn`: Keep the current native Scout spawn.
  - `Cancel mapping`: Do not map this codebase now.

**Step 3-duo:** When `RESOLVED_BACKEND` is `in_process`, create two shell-issued, read-only Scout contracts, one for tech and architecture and one for quality and concerns. Use the identical brief, contract path, and task id with generic `scripts/agent-generator.sh scout`, then advance each contract to `dispatched`. Spawn only with the emitted `model` and `SPAWN_READY` name as `subagent_type` and `name`, as required by `references/agent-spawn-protocol.md`. Do not grant a write allowance. Each Scout returns cited evidence and proposed content in its report. The main session validates and writes every map document.

When `RESOLVED_BACKEND` is `workflow`, follow `{plugin-root}/references/workflow-spawn-protocol.md` for `DOMAINS=("tech-and-architecture" "quality-and-concerns")`. Scout's default role permits `Write`, so a schema 3 contract for it requires either a granted write capability or an explicit `--read-only-role scout` declaration. No Scout in this command writes any file: issue every contract read-only.

```bash
PROJECT_ROOT=$(pwd)
CONTROL_ROOT="$PROJECT_ROOT/.lbwc-planning"
DOMAINS=("tech-and-architecture" "quality-and-concerns")
CONTRACT_PATHS=(); TASK_IDS=(); SCRIPT_PATHS=()
for DOMAIN in "${DOMAINS[@]}"; do
  SCOUT_BRIEF="map ${DOMAIN} for {package or full codebase}"
  CONTRACT_PATH=$(bash "{plugin-root}/scripts/task-contract.sh" issue "$PROJECT_ROOT" "map-${DOMAIN}" --command map --role scout --team solo --job "$SCOUT_BRIEF" --control-root "$CONTROL_ROOT" --requested-backend workflow --resolved-backend workflow --read-only-role scout) || exit 1
  TASK_ID=$(basename "$CONTRACT_PATH" .json)
  GENERATOR_OUTPUT=$(bash "{plugin-root}/scripts/agent-generator.sh" scout --job "$SCOUT_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --control-root "$CONTROL_ROOT" --execution-backend workflow) || exit 1
  NAME=$(printf '%s\n' "$GENERATOR_OUTPUT" | awk '/^SPAWN_READY/{print $2}')
  WORKFLOW_OUTPUT=$(bash "{plugin-root}/scripts/workflow-generator.sh" solo scout --job "$SCOUT_BRIEF" --contract "$CONTRACT_PATH" --task-id "$TASK_ID" --name "$NAME" --control-root "$CONTROL_ROOT") || exit 1
  bash "{plugin-root}/scripts/task-contract.sh" state "$PROJECT_ROOT" "$TASK_ID" dispatched >/dev/null || exit 1
  CONTRACT_PATHS+=("$CONTRACT_PATH"); TASK_IDS+=("$TASK_ID")
  SCRIPT_PATHS+=("$(printf '%s\n' "$WORKFLOW_OUTPUT" | awk '/^  path:/{print $2}')")
done
```

Read each generation's own `Agent-call parameters:` and `SPAWN_READY <name>` line, captured above as `NAME`, and use only that printed name, never an invented one. Read each script's own `Workflow-call parameters:` block and `WORKFLOW_READY <task-id>` line. Call `Workflow` once per entry in `SCRIPT_PATHS`, passing only that entry's own `scriptPath`. Never pass `script`, and never inline or paraphrase a rendered file into the call. Launch both Scout runs before waiting on either. Wait for every launched run's own terminal result before Step 3.5. A `user_decision_required` result is the only path back to the user for that Scout: ask one bounded `AskUserQuestion` about it. Any other terminal result carries that Scout's evidence report, validated exactly like the `in_process` branch above.

**Step 3-quad:** When `RESOLVED_BACKEND` is `in_process`, create four shell-issued, read-only Scout contracts for stack and dependencies, architecture and structure, conventions and testing, and concerns. Follow the same generic generator and spawn protocol for each contract. Each Scout returns cited evidence and proposed content only. The main session is the sole writer of map artifacts.

When `RESOLVED_BACKEND` is `workflow`, follow the identical loop as Step 3-duo above with `DOMAINS=("stack-and-dependencies" "architecture-and-structure" "conventions-and-testing" "concerns")`, one contract, generation, and workflow script per domain, each issued with `--read-only-role scout`. Launch all four Scout runs before waiting on any of them. Wait for every launched run's own terminal result before Step 3.5. A `user_decision_required` result is the only path back to the user for that Scout: ask one bounded `AskUserQuestion` about it. Any other terminal result carries that Scout's evidence report, validated exactly like the `in_process` branch above.

For every Scout brief, require file paths, concrete evidence, uncertainty, and the exact assigned domains. Do not ask Scouts to create, edit, commit, or stage files. Wait for every report. If a Scout fails, continue only when inline analysis can fill its assigned domain and mark the gap in `INDEX.md` Validation Notes.

### Step 3.5: Verify mapping documents written by Scouts

Scouts return evidence, they do not write map documents. Validate each report against the assigned domain and source paths. The main session writes or repairs these seven documents: `STACK.md`, `DEPENDENCIES.md`, `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `TESTING.md`, and `CONCERNS.md`. Do not write placeholders from an unsupported report.

### Step 4: Synthesize INDEX.md and PATTERNS.md

Read the seven domain documents. The main session writes `INDEX.md` and `PATTERNS.md`, including contradictions, evidence limits, and recurring architectural, naming, quality, concern, and dependency patterns.

### Step 5: Create META.md and present summary

The main session writes `META.md` from the exact template above after all documents validate. Display the mode, tier, created documents, key findings, and evidence gaps.

## Failure and recovery

If contract issuance, generation, or spawning fails, report the helper error verbatim. Do not retry with a hand-written agent, another role, unsupported Agent fields, or a write allowance. Keep existing map artifacts unchanged until a complete replacement document is validated. If a report is incomplete, analyze that domain inline or stop with the missing evidence named.

If the workflow generator fails or a `Workflow` call is denied for a Scout, leave that Scout's contract `planned`, report the failure verbatim, and do not fall back to `in_process`. Analyze that Scout's assigned domain inline instead, or stop with the missing evidence named.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md. Use a Phase Banner, a file checklist, `◆` findings, `⚠` warnings, and no ANSI color codes.

## Next Up

```text
➜ Next Up
  /lbwc:plan {NN} - plan the next phase with this map
  /lbwc:research "topic" - investigate an identified uncertainty
  /lbwc:status - review project state
```
