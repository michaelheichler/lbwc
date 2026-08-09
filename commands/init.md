---
description: First-run scaffold. Creates .lbwc-planning/ and writes PROJECT.md, REQUIREMENTS.md, a phase-less ROADMAP.md, and STATE.md. No agent spawn.
argument-hint: "[project idea, or nothing for brownfield detection]"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

Pure orchestrator work. Do not spawn anyone, do not use `@references/agent-spawn-protocol.md`. This command scaffolds, `/vibe`'s scope step spawns `architect` afterward to fill in the roadmap's phases.

If `.lbwc-planning/PROJECT.md` already exists, stop and tell the user to run `/vibe` instead, this project is already initialized.

1. Detect brownfield versus greenfield by checking for existing source files (package manifests, source trees, tests) outside this plugin's own directories. Infer what you can from what you find: language and stack from manifests, an existing README's stated purpose, existing test framework. Do not ask about anything you can read directly from the repo.
2. Ask only for the genuine gray areas $ARGUMENTS and repo inspection did not answer: the project's core value in one sentence if none is stated anywhere, and any explicit stack or constraint choice greenfield work needs before REQUIREMENTS.md can be written. Cap this at 4 questions via AskUserQuestion. Skip a question entirely if the answer is already inferable, asking it anyway is the failure mode this step exists to avoid.
3. Create `.lbwc-planning/` if it does not exist.
4. Write `.lbwc-planning/PROJECT.md` from `templates/PROJECT.md`: name, description, core value, the v1 requirements gathered above under Active, anything explicitly ruled out under Out of Scope.
5. Write `.lbwc-planning/REQUIREMENTS.md` from `templates/REQUIREMENTS.md`, classifying each requirement as table stakes, differentiator, or anti-feature. Skip the Domain Context section entirely if no research was done, do not invent findings to fill it.
6. Write `.lbwc-planning/ROADMAP.md` from `templates/ROADMAP.md` as a bare shell: title and overview sentence only, no `### Phase` sections yet. `/vibe` detects the missing phases and spawns `architect` to fill them in.
7. Write `.lbwc-planning/STATE.md` from `templates/STATE.md` with Phase set to none yet and Status `ready`.
8. Report the four files written and tell the user to run `/vibe` next.
