#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${SCRIPT_DIR}/lib/lbwc-target-root.sh"

PHASE_DIR="${1:-.}"
PLAN_PATH="${2:-}"
PHASE_DIR_EXPLICIT=0
PLAN_PATH_EXPLICIT=0

if [ $# -ge 1 ]; then
  PHASE_DIR_EXPLICIT=1
fi

if [ $# -ge 2 ]; then
  PLAN_PATH_EXPLICIT=1
fi

TARGET_SCOPE_EXPLICIT=0
if [ "$PHASE_DIR_EXPLICIT" -eq 1 ] || [ "$PLAN_PATH_EXPLICIT" -eq 1 ]; then
  TARGET_SCOPE_EXPLICIT=1
fi

TARGET_ROOT=$(lbwc_resolve_target_root "$TARGET_SCOPE_EXPLICIT" "$PLAN_PATH" "$PHASE_DIR" || true)
TARGET_GIT_ROOT=$(lbwc_resolve_target_git_root "$TARGET_SCOPE_EXPLICIT" "$PLAN_PATH" "$PHASE_DIR" || true)
WORKSPACE_SUBPATH=$(lbwc_workspace_subpath_from_git_root "$TARGET_ROOT" "$TARGET_GIT_ROOT" 2>/dev/null || true)

emit_workspace_relative_delta_paths() {
  local path normalized

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    normalized=$(lbwc_git_path_to_workspace_path "$path" "$TARGET_ROOT" "$TARGET_GIT_ROOT" 2>/dev/null || true)
    [ -n "$normalized" ] || continue
    [ "$normalized" = "." ] && continue
    printf '%s\n' "$normalized"
  done | sort -u | grep -v '^$'
}

emit_git_delta_from_worktree() {
  local changed staged

  if [ -n "$WORKSPACE_SUBPATH" ]; then
    changed=$(git -C "$TARGET_GIT_ROOT" diff --name-only HEAD -- "$WORKSPACE_SUBPATH" 2>/dev/null || true)
    staged=$(git -C "$TARGET_GIT_ROOT" diff --name-only --cached -- "$WORKSPACE_SUBPATH" 2>/dev/null || true)
  else
    changed=$(git -C "$TARGET_GIT_ROOT" diff --name-only HEAD 2>/dev/null || true)
    staged=$(git -C "$TARGET_GIT_ROOT" diff --name-only --cached 2>/dev/null || true)
  fi

  [ -n "$changed" ] || [ -n "$staged" ] || return 1
  { printf '%s\n' "$changed"; printf '%s\n' "$staged"; } | emit_workspace_relative_delta_paths
}

emit_git_delta_from_last_tag() {
  local last_tag
  last_tag=$(git -C "$TARGET_GIT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)
  [ -n "$last_tag" ] || return 1

  if [ -n "$WORKSPACE_SUBPATH" ]; then
    git -C "$TARGET_GIT_ROOT" diff --name-only "$last_tag"..HEAD -- "$WORKSPACE_SUBPATH" 2>/dev/null | emit_workspace_relative_delta_paths
  else
    git -C "$TARGET_GIT_ROOT" diff --name-only "$last_tag"..HEAD 2>/dev/null | emit_workspace_relative_delta_paths
  fi
}

emit_git_delta_from_recent_log() {
  if [ -n "$WORKSPACE_SUBPATH" ]; then
    git -C "$TARGET_GIT_ROOT" log --name-only --format= --max-count=5 HEAD -- "$WORKSPACE_SUBPATH" 2>/dev/null | emit_workspace_relative_delta_paths || true
  else
    git -C "$TARGET_GIT_ROOT" log --name-only --format= --max-count=5 HEAD 2>/dev/null | emit_workspace_relative_delta_paths || true
  fi
}

emit_git_delta() {
  emit_git_delta_from_worktree && return 0
  emit_git_delta_from_last_tag && return 0
  emit_git_delta_from_recent_log
}

emit_summary_delta() {
  [ -d "$PHASE_DIR" ] || return 0
  for summary in "$PHASE_DIR"/*-SUMMARY.md; do
    [ -f "$summary" ] || continue
    sed -n '/^## Files Modified/,/^## /p' "$summary" 2>/dev/null | grep '^- ' | sed 's/^- //' | sed 's/ (.*)$//'
  done | sort -u | grep -v '^$'
}

if [ -n "$TARGET_GIT_ROOT" ]; then
  emit_git_delta
  exit 0
fi

emit_summary_delta
exit 0
