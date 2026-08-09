---
description: Codebase mapping. Writes .lbwc-planning/codebase/ map documents that every role bootstraps from.
argument-hint: "[--incremental] [--package=name] [--tier=solo|duo|quad]"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

`/map` produces the codebase map under `.lbwc-planning/codebase/` that `architect`, `lead`, `debugger`, `docs`, `qa`, `compile-context.sh`, `post-compact.sh`, and `map-staleness.sh` all consume. Nothing else in the pipeline writes it.

## Guards

1. No `.lbwc-planning/` directory: stop, tell the user to run `/init` first.
2. Not a git repo: warn "Not a git repo, incremental mapping disabled" and continue in full mode.
3. No source files outside this plugin's own directories: stop, "No source code found to map."

## Steps

1. **Parse arguments.** `--incremental` forces incremental refresh, `--package=name` scopes to one monorepo package, `--tier=solo|duo|quad` forces a tier.
2. **Size and tier.** Count source files with Glob, excluding `.lbwc-planning/`, `node_modules/`, `.git/`, `vendor/`, `dist/`, `build/`, `target/`, `.next/`, `__pycache__/`, `.venv/`, `coverage/`. With `--package`, scope the count and everything below to that package directory. Resolve the tier:

   ```bash
   PREFER_TEAMS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/normalize-prefer-teams.sh" .lbwc-planning/config.json 2>/dev/null || echo "auto")
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/map-tiers.sh"
   TIER=$(resolve_map_tier "$SOURCE_FILE_COUNT" "$PREFER_TEAMS" "<forced tier or empty>" | sed 's/^tier=//')
   ```

   `prefer_teams=never` forces solo regardless of count or flag. Display: `Sizing: {count} source files, tier {tier}`.
3. **Mode.** Resolve full versus incremental with the same library:

   ```bash
   eval "$(resolve_map_mode .lbwc-planning "<forced mode or empty>")"   # sets mode=, changed_files=
   ```

   Incremental means META.md exists, its `git_hash` resolves, and fewer than 20% of the mapped files changed since. In incremental mode, re-map only what the changed files touch and rewrite every document's affected sections, never append a second copy of a section.
4. **Execute the mapping, by tier.** Every document below follows the Map Document Format contract, no renamed headings.
   - **solo**: analyze each domain inline and write the files yourself.
   - **duo**: prepare two solo scout briefs with explicit `<output_paths>`. Scout A owns STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, and STRUCTURE.md. Scout B owns CONVENTIONS.md, TESTING.md, and CONCERNS.md.
   - **quad**: prepare four solo scout briefs. Their exact outputs are STACK.md plus DEPENDENCIES.md, ARCHITECTURE.md plus STRUCTURE.md, CONVENTIONS.md plus TESTING.md, and CONCERNS.md.
   - For each scout, issue a solo `/map` command contract named `map-{tier}-{NN}`. Repeat each `.lbwc-planning/codebase/<file>` output as a `--write-allowance`. Pass the same brief, contract path, task id, and allowances to the generator. Advance every contract to `dispatched`, then spawn all admitted scouts per `@references/agent-spawn-protocol.md`.
   - Every brief must state the mapping mode and require the Map Document Format contract in this command.
   - If `.lbwc-planning/MAP-TOOLS.json` exists, read its `recommended_route` and name the corresponding tools in each scout's brief (serena/gitnexus MCP tools, LSP, or plain Grep/Glob) instead of letting each scout re-derive the fallback.

## Verify and synthesize

5. **Verify.** After duo or quad, check that STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md all exist. Write a placeholder from the scout's returned `cross_cutting` findings for any it missed, and note the gap in your report.
6. **Synthesize.** Read the domain documents and write INDEX.md (cross-referenced index, key findings, a Validation Notes section for contradictions) and PATTERNS.md (recurring architectural, naming, quality, and dependency patterns).
7. **Write META.md.** Exactly this shape, top-level keys at column one, no list markers:

   ```yaml
   # Codebase Map META

   mapped_at: {UTC ISO 8601 timestamp}
   git_hash: {full git HEAD hash, or no-git}
   file_count: {positive SOURCE_FILE_COUNT integer}
   mode: {full or incremental}
   monorepo: {true or false}
   mapping_tier: {solo, duo, or quad}
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

   `map-staleness.sh` parses `mapped_at`, `git_hash`, and `file_count` from column one. Any other shape silently reads as `no_map`.
8. **Report.** List the documents written, the tier and mode, and one line of key findings. Tell the user `map-staleness.sh` will now report the map as fresh.

## Map Document Format

Every writer (you inline, or each scout) MUST use these exact level-two headings. Additional sections are allowed. Do not rename the required headings.

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

DEPENDENCIES.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md, and PATTERNS.md use headings suited to their domains.
