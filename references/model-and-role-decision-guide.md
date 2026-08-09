# Model and Role Decision Guide

This document answers one question, fast: at a given pipeline step, which role spawns, which model does it get, what reasoning effort, and why. It is a narrative guide over facts that already live in `config/model-profiles.json`, `config/reasoning-profiles.json`, and the two `scripts/resolve-agent-*.sh` scripts. It does not restate their logic in full, and it is never the thing that decides a model at spawn time. The scripts are.

## Who this is for

- **The orchestrator**, deciding which role to spawn for a pipeline step and wanting to state the expected model and effort before calling `agent-generator.sh`, so a surprising resolution result is recognizable as surprising.
- **A spawned agent**, wanting to understand why it got the model and effort it did, without tracing four files under time pressure.
- **The human operator**, auditing cost or quality tradeoffs across `quality`/`balanced`/`budget` profiles before switching one, or explaining to someone else why the critic on a pair runs a different model family than the engineer it reviews.

## Who this is not for

This is not a config file. Nobody edits a model assignment here. `config/model-profiles.json` and `config/reasoning-profiles.json` are the only places that change what an agent runs on by default, and `scripts/resolve-agent-settings.sh` is the only code that reads them at spawn time. If a value in this document ever disagrees with those three files, the three files are right and this document is stale.

## What this replaces

VBW's own model-selection story is scattered across three places. `config/model-profiles.json` has no narrative, just numbers. A long `docs/wiki/configuration.md` mixes the model story into token budgets, rollout gating, and LSP mapping under one heading. A roster table in `docs/wiki/agent-roles.md` lists permissions and tools per role but never shows the model each role actually gets. A reader who wants "what does Dev run on, and why" has to cross three files and reassemble it themselves. LBWC's roster is also larger: sixteen profile-routed roles across seven provider families, against VBW's eight roles on Claude aliases only. The same scattering would cost more here, not less. This document exists so that question has one answer, in one place, sized to stay scannable: one table for model, one table for effort, and under 250 lines total.

## Pipeline steps and the roles they spawn

Every role below resolves its model through the same three-tier lookup, checked in this order: a CLI flag passed to `agent-generator.sh` at spawn time, then `.lbwc-planning/config.json`'s `roles.<role>.model`, then `config/model-profiles.json[model_profile][role]`. With no CLI flag and no project override, every row's live answer is the profile file, which is what the table below shows. A project that has set `roles.<role>.model` outranks the value shown here, and a CLI flag outranks both. See "Resolution order" below for how that layering actually runs.

| Step | Role(s) spawned | Resolves via | Model family, quality / balanced / budget | Why |
|---|---|---|---|---|
| `/init` | none | n/a | n/a | Pure scaffold, no agent spawns, so no model decision applies. |
| `/vibe` (one-time scope step) | `architect` (solo) | `model_profile` | claude / claude / claude (`fable` / `opus` / `opus`) | Writes the roadmap once per project in a single long session. Staying on Claude at every spend tier keeps that session's behavior predictable. |
| `/plan` | `lead` (solo) | `model_profile` | claude / claude / openai (`fable` / `opus` / `terra`) | Runs a compaction-extended planning session. Stays on Claude except at budget, where a cheaper OpenAI model takes over. |
| `/build`, `coding-dijkstra` anchor | `coding-dijkstra` + `coding-dijkstra-critic` (+ `test-dev` in a trio) | `model_profile` | engineer: claude / claude / claude (`fable` / `opus` / `opus`). critic: openai / openai / openai (`sol` / `sol` / `terra`) | The critic is a different provider family from the engineer at every profile. A Claude-only blind spot in the implementation is less likely to be shared by an OpenAI-family reviewer. |
| `/build`, `python-engineer` anchor | `python-engineer` + `python-critic` (+ `test-dev` in a trio) | `model_profile` | engineer: openai / openai / openai (`luna` throughout). critic: openai / openai / openai (`sol` / `sol` / `terra`) | Engineer and critic share a provider family here, so the split that matters is reasoning effort, not family. The engineer runs at `xhigh` while the critic runs leaner, since it reviews rather than generates. |
| `/build`, `web-engineer` anchor | `web-engineer` + `web-code-critic` (+ `test-dev` in a trio) | `model_profile` | engineer: moonshot / moonshot / openai (`kimi3` / `kimi3` / `luna`). critic: claude / openai / openai (`opus` / `sol` / `terra`) | The critic crosses provider families against its engineer at both quality and balanced, and only converges to the engineer's family at budget. |
| `/build`, trio-only third member | `test-dev` | `model_profile` | openai / openai / openai (`terra` / `terra` / `luna`) | Writes tests in a lane the engineer is denied. Its model tracks cost, not the pairing logic above it. |
| `/qa` | `qa` (solo, read-only) | `model_profile` | claude / claude / claude (`opus` / `opus` / `sonnet`) | The deterministic verification gate every phase must clear. Staying on Claude at every tier keeps its verdict format and tool use consistent regardless of what family built the code under review. |
| `/uat` | none | n/a | n/a | UAT is a human checkpoint by design. `commands/uat.md` forbids delegating it to any agent, so no model question applies here. |
| `/debug` | `debugger` (solo) | `model_profile` | openai / openai / claude (`sol` / `terra` / `sonnet`) | Investigates one bug alone with no subagents allowed. Gets its highest reasoning effort at balanced, even though its model swaps to Claude at budget. |

Roles not shown here: `scout` is profile-routed the same way (`terra` / `elonmusk` / `deepseek-v4-pro`, the widest family spread of any role), but none of the seven steps above spawn it. It backs `/research` and codebase mapping instead.

`docs` and `qa-author` are both valid roles. `resolve-agent-settings.sh` derives its valid-role list from `config/model-profiles.json`'s keys. Both entries exist in all three profiles. `docs` resolves to `sonnet` (`claude-sonnet-5`) at every profile. `qa-author` resolves to `inherit`, a recognized Claude Code value that takes the orchestrator's active model and skips pricing validation. `/docs` uses `docs`. `/build` uses `qa-author` for a TDD red stage. Both routes must issue the shell-owned contract before calling `agent-generator.sh` with `--contract` and `--task-id`.

`lead-critic` has a template (`templates/agent-roles/lead-critic.md.tpl`) and a full row in `config/model-profiles.json` and `config/reasoning-profiles.json`. It pairs with `lead` the same way the other critics pair with their engineers, resolving to `fable` at every profile with `medium` reasoning effort.

## Reasoning effort by role

Effort resolves through the matching three-tier lookup inside `resolve-agent-settings.sh`: a CLI `--reasoning` flag, then `.lbwc-planning/config.json`'s `roles.<role>.effort`, then `reasoning-profiles.json` keyed by the same `model_profile`. With no CLI flag and no project override, these are the live values.

| Role | quality | balanced | budget |
|---|---|---|---|
| `architect` | medium | medium | medium |
| `lead` | medium | medium | high |
| `lead-critic` | medium | medium | medium |
| `coding-dijkstra` | medium | medium | medium |
| `coding-dijkstra-critic` | medium | medium | medium |
| `python-engineer` | xhigh | xhigh | xhigh |
| `python-critic` | medium | medium | high |
| `web-engineer` | medium | medium | medium |
| `web-code-critic` | high | high | high |
| `test-dev` | high | high | high |
| `qa` | medium | medium | medium |
| `debugger` | medium | high | medium |
| `scout` | xhigh | high | medium |
| `docs` | medium | medium | medium |
| `qa-author` | medium | medium | medium |

Effort is not free to set to anything. `resolve-agent-settings.sh` checks the resolved model's `reasoning_efforts` list in `config/model-pricing.json`. It substitutes that model's documented default if the configured value is not on its ladder, or drops the parameter entirely if the model rejects it outright (Claude Haiku 4.5 is the current example, and `inherit` skips the check outright). That clamp runs after model resolution, every time, regardless of what this table says.

## Resolution order, in plain prose

For model, reasoning effort, and max turns alike, `resolve-agent-settings.sh` checks the same three tiers, most specific first:

1. **CLI.** A flag passed straight through from `agent-generator.sh` (`--model`, `--reasoning`, `--max-turns`). Set for one spawn, right now. Wins over everything else.
2. **Project.** `.lbwc-planning/config.json`'s `roles.<role>.model`, `roles.<role>.effort`, or `roles.<role>.max_turns`. A value set for exactly this role, on this project, that persists across spawns until someone edits the file. An optional top-level `model_profile` key here also selects which profile tier 3 reads from.
3. **Profile.** Falls through to `model-profiles.json[model_profile][role]` or `reasoning-profiles.json[model_profile][role]`, where `model_profile` is the project's own `quality`/`balanced`/`budget` setting (default `quality`). This is the tier every table above documents, because a project with no `roles` block and no `model_profile` override has nothing at tiers 1 or 2.

Max turns additionally runs the resolved base value (project override, else `templates/agent-roles/defaults.json`'s `maxTurns` for the role, else a per-role fallback) through a workflow-effort multiplier (`thorough`/`balanced`/`fast`/`turbo`, itself read from `.lbwc-planning/config.json`'s top-level `effort` key). A CLI `--max-turns` flag skips the multiplier and is used exactly as given.

Four project-config keys from an earlier design (`model_overrides`, `model_matrix`, `reasoning_overrides`, `reasoning_matrix`, plus `agent_max_turns`, `model_catalog`, `model_catalog_extra`, and `custom_profiles`) are retired. `resolve-agent-settings.sh` exits 1 and names the replacement key if a project config still has one of these.

`scripts/resolve-agent-settings.sh` is the only code that walks this order. Read it when the exact tie-breaking or clamping logic matters. This document explains what the order means, not how the jq is written.

## Zero-trust note

This document is descriptive. `resolve-agent-settings.sh` is authoritative. Nothing here is permission for an orchestrator or a spawned agent to pick a model or effort by judgment. If a value printed by `agent-generator.sh` at spawn time does not match a row above, the script's output is correct and this document is out of date. Report the mismatch and update this file. Do not override the script's choice to match what this document says it should be.
