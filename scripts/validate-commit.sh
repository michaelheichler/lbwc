#!/bin/bash
set -u

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if ! echo "$COMMAND" | grep -q "git commit"; then
  exit 0
fi

VALID_TYPES="feat|fix|test|refactor|perf|docs|style|chore"

MSG=""
if echo "$COMMAND" | grep -q 'cat <<'; then
  MSG=$(printf '%s\n' "$COMMAND" | sed -n '/cat <</,$ p' | sed '1d' | grep -m1 -E "^($VALID_TYPES)\(.+\): .+" | sed 's/^[[:space:]]*//')
  if [ -z "$MSG" ]; then
    MSG=$(printf '%s\n' "$COMMAND" | sed -n '/cat <</,$ p' | sed '1d' | sed '/^[[:space:]]*$/d' | head -1 | sed 's/^[[:space:]]*//')
  fi
  if [ -z "$MSG" ]; then
    exit 0  # Can't parse heredoc, fail-open
  fi
fi
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$MSG" ] && MSG=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]*'\\([^']*\\)'.*/\\1/p")
  [ -z "$MSG" ] && MSG=$(echo "$COMMAND" | sed -n 's/.*-m[[:space:]]*\([^[:space:]]*\).*/\1/p')
fi

if [ -z "$MSG" ]; then
  exit 0
fi

if ! echo "$MSG" | grep -qE "^($VALID_TYPES)\(.+\): .+"; then
  jq -n --arg msg "$MSG" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Commit message does not match format {type}({scope}): {desc}. Got: " + $msg)
    }
  }'
fi

exit 0
