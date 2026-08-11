# Model and Role Decision Guide

This guide explains role purpose and routing boundaries. It does not select a model or reasoning value.

## Routing authority

The detected Claude Code catalog is the only source of valid selectors and reasoning values.

| Component | Responsibility |
| --- | --- |
| `scripts/claude-capabilities.sh` | Detects selectors and reasoning values from the installed Claude Code executable. |
| `scripts/lbwc-model` | Refreshes, displays, validates, activates, copies, and updates routing profiles. |
| `scripts/lbwc-config.sh` | Creates and validates the planning configuration. |
| `scripts/lbwc-routing.sh` | Resolves a role from the active routing profile and validates its stored route against the saved catalog. |
| `scripts/resolve-agent-settings.sh` | Resolves and validates the route immediately before one agent spawn. |

The final resolver output wins. Commands and agents must not infer a selector from a role, a profile name, a benchmark, a provider family, or this document.

## Profiles and workflow effort

The routing profiles are `quality`, `balanced`, and `turbo`. Each profile stores a validated selector and reasoning cell for each routed role. Profile names express the intended task posture, not a fixed model, cost, or reasoning level.

Workflow effort is separate. It controls command depth and turn scaling. It does not pick a routing profile or change a saved route. Commands that still accept `fast` or `thorough` treat them as workflow compatibility values only.

Use the model interface to inspect or change routing:

```sh
scripts/lbwc-model refresh .lbwc-planning
scripts/lbwc-model show .lbwc-planning
scripts/lbwc-model validate .lbwc-planning
```

After a Claude Code update, refresh before dispatching work. A saved catalog that no longer matches the executable is rejected.

## Role guidance

| Role or role group | Purpose | Routing concern |
| --- | --- | --- |
| `architect` | Defines project scope and phases. | Needs enough room to trace requirements, constraints, and dependencies. |
| `lead`, `lead-critic` | Plans phase work and challenges the plan. | Keep the review independent from plan generation where the detected catalog supports it. |
| Engineering roles and critics | Implement a bounded task and review the implementation. | Choose only routes proven adequate for the stack, task size, and required tools. |
| `test-dev`, `qa-author`, `qa` | Create test evidence and verify requirements. | Preserve enough reasoning for requirements, changed paths, and regression evidence. |
| `scout`, `deviq` | Gather source evidence and project guidance. | Choose routes that can process the needed material and report evidence accurately. |
| `debugger` | Establish a root cause and prove the fix. | Reserve enough capacity to test evidence and a focused regression. |
| `ux-oracle` | Evaluates user experience concerns. | Keep its review focused on observable behavior and accessibility evidence. |
| `docs` | Explains shipped behavior and operation. | Use a route that can check referenced behavior before writing. |

A role table does not grant a route. The active profile must contain a resolved route for the role before it can spawn.

## Reasoning semantics

A stored reasoning value is either a detected string or JSON `null`.

- `null` means omit the reasoning parameter and use the Claude Code default.
- A detected string, including `"default"` when the catalog exposes it, is an explicit value and must be passed as a string.

The values are different. Do not replace `null` with `"default"`, or the reverse. `scripts/lbwc-routing.sh` validates stored cells, and `scripts/resolve-agent-settings.sh` validates the route again at spawn time.

## Operating rules

1. Refresh the catalog after a Claude Code update.
2. Inspect detected options before changing a route.
3. Set or activate a route through `scripts/lbwc-model` only.
4. Pass the resolver output unchanged to the agent spawn.
5. Treat an unresolved or rejected route as a stop condition, not a prompt to choose a replacement by judgment.

For route operations and profile semantics, see `@references/model-profiles.md`.
