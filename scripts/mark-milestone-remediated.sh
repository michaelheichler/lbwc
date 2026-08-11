#!/usr/bin/env bash
set -euo pipefail


PLANNING_DIR="${1:-}"
PHASE_DIRS_PIPE="${2:-}"

if [[ -z "$PLANNING_DIR" || -z "$PHASE_DIRS_PIPE" ]]; then
  echo "Usage: mark-milestone-remediated.sh PLANNING_DIR PHASE_DIRS_PIPE" >&2
  exit 1
fi

if [[ ! -d "$PLANNING_DIR" ]]; then
  echo "Error: planning dir not found: $PLANNING_DIR" >&2
  exit 1
fi

MARKED_COUNT=0
SKIPPED_COUNT=0

IFS='|' read -ra PHASE_DIRS <<< "$PHASE_DIRS_PIPE"
for raw_dir in "${PHASE_DIRS[@]}"; do
  dir="${raw_dir%/}"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  case "$dir" in
    "$PLANNING_DIR"/milestones/*/phases/*)
      ;;
    *)
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      continue
      ;;
  esac

  printf '%s\n' "acknowledged:start-fresh" > "$dir/.remediated"
  MARKED_COUNT=$((MARKED_COUNT + 1))
done

echo "marked_count=$MARKED_COUNT"
echo "skipped_count=$SKIPPED_COUNT"

exit 0
