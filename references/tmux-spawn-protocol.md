# TMUX Spawn Protocol

Use this protocol only after a frozen runtime snapshot resolves the backend to `tmux`. Native Agent and native team behavior remain authoritative when the snapshot resolves `in_process` or `native`.

1. Run `tmux-preflight.sh` before issuing a TMUX process. Stop on failure unless the frozen snapshot explicitly resolves the permitted in-process fallback.
2. Issue the same schema 3 task contract and generate the same definitions used by the native path. Reject generator metadata that disagrees with the snapshot.
3. Run `tmux-agent-orchestrator.sh provision`, then `split-group`, with the authenticated main capability. The orchestrator creates agent panes only after every runtime record is prepared.
4. Child panes receive capabilities and binding tokens only through their pane environment. Do not pass credentials through `send-keys`, shell history, prompt text, scrollback, or a bus message.
5. A child binds exactly once through `session-start.sh`. Publish and acknowledge jobs through `tmux-bus.sh`; read result, error, and heartbeat messages only as the authenticated main orchestrator.
6. Treat malformed registry, routing, lock, claim, envelope, or binding state as a failure. Do not switch backends or delete runtime state based on malformed data.
7. On cancellation before provision, create no runtime state. On provision or split failure, call `tmux-agent-orchestrator.sh rollback` with the run id and authenticated main capability. Rollback preserves an externally attached tmux session and shuts down only LBWC-owned panes.
8. For normal completion, await result delivery, acknowledge messages, transition lifecycle state, then use `kill-agent` or `kill-session` according to the frozen cleanup policy.
