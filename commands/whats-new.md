---
name: lbwc:whats-new
category: advanced
disable-model-invocation: true
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# LBWC What's New $ARGUMENTS

## Context

Plugin root:
```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in file lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references VERSION or CHANGELOG.md.

## Guard

1. **Missing changelog:** `{plugin-root}/CHANGELOG.md` missing → STOP: "No CHANGELOG.md found."

## Steps

1. Read `{plugin-root}/VERSION` for current_version.
2. Read `{plugin-root}/CHANGELOG.md`, split by `## [` headings.
   - With version arg: show entries newer than that version.
   - No args: show current version's entry.
3. Display Phase Banner "LBWC Changelog" with version context, entries, Next Up (/lbwc:help). No entries: "✓ No changelog entry found for v{version}."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/lbwc-brand-essentials.md , double-line box, ✓ up-to-date, Next Up, no ANSI.

## Next Up

Show `/lbwc:help` only when the user needs command details. Otherwise stop after the changelog.
