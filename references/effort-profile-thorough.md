# Thorough Workflow Compatibility Guide

`thorough` is a workflow-effort compatibility value for command contracts that still accept it. It is not a routing profile and cannot select a model or reasoning value. The canonical routing profiles are `quality`, `balanced`, and `turbo`.

Use `thorough` when the task has material uncertainty, a large blast radius, difficult diagnosis, or high cost of a missed defect. Expand evidence and verification only to the level the risk requires.

| Role group | Thorough workflow guidance |
| --- | --- |
| Scope and planning | Trace requirements, dependencies, risks, and completion evidence before implementation. |
| Implementation | Follow the approved plan and check integration points while changing code. |
| Review and QA | Map checks to requirements and run the relevant regression coverage. |
| Research | Compare primary sources and record unresolved uncertainty. |
| Debugging | Test competing root-cause hypotheses and confirm the fix with a focused regression check. |
| Documentation | Record the operational behavior, limits, and recovery steps that changed. |

The active routing profile still supplies every role's stored selector and reasoning value. Use `scripts/lbwc-model show .lbwc-planning` to inspect it and `scripts/resolve-agent-settings.sh` to resolve it for a spawn. Do not create a `thorough` route or infer a selector from this guide.

If the command contract no longer accepts `thorough`, use one of the canonical routing profiles and the command's current workflow setting instead.
