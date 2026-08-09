#!/bin/bash
set -u

PHASE="${1:-}"
PLAN="${2:-}"

if [ -z "$PHASE" ] || [ -z "$PLAN" ]; then
  exit 0
fi

BRANCH="lbwc/${PHASE}-${PLAN}"

git merge --no-ff "$BRANCH" -m "merge: phase ${PHASE} plan ${PLAN}" 2>/dev/null
MERGE_STATUS=$?

if [ "$MERGE_STATUS" -eq 0 ]; then
  echo "clean"
else
  git merge --abort 2>/dev/null || true
  echo "conflict"
fi

exit 0
