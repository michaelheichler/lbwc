# Fast Workflow Compatibility Guide

`fast` is a workflow-effort compatibility value for command contracts that still accept it. It is not a routing profile and cannot select a model or reasoning value. The canonical routing profiles are `quality`, `balanced`, and `turbo`.

Use `fast` only for a well-understood task with a bounded change and a clear check. Keep planning concise, research targeted, implementation narrow, and verification focused on the changed behavior.

| Role group | Fast workflow guidance |
| --- | --- |
| Scope and planning | State the outcome and the one or two facts that make the task safe to start. |
| Implementation | Prefer the existing local pattern over a new abstraction. |
| Review and QA | Verify the changed contract and its nearest regression boundary. |
| Research and debugging | Start with the most likely source or hypothesis, then stop when confirmed. |

The active routing profile still supplies every role's stored selector and reasoning value. Use `scripts/lbwc-model show .lbwc-planning` to inspect it and `scripts/resolve-agent-settings.sh` to resolve it for a spawn. Do not create a `fast` route or infer a selector from this guide.

If the command contract no longer accepts `fast`, use one of the canonical routing profiles and the command's current workflow setting instead.
