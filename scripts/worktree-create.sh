#!/bin/bash
set -u


PHASE="${1:-}"
PLAN="${2:-}"
BASE="${3:-}"

if [ -z "$PHASE" ] || [ -z "$PLAN" ]; then
  exit 0
fi

WORKTREE_DIR=".lbwc-worktrees/${PHASE}-${PLAN}"
BRANCH="lbwc/${PHASE}-${PLAN}"

if [ -d "$WORKTREE_DIR" ]; then
  ABS_PATH=$(cd "$WORKTREE_DIR" && pwd)
  echo "$ABS_PATH"
  exit 0
fi

mkdir -p .lbwc-worktrees

GITIGNORE=".gitignore"
if ! grep -qxF ".lbwc-worktrees/" "$GITIGNORE" 2>/dev/null; then
  echo ".lbwc-worktrees/" >> "$GITIGNORE"
fi

if [ -n "$BASE" ]; then
  git worktree add "$WORKTREE_DIR" -b "$BRANCH" "$BASE" 2>/dev/null
  GIT_STATUS=$?
  if [ "$GIT_STATUS" -ne 0 ]; then
    git worktree add "$WORKTREE_DIR" "$BRANCH" 2>/dev/null
    GIT_STATUS=$?
  fi
else
  git worktree add "$WORKTREE_DIR" -b "$BRANCH" 2>/dev/null
  GIT_STATUS=$?
  if [ "$GIT_STATUS" -ne 0 ]; then
    git worktree add "$WORKTREE_DIR" "$BRANCH" 2>/dev/null
    GIT_STATUS=$?
  fi
fi

if [ "$GIT_STATUS" -eq 0 ]; then
  ABS_PATH=$(cd "$WORKTREE_DIR" && pwd)
  echo "$ABS_PATH"
fi

exit 0
