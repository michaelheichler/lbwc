#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""
if [ -z "$ROOT" ]; then
  echo "WARNING: pre-push hook could not determine repo root, skipping version check" >&2
  exit 0
fi

if [ ! -f "$ROOT/scripts/version-bump.sh" ]; then
  exit 0
fi

if [ ! -f "$ROOT/.claude-plugin/plugin.json" ]; then
  exit 0
fi
PLUGIN_NAME=$(jq -r '.name // ""' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "")
if [ "$PLUGIN_NAME" != "lbwc" ]; then
  exit 0
fi

VERIFY_OUTPUT=$(bash "$ROOT/scripts/version-bump.sh" --verify 2>&1) || {
  echo ""
  echo "ERROR: Push blocked -- version files are out of sync."
  echo ""
  echo "$VERIFY_OUTPUT" | grep -A 10 "MISMATCH"
  echo ""
  echo "  Run: bash scripts/version-bump.sh --verify"
  echo "  to see details, then manually sync the version files."
  echo ""
  exit 1
}

exit 0
