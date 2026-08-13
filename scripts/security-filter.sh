#!/bin/bash
set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate file path" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

HAS_PATH=$(echo "$INPUT" | jq -r '(.tool_input.file_path != null) or (.tool_input.path != null)' 2>/dev/null) || exit 2

if [ "$HAS_PATH" != "true" ]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || exit 2

if [ -z "$FILE_PATH" ]; then
  exit 2
fi

if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|(^|/)[^/]+\.(pem|key|cert|p12|pfx)(\.[A-Za-z0-9]+)?($|/)|credentials\.json$|secrets\.json$|service-account.*\.json$|(^|/)node_modules/|(^|/)\.git/|(^|/)\.temporary-agent-runfiles/|(^|/)dist/|(^|/)build/'; then
  echo "Blocked: sensitive file ($FILE_PATH)" >&2
  exit 2
fi

exit 0
