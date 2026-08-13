---
category: advanced
disable-model-invocation: true
description: Cleanly remove all LBWC traces from the system before plugin uninstall.
argument-hint: "[--check]"
allowed-tools: Read, Write, Edit, Bash, Glob, AskUserQuestion
---

# LBWC Uninstall

## Context

Settings:
```
!`for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; [ -f "$_d/settings.json" ] && cat "$_d/settings.json" 2>/dev/null && break; done || echo "{}"`
```
Planning dir:
```text
!`ls -d .lbwc-planning 2>/dev/null && echo "EXISTS" || echo "NONE"`
```
CLAUDE.md:
```text
!`ls CLAUDE.md 2>/dev/null && echo "EXISTS" || echo "NONE"`
```

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Steps

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set and directory exists), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`.

### Step 1: Confirm intent

Display Phase Banner "LBWC Uninstall" explaining system-level config removal. Project files handled separately. Ask confirmation.

### Step 2: Clean statusLine

Read `CLAUDE_DIR/settings.json`. If statusLine contains `lbwc-statusline`: remove entire statusLine key, display ✓. If not LBWC's: "○ Statusline is not LBWC's , skipped".

### Step 3: Clean Agent Teams env var

If `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` exists: ask user (it's a Claude Code feature other tools may use). Approved: remove (if env then empty, remove env key). Declined: "○ Agent Teams setting kept".

### Step 4: Project data

If `.lbwc-planning/` exists: ask keep (recommended) or delete. Delete: `rm -rf .lbwc-planning/`.

### Step 5: CLAUDE.md cleanup

If CLAUDE.md exists: ask keep or delete.

### Step 6: Summary

Display Phase Banner "LBWC Cleanup Complete" with ✓/○ per step. Then:
```
➜ Final Step
  /plugin uninstall lbwc@lbwc-marketplace
  Then optionally: /plugin marketplace remove lbwc-marketplace
```
**Do NOT run plugin uninstall yourself** , it would remove itself mid-execution.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md , Phase Banner (double-line box), ✓ completed, ○ skipped, Next Up, no ANSI.

## Guard

Require explicit uninstall intent. List every LBWC-owned path before deletion. Do not remove project source, unrelated Claude configuration, or shared third-party state.

## Failure and recovery

On any failed removal, stop and report the exact remaining LBWC path. Never claim a complete uninstall while residue remains.

## Next Up

After verification, instruct the user to remove the plugin through Claude Code plugin management.
