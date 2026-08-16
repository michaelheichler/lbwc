# TMUX Destack and Fault Fixes

Source: destack plan (tmux destack faults). Do not wire vibe/build/team spawn here.

## Phase 1: Foundation

- [ ] Task 1: Fix lock array release
- [ ] Task 2: One clock, no production `NOW_MS`
- [ ] Task 3: Single private-FS implementation

## Phase 2: Identity and registry destack

- [ ] Task 4: Strip `messaging_socket`
- [ ] Task 5: One capability, no pane secrets
- [ ] Task 6: Delete registry-route journal
- [ ] Task 7: One writer, one registration path

## Phase 3: Lifecycle destack and remaining faults

- [ ] Task 8: Replace heartbeat daemon with bind-time heartbeat
- [ ] Task 9: Watchdog timestamps are integer ms
- [ ] Task 10: Delete orchestrator `--cancel`
- [ ] Task 11: Compact without `ls`
- [ ] Task 12: Keep registry lock across external teardown
- [ ] Task 13: Remove production fail-injection env vars

## Phase 4: Config, doctor, honesty

- [x] Task 14: Remove unused tmux config keys
- [x] Task 15: Persist snapshot cancel
- [ ] Task 16: Real doctor tmux helper
- [ ] Task 17: Honest SMOKE rows
