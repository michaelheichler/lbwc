#!/bin/bash
set -u

PHASE="${1:-}"
PLAN="${2:-}"

if [ -z "$PHASE" ] || [ -z "$PLAN" ]; then
  exit 0
fi

if ! [[ "$PHASE" =~ ^[0-9]{2}$ && "$PLAN" =~ ^[0-9]{2}$ ]]; then
  printf 'invalid cleanup target: phase and plan must be two digits\n' >&2
  exit 1
fi

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
WORKTREES_PARENT=".lbwc-worktrees"
WORKTREE_DIR="${WORKTREES_PARENT}/${PHASE}-${PLAN}"
BRANCH="lbwc/${PHASE}-${PLAN}"
AGENT_WORKTREES_DIR="$PLANNING_DIR/.agent-worktrees"
AUTOMATIC_CLEANUP="${LBWC_AUTOMATIC_CLEANUP:-0}"

scan_only() {
  printf 'scan_only|%s|%s\n' "$WORKTREE_DIR" "$1"
  exit 0
}

worktree_mapping_state() {
  local worktree_abs map_file mapped_path mapped_abs

  worktree_abs="$(cd "$WORKTREE_DIR" 2>/dev/null && pwd -P)" || return 2
  command -v jq >/dev/null 2>&1 || return 2
  [ -d "$AGENT_WORKTREES_DIR" ] || return 2

  for map_file in "$AGENT_WORKTREES_DIR"/*.json; do
    [ -f "$map_file" ] || continue
    mapped_path="$(jq -er '.worktree_path | strings | select(length > 0)' "$map_file" 2>/dev/null)" || return 2
    mapped_abs="$(cd "$mapped_path" 2>/dev/null && pwd -P)" || mapped_abs="$mapped_path"
    [ "$mapped_abs" = "$worktree_abs" ] && return 0
  done

  return 1
}

is_owned_lbwc_worktree() {
  local worktree_abs

  worktree_abs="$(cd "$WORKTREE_DIR" 2>/dev/null && pwd -P)" || return 1
  git worktree list --porcelain 2>/dev/null | awk -v path="$worktree_abs" -v branch="refs/heads/$BRANCH" '
    $1 == "worktree" {
      if (worktree == path && current_branch == branch) found = 1
      worktree = substr($0, 10)
      current_branch = ""
      next
    }
    $1 == "branch" { current_branch = substr($0, 8) }
    END {
      if (worktree == path && current_branch == branch) found = 1
      exit !found
    }
  '
}

worktree_is_dirty() {
  [ -n "$(git -C "$WORKTREE_DIR" status --porcelain --untracked-files=all 2>/dev/null)" ]
}

if [ "$AUTOMATIC_CLEANUP" = "1" ]; then
  [ -d "$WORKTREE_DIR" ] || scan_only "cleanup target absent"
  is_owned_lbwc_worktree || scan_only "unproven ownership"
  worktree_mapping_state
  case "$?" in
    0) scan_only "active mapping" ;;
    1) ;;
    *) scan_only "active mapping inspection unavailable" ;;
  esac
  worktree_is_dirty && scan_only "dirty worktree"
fi

git worktree unlock "$WORKTREE_DIR" 2>/dev/null || true

git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true

rm -rf "$WORKTREE_DIR" 2>/dev/null || true

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || true
if [ -n "${GIT_DIR:-}" ] && [ -d "$GIT_DIR/worktrees" ]; then
  WORKTREE_ABS="$(cd "$(dirname "$WORKTREE_DIR")" 2>/dev/null && pwd)/$(basename "$WORKTREE_DIR")" 2>/dev/null || true
  if [ -n "${WORKTREE_ABS:-}" ]; then
    for admin_dir in "$GIT_DIR/worktrees"/*/; do
      [ -d "$admin_dir" ] || continue
      gitdir_file="${admin_dir}gitdir"
      [ -f "$gitdir_file" ] || continue
      recorded="$(cat "$gitdir_file" 2>/dev/null)" || continue
      recorded_wt="${recorded%/.git}"
      recorded_wt_abs="$(cd "$recorded_wt" 2>/dev/null && pwd)" 2>/dev/null || recorded_wt_abs=""
      if [ "$recorded_wt_abs" = "$WORKTREE_ABS" ] || [ "$recorded_wt" = "$WORKTREE_DIR" ]; then
        rm -rf "$admin_dir" 2>/dev/null || true
      fi
    done
  fi
fi

rmdir "$WORKTREES_PARENT" 2>/dev/null || true

git branch -d "$BRANCH" 2>/dev/null || true

if [ -d "$AGENT_WORKTREES_DIR" ]; then
  for f in "$AGENT_WORKTREES_DIR"/*"${PHASE}-${PLAN}"*.json; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
  done
fi

exit 0
