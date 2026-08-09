---
description: Standalone or pre-plan research. Spawns one to four scout agents in parallel and writes their findings.
argument-hint: "<research topic, or phase number to research for>"
---

Required first step: read `skills-bundle/ponytail/SKILL.md` under the plugin root (`${CLAUDE_PLUGIN_ROOT}`) and apply the ponytail discipline at level full for the whole task.

1. Decide the target file. If $ARGUMENTS names or clearly maps to an open phase in `.lbwc-planning/ROADMAP.md`, the output is `.lbwc-planning/phases/{NN}-{slug}/RESEARCH.md` from `templates/RESEARCH.md`. Otherwise it is standalone: `.lbwc-planning/STANDALONE-RESEARCH-{slug}.md` from `templates/STANDALONE-RESEARCH.md`, slug derived from the topic.
2. Restate $ARGUMENTS as one or more concrete research questions. Split into separate questions only when the topic is genuinely made of independent sub-questions, up to four. A single focused topic gets one `scout`, do not spawn more agents than there are distinct questions.
3. Give each scout one question as its exact brief. For each question, issue a solo `/research` command contract named `research-{slug}-q{NN}`. Give it the target file as its only `--write-allowance`. Pass the same brief, contract path, task id, and allowance to the generator. Advance each contract to `dispatched`, then spawn the scouts per `@references/agent-spawn-protocol.md`.
4. `scout`'s own role definition already bounds it: WebFetch for public and anonymous HTTP, verified-safe read-only Bash for authenticated checks, no mutating or unverifiable commands, and a required `## Live Validation Evidence` block in its report. Do not relax or restate these as optional in the brief you hand it.
5. Each `scout` writes its own findings directly into the target file (new file, or its own dedicated section if multiple scouts share one file), it never edits work outside that scope.
6. Once every scout reports, consolidate findings, patterns, risks, and recommendations into the target file's sections if any scout left them split across parallel writes. Check that each file's `confidence` frontmatter field (`high`, `medium`, or `low`) reflects what the scout actually found, a scout that could not verify a claim live must not leave `confidence: high` standing. Report the file path and a one-paragraph summary.
