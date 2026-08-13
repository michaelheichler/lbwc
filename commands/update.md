---
category: advanced
disable-model-invocation: true
description: Update LBWC to the latest version with automatic cache refresh.
argument-hint: "[--check]"
allowed-tools: Read, Bash, Glob
---

# LBWC Update $ARGUMENTS

## Context

Plugin root:
```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in file/script lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or file in the installed plugin.

**Resolve config directory:** Try in order: env var `CLAUDE_CONFIG_DIR` (if set and directory exists), `~/.config/claude-code` (if exists), otherwise `~/.claude`. Store result as `CLAUDE_DIR`. Use for all config paths below.

## Steps

### Step 1: Read current INSTALLED version

Read the **cached** version (what user actually has installed):
```bash
for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"
do
  [ -z "$_d" ] && continue
  v=$(cat "$_d"/plugins/cache/lbwc-marketplace/lbwc/*/VERSION 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$v" ] && echo "$v" && break
done
```
Store as `old_version`. If empty, fall back to `{plugin-root}/VERSION`.

**CRITICAL:** Do NOT read `{plugin-root}/VERSION` as primary, in dev sessions it resolves to source repo (may be ahead), causing false "already up to date."

### Step 2: Handle --check

If `--check`: display version banner with installed version and STOP.

### Step 3: Check for update

```bash
curl -sf --max-time 5 "https://raw.githubusercontent.com/michaelheichler/vibe-better-with-claude-code-lbwc/main/VERSION"
```
Store as `remote_version`. Curl fails → STOP: "⚠ Could not reach GitHub to check for updates."
If remote == old: display "✓ Already at latest (v{old_version}). Refreshing cache..." Continue to Step 4 for clean cache refresh.

### Step 4: Nuclear cache wipe

```bash
bash "{plugin-root}/scripts/cache-nuke.sh"
```
Removes CLAUDE_DIR/plugins/cache/lbwc-marketplace/lbwc/, CLAUDE_DIR/commands/lbwc/, /tmp/lbwc-* for pristine update.

### Step 5: Perform update

Same version: "Refreshing LBWC v{old_version} cache..." Different: "Updating LBWC v{old_version}..."

**CRITICAL: All `claude plugin` commands MUST be prefixed with `unset CLAUDECODE &&`**, without this, Claude Code detects the parent session's env var and blocks with "cannot be launched inside another Claude Code session."

**Refresh marketplace FIRST** (stale checkout → plugin update re-caches old code):
```bash
unset CLAUDECODE && claude plugin marketplace update lbwc-marketplace 2>&1
```
If fails: "⚠ Marketplace refresh failed, trying update anyway..."

Try in order (stop at first success):
- **A) Platform update:** `unset CLAUDECODE && claude plugin update lbwc@lbwc-marketplace 2>&1`
- **B) Reinstall:** `unset CLAUDECODE && claude plugin uninstall lbwc@lbwc-marketplace 2>&1 && unset CLAUDECODE && claude plugin install lbwc@lbwc-marketplace 2>&1`
- **C) Manual fallback:** display commands for user to run manually, STOP.

**Clean stale global commands** (after A or B succeeds):
```bash
for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"
do
  [ -z "$_d" ] && continue
  rm -rf "$_d/commands/lbwc" 2>/dev/null
done
```
This removes stale copies that break `{plugin-root}` resolution. Commands load from the plugin cache where the resolved plugin root is guaranteed.

### Step 5.5: Ensure LBWC statusline

Read `CLAUDE_DIR/settings.json`, check `statusLine` (string or object .command). If contains `lbwc-statusline`: skip. Otherwise update to:
```json
{"type": "command", "command": "bash -c 'for _d in \"${CLAUDE_CONFIG_DIR:-}\" \"$HOME/.config/claude-code\" \"$HOME/.claude\"\\n do\\n   [ -z \"$_d\" ] && continue\\n   f=$(ls -1 \"$_d\"/plugins/cache/lbwc-marketplace/lbwc/*/scripts/lbwc-statusline.sh 2>/dev/null | sort -V | tail -1 || true)\\n   [ -f \"$f\" ] && exec bash \"$f\"\\n done'"}
```
Use jq to write (backup, update, restore on failure). Display `✓ Statusline restored (restart to activate)` if changed.

### Step 6: Verify update

```bash
NEW_CACHED=$(for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"
do
  [ -z "$_d" ] && continue
  v=$(cat "$_d"/plugins/cache/lbwc-marketplace/lbwc/*/VERSION 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$v" ] && echo "$v" && break
done)
```
Use NEW_CACHED as authoritative version. If empty or equals old_version when it shouldn't: "⚠ Update may not have applied. Try /lbwc:update again after restart."

### Step 7: Display result

Use NEW_CACHED for all display. Same version = "LBWC Cache Refreshed" banner + "Changes active immediately". Different = "LBWC Updated" banner with old→new + "Changes active immediately" + "/lbwc:whats-new" suggestion.

**Edge case:** If Step 6 verification failed (NEW_CACHED empty/unchanged when upgrade expected): keep restart suggestion as diagnostic fallback.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md, double-line box, ✓ success, ⚠ fallback warning, Next Up, no ANSI.

## Guard

`--check` is read-only. Before replacing an installed plugin or statusline, preserve the current version and require the helper rollback boundary. Never push or change project source.

## Next Up

After verification, show `/lbwc:whats-new` and stop.
