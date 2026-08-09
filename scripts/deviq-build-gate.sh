#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN_FILTER="$SCRIPT_DIR/lib/deviq-open-blocks.jq"

ROOT=".lbwc-planning/deviq"
PHASE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      ROOT="${2:?--root requires a value}"
      shift 2
      ;;
    *)
      if [ -n "$PHASE" ]; then
        echo "deviq-build-gate: unexpected argument: $1" >&2
        exit 1
      fi
      PHASE="$1"
      shift
      ;;
  esac
done

if [ -z "$PHASE" ]; then
  echo "usage: deviq-build-gate.sh <phase> [--root <dir>]" >&2
  exit 1
fi

BLOCKS_FILE="$ROOT/blocks.jsonl"

if [ ! -s "$BLOCKS_FILE" ]; then
  exit 0
fi

LINE_NO=0
while IFS= read -r line || [ -n "$line" ]; do
  LINE_NO=$((LINE_NO + 1))
  [ -n "$line" ] || continue
  if ! jq -e . >/dev/null 2>&1 <<< "$line"; then
    echo "deviq blocks.jsonl is malformed at line $LINE_NO, inspect it" >&2
    exit 2
  fi
done < "$BLOCKS_FILE"

OPEN_BLOCKS=$(jq -c --arg phase "$PHASE" 'select(.phase == $phase)' "$BLOCKS_FILE" \
  | jq -s -c -f "$OPEN_FILTER")

OPEN_COUNT=$(jq 'length' <<< "$OPEN_BLOCKS")

if [ "$OPEN_COUNT" -eq 0 ]; then
  exit 0
fi

echo "deviq-build-gate: phase '$PHASE' has $OPEN_COUNT unresolved open block(s):" >&2
jq -r '.[] | "- \(.trigger // ""): \(.consequence // "") (fix: \(.fix // ""))"' <<< "$OPEN_BLOCKS" >&2

exit 2
