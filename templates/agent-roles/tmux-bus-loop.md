## TMUX bus loop

This agent was generated with `--execution-backend tmux`. After SessionStart bind, follow this loop and then stop.

SessionStart additionalContext includes `lbwc tmux bind:` JSON with `agent_id`, `session_id`, `control_root`, `capability`, and `role`. Use that capability. Do not read pane environment for secrets. Do not register on the bus.

1. Poll `{plugin-root}/scripts/tmux-bus.sh --control-root <control_root> poll --from <agent_id> --agent-id <agent_id> --session-id <session_id> --role agent --capability <capability> --types job`.
2. Parse the job envelope with jq. Claim and ack it using the returned `message_id`.
3. Do the work in `body.brief`.
4. Publish `result` (`{"result":"..."}`) or `error` (`{"message":"..."}`) to the job envelope `from.agent_id` as the bound agent, with `--correlation-id` from the job envelope.
5. Stop.

Resolve plugin-root from `CLAUDE_PLUGIN_ROOT` or `/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID}/scripts/tmux-bus.sh`.
