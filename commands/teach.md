---
category: supporting
disable-model-invocation: true
description: View, add, remove, refresh, and reconcile project conventions through the LBWC trusted shell layer.
argument-hint: '["convention text" | remove <id> | refresh | list | group]'
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
---

# LBWC Teach $ARGUMENTS

## Purpose

Manage project conventions without letting the model write `.lbwc-planning/conventions.json` directly. The trusted entrypoint is:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh"
```

All saved entries keep the exact `tag` and `rule` fields consumed by `scripts/compile-context.sh`. Extra source, category, confidence, and detection metadata remain available for people and tools.

The `category` frontmatter field is LBWC metadata. Claude Code does not define it as command behavior.

## Main-session boundary

This command runs only in the Claude Code main session. Generated agents must not invoke this command, modify conventions, answer for the user, or clear a pending decision. They return this blocker to the main session:

```json
{
  "status": "user_decision_required",
  "decision": "convention_change",
  "question": "A clear, non-technical question for the user",
  "choices": ["Two to four bounded choices when applicable"],
  "context": "Why the answer is needed"
}
```

The main session presents that question with `AskUserQuestion` before another convention transition begins.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard and state

1. Confirm `.lbwc-planning/` exists. If it does not, stop with `Run /lbwc:init first.`
2. Never use a legacy planning-state namespace.
3. Never write, edit, redirect to, or replace `.lbwc-planning/conventions.json` directly.
4. Use `lbwc-conventions.sh` for every list, group, add, remove, reconcile, and refresh operation.
5. If the trusted command rejects malformed state, a symbolic link, traversal, conflict, or redundant rule, show its exact error and stop.

## Convention structure

The trusted CLI writes a versioned artifact. The compiler projection remains `tag` plus `rule`:

```json
{
  "schema_version": 1,
  "conventions": [{
    "id": "CONV-001",
    "tag": "FILE-STRUCTURE",
    "rule": "API routes go in src/routes/{resource}.ts",
    "source": "auto-detected",
    "category": "file-structure",
    "confidence": "high",
    "detected_from": "PATTERNS.md",
    "added": "2026-02-10"
  }]
}
```

Sources are `auto-detected` and `user-defined`. Categories are `file-structure`, `naming`, `testing`, `style`, `tooling`, `patterns`, and `other`. Auto-detected confidence is `high`, `medium`, or `low`.

## Display contract

### No arguments, `list`, or `group`

1. Run the trusted list operation:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" list .lbwc-planning
   ```

2. For category-grouped output, run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" group .lbwc-planning
   ```

3. Preserve the readable table headings `ID`, `Category`, `Source`, `Confidence`, and `Rule`. Show totals. Do not replace the table with raw JSON for a person.
4. With no arguments, call `AskUserQuestion`:
   - Header: `Conventions`
   - Question: `What would you like to do with the project conventions?`
   - Choices: `Add a convention`, `Refresh from the codebase` when a map exists, and `Done`
5. Mandatory pause. Do not infer the answer or continue before the user responds.

For deterministic machine use, add `--json` before the operation. The JSON output is compact, sorted, and stable.

## Add a convention

### Parse and classify

Extract one self-contained rule from the text argument. Infer its category from this table:

| Evidence | Category |
|---|---|
| Paths and directories | `file-structure` |
| Casing, names, and prefixes | `naming` |
| Tests, coverage, Vitest, Jest, and pytest | `testing` |
| Formatting, imports, and code style | `style` |
| ESLint, Prettier, pnpm, and other tools | `tooling` |
| Architecture, state, API, and recurring design rules | `patterns` |
| Anything else | `other` |

### Check ambiguity

Compare the proposed rule with every row returned by the trusted `--json list` operation.

- Semantic conflict: show both rules. Call `AskUserQuestion` with `Replace existing`, `Keep both`, and `Cancel`.
- Redundancy: show both versions. Call `AskUserQuestion` with `Replace with new version`, `Add as separate`, and `Cancel`.
- Confirm category: call `AskUserQuestion` with the inferred category marked recommended and two or three plausible alternatives.

Each question covers one decision. Use clear, non-technical wording. Mandatory pause after every `AskUserQuestion`. Dependent questions run sequentially.

### Save through the trusted CLI

For a new rule:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" add .lbwc-planning "<category>" "<rule>"
```

For `Replace existing` or `Replace with new version`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" add .lbwc-planning "<category>" "<rule>" --replace "<id>"
```

For a semantic conflict where the user selects `Keep both`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" add .lbwc-planning "<category>" "<rule>" --conflicts-with "<id>" --keep-both
```

Show the exact success line from the CLI. Then run `list` and show the updated table. Do not add a Project Conventions section to `CLAUDE.md`.

## Remove a convention

### Confirm removal

1. Parse `remove <id>`.
2. Run `--json list` and display the exact matching row.
3. If it does not exist, stop with `Convention not found: <id>`.
4. Call `AskUserQuestion`:
   - Header: `Remove`
   - Question: `Remove <id>: <rule>?`
   - Choices: `Remove convention` and `Keep convention`
5. Mandatory pause.

### Apply removal

Only after `Remove convention`, run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" remove .lbwc-planning "<id>" --yes
   ```

Show the success line and the updated list table.

## Refresh from the codebase

### Read the mapped evidence

If `.lbwc-planning/codebase/` is absent, stop with `No codebase map found. Run /lbwc:map first.` Read only existing copies of `PATTERNS.md`, `ARCHITECTURE.md`, `STACK.md`, and `CONCERNS.md`.

Extract candidate rules using the full evidence contract:

- Rules are specific and observed. `Components use PascalCase` is valid. `Code should be clean` is not.
- `consistently`, `always`, and `all` indicate high confidence.
- `most` and `commonly` indicate medium confidence.
- `some` and `mixed` indicate low confidence.
- Skip low-confidence rules when a higher-confidence rule exists in the same category.
- Maximum 15 auto-detected conventions.
- Every candidate names the source document in `detected_from`.
- When a candidate conflicts with an existing convention, include its ID in `conflicts_with`.

### Reconcile before writing

1. Build an untrusted candidate JSON document in a secure temporary file made with `mktemp`. The document contains `schema_version: 1` and a `conventions` array. Never use the state artifact as the temporary file.
2. Preview the trusted reconciliation:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" reconcile .lbwc-planning "<candidate-file>"
   ```

3. User-defined always win. The trusted reconciliation drops duplicate or conflicting auto detections, removes orphaned auto detections, preserves matching detection IDs, and never changes user-defined rows.
4. Show the preview table and a plain summary of added, updated, removed, and kept rows.

### Decide and apply

1. Call `AskUserQuestion`:
   - Header: `Refresh`
   - Question: `Apply this refreshed convention table?`
   - Choices: `Apply refresh`, `Review candidates`, and `Cancel`
2. Mandatory pause.
3. If the user selects `Review candidates`, show the source, confidence, category, and rule for each candidate. Ask the same refresh question again after the review.
4. If the user selects `Apply refresh`, run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" refresh .lbwc-planning "<candidate-file>"
   ```

5. Show the final table and totals. Remove the temporary candidate file. On `Cancel`, remove the temporary file and leave state unchanged.

## Conflict and redundancy rules

- The model may identify a possible semantic conflict, but it cannot resolve one for the user.
- The trusted CLI rejects a declared conflict until the main session passes the exact user choice.
- The trusted CLI rejects normalized duplicate rules as redundant.
- User-defined conventions win during every refresh and reconcile operation.
- A removed or stale auto-detected rule never causes automatic substitution of a user rule.

## Convention injection

`scripts/compile-context.sh` reads `.lbwc-planning/conventions.json` and emits each exact `tag` and `rule`. QA checks user-defined and high-confidence auto-detected rules. Convention violations are reported as evidence-backed deviations in the phase summary.

## Failure and recovery

| Failure | Result | Recovery |
|---|---|---|
| Malformed current artifact | Command stops, state unchanged | Repair the artifact from a known-good copy, then run `--json list` |
| Malformed candidate input | Refresh stops, state unchanged | Rebuild the temporary candidate file from mapped evidence |
| Symbolic link or traversal | Command stops, state unchanged | Use the physical project `.lbwc-planning` directory |
| Conflict or redundancy | No write occurs | Present the exact bounded choice with `AskUserQuestion` |
| Existing conventions lock | Command stops, state unchanged | Confirm no LBWC convention process is active before removing a stale lock directory |

Never retry by writing the artifact directly. Re-run the same trusted CLI operation after the cause is fixed.

## Verification

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-conventions.sh" --json list .lbwc-planning` and confirm the saved rows.
2. Confirm each row has the intended exact `tag` and `rule` projection.
3. Run the relevant LBWC context build that invokes `compile-context.sh`.
4. Confirm the generated context shows the same convention text.
5. For refresh, compare the final added, updated, removed, and kept counts with the approved preview.

## Output style

Use compact tables and one action per step. Use `Added`, `Removed`, `Refreshed`, `Warning`, and `No change` status labels. Do not use ANSI color. End each completed operation with `Next:` guidance and one concrete action, such as `Next: continue your current LBWC workflow.`
