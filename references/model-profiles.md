# Detected Routing Profiles

LBWC does not ship a static model roster, alias table, price table, or reasoning ladder. Claude Code capabilities detected for this installation are the only candidates that may be stored or used. This document explains that system. It does not choose a route.

## Authority

| Component | Authority |
| --- | --- |
| `scripts/claude-capabilities.sh` | Detects the installed Claude Code model selectors and accepted reasoning values, then records them in `.lbwc-planning/claude-capabilities.json`. |
| `scripts/lbwc-config.sh` | Creates, migrates, and validates the planning configuration shape. |
| `scripts/lbwc-routing.sh` | Validates stored profile routes against the saved catalog and resolves a role from the active profile. |
| `scripts/lbwc-model` | Provides transactional refresh, display, activation, copy, set, catalog, and validation operations. |
| `scripts/resolve-agent-settings.sh` | Resolves and revalidates the route used by one agent spawn. |

These scripts are the selector and reasoning authority. A command, an orchestrator, and a spawned agent must use their output rather than choose a model or reasoning value by judgment. If this document conflicts with a script result, the script result is correct.

## Canonical profiles

Every planning directory has exactly three routing profiles:

| Profile | Use when |
| --- | --- |
| `quality` | The task has material uncertainty, complexity, or consequence and benefits from the strongest validated route choices. |
| `balanced` | The task is ordinary development work and needs proportionate planning, implementation, and verification. |
| `turbo` | The task is small, well-understood, and low consequence. |

A profile is a set of per-role route cells. Each cell stores a detected model selector, a reasoning value, and a resolved status. Profile names do not imply a particular provider, model, cost, context size, or reasoning level. Inspect the current installation instead of relying on a published table.

`quality`, `balanced`, and `turbo` are routing choices. Workflow effort controls command depth and turn scaling. A workflow effort setting does not select a routing profile, and a routing profile does not permit a command to skip required gates.

## Refresh and inspect

Run these commands from the plugin root with the project planning directory as the target:

```sh
scripts/lbwc-model refresh .lbwc-planning
scripts/lbwc-model show .lbwc-planning
scripts/lbwc-model validate .lbwc-planning
```

Refresh after upgrading Claude Code or when the saved catalog no longer matches the executable. Routing validation rejects a catalog whose recorded executable fingerprint differs from the installed binary.

Use only selectors shown by `scripts/lbwc-model catalog .lbwc-planning` or `show`. To change a route, use the transactional interface:

```sh
scripts/lbwc-model set .lbwc-planning <quality|balanced|turbo> <role> <detected-selector> <reasoning-json>
scripts/lbwc-model copy .lbwc-planning <source-profile> <destination-profile>
scripts/lbwc-model activate .lbwc-planning <quality|balanced|turbo>
```

The setter rejects an unknown role, selector, reasoning value, or selector and reasoning combination. It records the route as resolved only after those checks pass.

## Reasoning values and JSON null

A route's `reasoning` field is either a detected string or JSON `null`.

- JSON `null` means omit the reasoning parameter and let Claude Code use its own default.
- A detected string, including the literal string `"default"` if Claude Code exposes it, is an explicit reasoning value. It must be passed and validated as a string.

Those values are not interchangeable. `null` is a request to use the Claude Code default. `"default"` is a catalog value whose meaning comes from the detected Claude Code installation. Never replace one with the other because their text looks similar.

The catalog can describe global reasoning values or values associated with particular selectors. `scripts/lbwc-routing.sh` enforces either form, and `scripts/resolve-agent-settings.sh` checks again at spawn time.

## Role guidance

Configure routes for the role's task, not a generic model ladder.

| Role group | Routing concern |
| --- | --- |
| Planning, architecture, and debugging | Favor route choices that leave enough room for evidence, dependencies, and root-cause reasoning. |
| Implementation | Favor choices proven adequate for the project's stack, task size, and tool use. |
| Review and QA | Favor independent scrutiny and enough reasoning to check stated requirements. |
| Research | Favor choices that can process the needed source material and report evidence accurately. |
| Documentation | Favor clear, accurate writing that can verify the referenced behavior. |

This is evaluation guidance for an operator reviewing detected choices. It is not permission to invent selectors, use an unlisted value, or bypass validation.

## Compatibility references

`@references/effort-profile-balanced.md` and `@references/effort-profile-turbo.md` describe canonical routing profile use. `@references/effort-profile-fast.md` and `@references/effort-profile-thorough.md` remain only for command contracts that still accept those workflow-effort names.
