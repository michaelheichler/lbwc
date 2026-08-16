# Option 2 spawn wiring

## Spawn E2E gaps

- [x] Live MAIN_ID from CLAUDE_SESSION_ID, fail closed if empty
- [x] Repository-owned tmux-spawn-group.sh dispatch driver (no model-invented agents JSON or message ids)
- [x] Generated tmux child bus poll, result, and stop loop
- [x] Vibe execute hard branch: tmux driver XOR execute-protocol Agent spawn
- [x] Helper and command markdown tests. Interactive SMOKE rows stay PENDING


## Spawn wiring

- [x] T1: Schema 3 `open` from CLI flags
- [x] T2: Protocol rewrite (destack bind-file + split-group)
- [x] T3: Build tmux spawn branch
- [x] T4: Vibe execute tmux spawn branch
- [x] T5: Team choice then tmux or native
- [x] T6: Init indexer parity
- [x] T7: Honest interactive SMOKE (interactive rows stay PENDING, automated citations only)

## Destack (historical, DONE)

Source: destack plan (tmux destack faults). Do not treat this list as open work.

### Phase 1: Foundation

- [x] Task 1: Fix lock array release
- [x] Task 2: One clock, no production `NOW_MS`
- [x] Task 3: Single private-FS implementation

### Phase 2: Identity and registry destack

- [x] Task 4: Strip `messaging_socket`
- [x] Task 5: One capability, no pane secrets
- [x] Task 6: Delete registry-route journal
- [x] Task 7: One writer, one registration path

### Phase 3: Lifecycle destack and remaining faults

- [x] Task 8: Replace heartbeat daemon with bind-time heartbeat
- [x] Task 9: Watchdog timestamps are integer ms
- [x] Task 10: Delete orchestrator `--cancel`
- [x] Task 11: Compact without `ls`
- [x] Task 12: Keep registry lock across external teardown
- [x] Task 13: Remove production fail-injection env vars

### Phase 4: Config, doctor, honesty

- [x] Task 14: Remove unused tmux config keys
- [x] Task 15: Persist snapshot cancel
- [x] Task 16: Real doctor tmux helper
- [x] Task 17: Honest SMOKE rows
