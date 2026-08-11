#!/bin/bash

should_emit_hook_output() {
  local event_name="${1:-}"

  case "$event_name" in
    SessionStart|PreToolUse|PostToolUse|UserPromptSubmit|PreCompact)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  should_emit_hook_output "${1:-}"
  exit $?
fi
