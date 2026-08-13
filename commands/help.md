---
category: supporting
disable-model-invocation: true
description: Display all available LBWC commands with descriptions and usage examples.
argument-hint: "[command-name]"
allowed-tools: Read, Glob, Bash
---

# LBWC Help $ARGUMENTS

## Context

Plugin root:

```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "LBWC: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in command lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a command file.

## Behavior

### No args: Display all commands

Run the help output script and display the result exactly as-is (pre-formatted terminal output):

```
!`L="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/help-output.sh" || echo "LBWC: help-output.sh failed , run /lbwc:doctor for diagnostics"`
```

Display the output above verbatim. Do not reformat, summarize, or add commentary. The script dynamically reads all command files and generates grouped output.

### With arg: Display specific command details

Strip the `lbwc:` prefix from `{name}` if present, validate the remainder as a command slug, then read `{plugin-root}/commands/{name}.md`. Display:

- **Name** from the command filename and **description** from frontmatter
- **Category** from frontmatter
- **Usage:** `/lbwc:{name} {argument-hint}`
- **Arguments:** list from argument-hint with brief explanation
- **Related:** suggest 1-2 related commands based on category

If command not found: "⚠ Unknown command: {name}. Run /lbwc:help for all commands."

## Guard

Read only shipped command metadata. Do not execute the command being described.

## Output Format

Show the matching LBWC command, one-line purpose, arguments, and one example.

## Next Up

The displayed command is the only next action.
