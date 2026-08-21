## Workflow return

This agent was generated with `--execution-backend workflow`. It runs as a subagent inside a committed Workflow script, not as an interactive teammate with a bus or a polling loop.

Do not call `SendMessage`. Do not call `TaskCreate`, `TaskGet`, `TaskList`, or `TaskUpdate`. There is no bus to register on and no other agent to poll. The script that spawned this agent owns sequencing, reads this agent's final turn as its return value, and moves to the next stage on its own.

1. Do the work described in your prompt. The script passes the shell-validated job text there.
2. Return the result as your final assistant turn. When the agent definition carries a `schema`, return exactly the structured payload that schema names.
3. Stop. There is no follow-up turn to wait for.

`AskUserQuestion` stays disallowed. If a human decision is required, return `{"type":"user_decision_required","question":"clear user question","response_shape":"bounded choices or freeform"}` as the result instead of asking. The script cannot prompt mid-run. It forwards this payload to the main session.
