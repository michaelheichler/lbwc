---
name: lbwc:pause
category: supporting
disable-model-invocation: true
description: Save session notes for next time (state auto-persists).
argument-hint: "[notes]"
allowed-tools: Read, Write
---

# LBWC Pause: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```

## Guard

1. **Not initialized** (no .lbwc-planning/ dir): STOP "Run /lbwc:init first."

## Steps

1. **Write notes:** If $ARGUMENTS has notes: write `.lbwc-planning/RESUME.md` with timestamp + notes + resume hint. If no notes: skip write.
2. **Present:** Phase Banner "Session Paused". Show notes path if saved. "State is always saved in .lbwc-planning/. Nothing to lose, nothing to remember." Next Up: /lbwc:resume.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md , double-line box, ➜ Next Up, no ANSI.

## Next Up

After the pause artifact validates, show `/lbwc:resume` and stop.
