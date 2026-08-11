#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""

if [ -z "$ROOT" ] || [ ! -d "$ROOT/.git" ]; then
  exit 0
fi

mkdir -p "$ROOT/.git/hooks"

HOOK_PATH="$ROOT/.git/hooks/pre-push"

HOOK_CONTENT='#!/usr/bin/env bash
set -euo pipefail
SCRIPT="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/pre-push-hook.sh"
if [ -f "$SCRIPT" ]; then
  exec bash "$SCRIPT" "$@"
fi
exit 0'

if [ -f "$HOOK_PATH" ]; then
  if [ -L "$HOOK_PATH" ]; then
    CURRENT_TARGET=$(readlink "$HOOK_PATH")
    if echo "$CURRENT_TARGET" | grep -q "pre-push-hook.sh"; then
      echo "$HOOK_CONTENT" > "$HOOK_PATH"
      chmod +x "$HOOK_PATH"
      echo "Upgraded pre-push hook to standalone script" >&2
    else
      echo "pre-push hook exists but is not managed by LBWC -- skipping" >&2
    fi
  elif grep -qE '(_lbwc_find_script|SCRIPT="/tmp/.lbwc-plugin-root-link-)' "$HOOK_PATH" 2>/dev/null; then
    echo "$HOOK_CONTENT" > "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "Updated pre-push hook" >&2
  else
    echo "pre-push hook exists but is not managed by LBWC -- skipping" >&2
  fi
else
  echo "$HOOK_CONTENT" > "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "Installed pre-push hook" >&2
fi
