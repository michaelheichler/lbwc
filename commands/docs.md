---
category: core
description: Run a standalone documentation job through the contracted docs role.
argument-hint: "<what to document or update>"
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, Agent
disable-model-invocation: true
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

## Context

Use the contracted `docs` role only for standalone documentation work. Feature documentation remains with the task engineer under that task's PLAN contract. The main session owns all user questions, contracts, admission, verification, Git status, staging, commits, and user-facing output. The `docs` worker never runs Git.

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Guard

Require initialized planning state when a phase is named, an exact documentation target path, and a concrete audience and change scope. If the target is genuinely unclear, ask one focused main-session question. Stop before opening a contract when paths are not exact.

## Steps

For documentation work that stands alone: READMEs, changelogs, guides, API docs. Documentation bundled inside a feature implementation task stays with that task's engineer under its plan contract, do not route it here.

1. Restate $ARGUMENTS as one concrete documentation job: which files, which audience, what changes. If the target is genuinely unclear, ask one focused question via AskUserQuestion before spawning.
2. Add the codebase-map pointer to the exact brief when a map exists. Issue a solo `/docs` command contract named `docs-{slug}` with every target document as an exact `--write-allowance`. Pass the same brief, contract path, task id, and allowances to the generator. Advance the contract to `dispatched`, then spawn one `docs` agent per `@references/agent-spawn-protocol.md`. If the target paths are not exact, stop and ask one question before issuing the contract.
3. When `docs` returns, you commit the changed documentation files yourself, one commit for the job, message format `docs: {summary}`. `docs` never runs git.
4. If the job was scoped out of an active phase, record one `deviq-record.py decision --phase <phase> --role docs --field summary="..." --field rationale="..."` for any material documentation choice (a new doc structure, a renamed public term). Standalone jobs with no phase skip this.
5. Report the outcome and commit hash. If the job came from a phase, tell the user to continue with `/vibe`.

## Failure and recovery

If the target, contract, generator, worker result, verification, or main-session Git operation fails, report the exact error and leave planning state unchanged. Keep a failed contract at its observed state. Correct the scoped cause, issue a new contract when required, and retry only the documentation job.

## Output Format

Report the documentation scope, contracted `docs` role, changed files, main-session Git commit hash, and any recorded phase decision.

## Next Up

For phase-scoped work, end with `Next Up: /lbwc:vibe`. For standalone work, end with one concrete continuation chosen from the completed scope.
