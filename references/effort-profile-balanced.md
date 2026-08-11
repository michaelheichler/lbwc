# Balanced Routing Profile

Use the `balanced` routing profile for ordinary development work. It is the normal choice when the task needs planning, implementation, and verification without the extra margin appropriate for unusually consequential or uncertain work.

Routing profiles choose stored routes. Workflow effort controls command depth and turn scaling. They are separate settings. A command may use a high or low workflow effort while the active routing profile remains `balanced`.

## Role guidance

| Role group | Balanced behavior |
| --- | --- |
| Scope and planning | Establish the requested outcome, constraints, and completion evidence before work starts. |
| Implementation | Make the smallest complete change that meets the accepted plan. |
| Review and QA | Check the stated requirements, changed paths, and proportionate regression evidence. |
| Research | Gather enough primary evidence to support a decision, then stop. |
| Debugging | Test the most likely explanation first and expand only when evidence requires it. |
| Documentation | Describe the shipped behavior and the commands needed to operate it. |

This guidance does not select a model or reasoning value for a role. The saved `balanced` route does that.

## Use the profile

Refresh the detected Claude Code catalog before configuring routes, especially after a Claude Code update:

```sh
scripts/lbwc-model refresh .lbwc-planning
scripts/lbwc-model activate .lbwc-planning balanced
scripts/lbwc-model validate .lbwc-planning
```

Use `scripts/lbwc-model show .lbwc-planning` to inspect the active routes. Change a route only through `scripts/lbwc-model set` with a selector and reasoning value displayed by the refreshed catalog. `@references/model-profiles.md` defines the catalog, validation, and null reasoning semantics.

## Boundaries

`balanced` is a routing profile, not permission to omit a command's required planning, QA, approval, or user confirmation. Command contracts decide which stages run. `scripts/resolve-agent-settings.sh` resolves the final route for each spawn and its output wins over this document.
