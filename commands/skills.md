---
name: lbwc:skills
category: supporting
disable-model-invocation: true
description: Inspect installed skills and discover stack-based candidates.
argument-hint: "[--json] [--search <query> | --list | --refresh]"
allowed-tools: Read, AskUserQuestion, Bash("${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" *)
# Tool list:
#   - Read
#   - AskUserQuestion
#   - Bash("${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" *)
---

# LBWC Skills $ARGUMENTS

## Authority

This command runs in the main session only. A generated agent or subagent must not run this flow, install a skill, modify a hook, call an external registry, or change skill state. If an agent needs a skill decision, it returns a `user_decision_required` blocker to the main session.

Claude Code consumes `name`, `description`, `argument-hint`, `allowed-tools`, and `disable-model-invocation` from this header. `category` is LBWC project metadata for organizing commands. Claude Code may ignore that extra field, but LBWC retains it as part of the required command contract.

`${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh` is the only skills discovery interface. Do not parse manifests, edit skill directories, or invoke a package or registry CLI directly. The shell interface reads the existing LBWC stack detector and saved project configuration. It performs no model call, provider lookup, pricing lookup, API-key lookup, or network request.

## Context

Working directory:

```text
!`pwd`
```

Current discovery state:

```text
!`"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" --json list "$(pwd)" 2>&1`
```

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

1. If the shell command fails, stop and report its exact error. Do not replace the result with agent inference.
2. If saved `skill_suggestions` is `false`, show installed skills and stop without asking a discovery question.
3. If saved `discovery_questions` is `false`, show discovered state and stop without asking an installation question.
4. Saved `auto_install_skills: true` never bypasses explicit consent. It records user preference, not shell authority.
5. A malformed detector result, invalid configuration, or unknown candidate fails closed.

## Step 1: Parse arguments

- No arguments: run the full main-session flow.
- `--list`: show installed skills and discovered candidates. Do not ask a question.
- `--refresh`: run the stack detector again, then show the complete refreshed state. Do not ask a question.
- `--search <query>`: search the current detector-provided candidate set. Do not call a remote registry. Do not ask a question.
- `--json` may prefix `--list`, `--refresh`, or `--search`. Return stable JSON unchanged.
- Any install argument is invalid. Installation consent is only accepted through the full main-session flow below.

For deterministic argument use, run exactly one matching shell form:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" list "$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" refresh "$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" search "$(pwd)" "<query>"
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" --json list "$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" --json refresh "$(pwd)"
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" --json search "$(pwd)" "<query>"
```

Stop after returning deterministic output.

## Step 2: Display current state

For the full flow, run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" refresh "$(pwd)"
```

Present its readable tables unchanged. They include:

- saved discovery settings
- detected project stack
- project-installed skills
- globally installed skills for information
- sorted and deduplicated candidates
- the required question mode

Project-installed and global skills remain separate. Never claim a global skill is installed in the project.

## Step 3: Curated suggestions

Use only `candidates[]` from the refreshed JSON result. These values come from the existing LBWC stack detector. Do not invent skill names or descriptions.

- Non-empty candidates: show every candidate in ranked table order.
- Empty candidates with a detected stack: state that no missing mapped skill was found.
- No detected stack and no candidate: state that no stack was detected and suggest `--search <query>` with a concrete stack-related term.
- `skill_suggestions: false`: state that suggestions are disabled and stop.

## Step 4: Search

`--search` filters the current detector-provided candidate set with a case-insensitive literal query. The shell command returns the same stable table or JSON shape as list and refresh.

Remote registry search is outside this release boundary because it would require a network operation and introduce an external trust source. Do not call WebFetch, WebSearch, a package runner, or a registry CLI as a fallback. If local search returns no candidate, say that no validated local candidate matched.

## Step 5: Ask for installation consent

Run this step only in the main session, only with no arguments, and only when both `skill_suggestions` and `discovery_questions` are true. Every question must be clear, self-contained, non-technical, and limited to one decision. Use native AskUserQuestion. After presenting a question, pause for the response.

If the candidate list is empty, stop without AskUserQuestion. The table already explains why there is no decision.

For any bounded question, accept the visible option, its visible number, or an unambiguous phrase anchored to that option. Re-ask the same question only when the answer is ambiguous.

### One candidate

Ask one bounded question:

```text
Header: Skill choice
Question: LBWC found {skill-name} for this project's detected stack. Do you want LBWC to prepare this skill for installation?
Options:
1. Prepare {skill-name} (Recommended)
2. Skip for now
```

Skip means display `No skills selected for installation.` and stop.

### Two to four candidates

Ask one bounded question per skill in table order. Ask them sequentially because each answer changes the selected set.

```text
Header: {skill-name}
Question: LBWC found {skill-name} for this project's detected stack. Do you want to prepare it for installation?
Options:
1. Prepare (Recommended)
2. Skip
```

Collect selected names in table order. If none are selected, display `No skills selected for installation.` and stop.

### More than four candidates

Use native AskUserQuestion with exactly two visible options. Include the complete numbered candidate table in the self-contained question. The native Other path is the freeform number entry route.

```text
Header: Skill selection
Question: LBWC found more than four skill candidates. Choose Skip all, show the table again, or use Other to type comma-separated numbers from this table: {complete numbered table}
Options:
1. Skip all
2. Show the table again
```

Use native Other to type comma-separated numbers. Accept only table numbers from the Other response. Trim surrounding whitespace. Ignore empty tokens caused by a trailing comma. Reject an empty answer, duplicates, non-numeric tokens, and values outside the displayed range. On invalid input, explain the exact invalid token and ask the same two-option question again. `Skip all` ends the flow without a selection. `Show the table again` renders the table, then asks the same two-option question again. Stop only after a valid Other selection or `Skip all`.

## Step 6: Validate the installation handoff

For each selected skill, call the shell-owned validator with the exact candidate name:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lbwc-skills.sh" install "$(pwd)" "<exact-candidate>"
```

The current release validates the candidate, then blocks with status code 3 because completing the installation would require an external registry or network mutation. Treat that specific blocked result as a validated handoff, not as an installed skill. Show the result in a table with candidate, status, and reason.

Do not ask the user to write code or copy a package-runner command. Do not claim success, create `.claude/skills/`, edit hooks, or clear the selection. Report that LBWC preserved the consented candidate for a future trusted installer boundary and made no filesystem or network change.

## Output format

Use plain Markdown tables and short action lines. Use no ANSI formatting. Keep project and global scopes visible. Show exact detector-provided names without translating or shortening them. End with one concrete state line:

- `No installation decision was needed.`
- `No skills selected for installation.`
- `Installation handoff validated. No skill was installed.`

## Next Up

Show `/lbwc:skills --list` as the way to review current state after any search or handoff, then stop.
