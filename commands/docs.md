---
description: Standalone documentation job. Spawns one solo docs agent to write or update project documentation.
argument-hint: "<what to document or update>"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

For documentation work that stands alone: READMEs, changelogs, guides, API docs. Documentation bundled inside a feature implementation task stays with that task's engineer under its plan contract, do not route it here.

1. Restate $ARGUMENTS as one concrete documentation job: which files, which audience, what changes. If the target is genuinely unclear, ask one focused question via AskUserQuestion before spawning.
2. Add the codebase-map pointer to the exact brief when a map exists. Issue a solo `/docs` command contract named `docs-{slug}` with every target document as an exact `--write-allowance`. Pass the same brief, contract path, task id, and allowances to the generator. Advance the contract to `dispatched`, then spawn one `docs` agent per `@references/agent-spawn-protocol.md`. If the target paths are not exact, stop and ask one question before issuing the contract.
3. When `docs` returns, you commit the changed documentation files yourself, one commit for the job, message format `docs: {summary}`. `docs` never runs git.
4. If the job was scoped out of an active phase, record one `deviq-record.py decision --phase <phase> --role docs --field summary="..." --field rationale="..."` for any material documentation choice (a new doc structure, a renamed public term). Standalone jobs with no phase skip this.
5. Report the outcome and commit hash. If the job came from a phase, tell the user to continue with `/vibe`.
