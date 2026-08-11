# Turbo Routing Profile

Use the `turbo` routing profile for small, well-understood, low-consequence work where speed matters. Keep the task narrow. If the scope grows, touches an external system, or needs broad investigation, switch to a profile that fits the new work before dispatching agents.

Routing profiles choose stored routes. Workflow effort controls command depth and turn scaling. They are separate settings. A command using `turbo` workflow effort does not choose the `turbo` routing profile by itself.

## Role guidance

| Role group | Turbo behavior |
| --- | --- |
| Scope and planning | Confirm the requested change and its boundary without creating speculative work. |
| Implementation | Apply the direct fix or configuration change, with no unrelated refactor. |
| Review and QA | Run the smallest check that proves the changed behavior. |
| Research | Use only evidence needed to complete the immediate task. |
| Debugging | Test one strong hypothesis and report the confirmed root cause. |
| Documentation | Update only documentation affected by the change. |

This guidance does not select a model or reasoning value for a role. The saved `turbo` route does that.

## Use the profile

```sh
scripts/lbwc-model refresh .lbwc-planning
scripts/lbwc-model activate .lbwc-planning turbo
scripts/lbwc-model validate .lbwc-planning
```

Inspect the detected catalog and active routes with `scripts/lbwc-model show .lbwc-planning`. Configure a route only with a selector and reasoning value accepted by that catalog. See `@references/model-profiles.md`.

## Boundaries

`turbo` does not authorize skipping a required command stage, safety check, approval, or user confirmation. Those decisions belong to command contracts. `scripts/resolve-agent-settings.sh` supplies the final validated route at spawn time.
