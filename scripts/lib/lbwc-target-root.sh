#!/usr/bin/env bash


lbwc_candidate_dir_for_path() {
  local candidate="$1"

  [ -n "$candidate" ] || return 1
  [ -e "$candidate" ] || return 1

  if [ -d "$candidate" ]; then
    (
      cd "$candidate" 2>/dev/null && pwd -P 2>/dev/null
    ) || printf '%s\n' "$candidate"
  else
    local dir
    dir=$(dirname "$candidate")
    (
      cd "$dir" 2>/dev/null && pwd -P 2>/dev/null
    ) || printf '%s\n' "$dir"
  fi
}

lbwc_walk_up_for_workspace_root() {
  local current="$1" next

  while :; do
    if [ "$(basename "$current")" = ".lbwc-planning" ]; then
      dirname "$current"
      return 0
    fi

    if [ -d "$current/.lbwc-planning" ]; then
      printf '%s\n' "$current"
      return 0
    fi

    if [ "$current" = "/" ]; then
      break
    fi

    next=$(dirname "$current")
    [ "$next" = "$current" ] && break
    current="$next"
  done

  return 1
}

lbwc_git_show_toplevel() {
  local candidate_dir="$1"
  local git_root

  git -C "$candidate_dir" rev-parse --is-inside-work-tree &>/dev/null || return 1
  git_root=$(git -C "$candidate_dir" rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$git_root" ] || return 1
  printf '%s\n' "$git_root"
}

lbwc_target_root_from_candidates() {
  local candidate candidate_dir

  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    candidate_dir=$(lbwc_candidate_dir_for_path "$candidate" 2>/dev/null || true)
    [ -n "$candidate_dir" ] || continue

    if lbwc_walk_up_for_workspace_root "$candidate_dir" 2>/dev/null; then
      return 0
    fi
    if lbwc_git_show_toplevel "$candidate_dir" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

lbwc_target_root_from_pwd() {
  local pwd_dir
  pwd_dir=$(pwd -P 2>/dev/null || pwd)

  if lbwc_walk_up_for_workspace_root "$pwd_dir" 2>/dev/null; then
    return 0
  fi
  if command -v git &>/dev/null && lbwc_git_show_toplevel "$pwd_dir" 2>/dev/null; then
    return 0
  fi

  return 1
}

lbwc_resolve_target_root() {
  local explicit_scope="$1"
  shift || true

  if lbwc_target_root_from_candidates "$@"; then
    return 0
  fi

  if [ "$explicit_scope" != "1" ]; then
    lbwc_target_root_from_pwd
    return $?
  fi

  return 1
}

lbwc_resolve_target_planning_dir() {
  local explicit_scope="$1"
  shift || true

  local candidate candidate_dir target_root

  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    candidate_dir=$(lbwc_candidate_dir_for_path "$candidate" 2>/dev/null || true)
    [ -n "$candidate_dir" ] || continue

    if [ "$(basename "$candidate_dir")" = ".lbwc-planning" ]; then
      printf '%s\n' "$candidate_dir"
      return 0
    fi
  done

  target_root=$(lbwc_resolve_target_root "$explicit_scope" "$@" 2>/dev/null || true)
  if [ -n "$target_root" ] && [ -d "$target_root/.lbwc-planning" ]; then
    printf '%s/.lbwc-planning\n' "$target_root"
    return 0
  fi

  return 1
}

lbwc_resolve_target_git_root() {
  local explicit_scope="$1"
  shift || true

  local candidate candidate_dir

  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    candidate_dir=$(lbwc_candidate_dir_for_path "$candidate" 2>/dev/null || true)
    [ -n "$candidate_dir" ] || continue

    if lbwc_git_show_toplevel "$candidate_dir" 2>/dev/null; then
      return 0
    fi
  done

  if [ "$explicit_scope" != "1" ] && command -v git &>/dev/null && lbwc_git_show_toplevel "$(pwd -P 2>/dev/null || pwd)" 2>/dev/null; then
    return 0
  fi

  return 1
}

lbwc_is_safe_relative_path() {
  local path="${1:-}"
  case "$path" in
    ""|/*|..|../*|*/../*|*/..) return 1 ;;
  esac
  return 0
}

lbwc_resolve_repo_path() {
  local root="$1" path="$2"

  if [ -z "$path" ]; then
    printf '\n'
    return 0
  fi

  if ! lbwc_is_safe_relative_path "$path"; then
    return 1
  fi

  if [ -n "$root" ]; then
    printf '%s/%s\n' "$root" "$path"
  else
    printf '%s\n' "$path"
  fi
}

lbwc_workspace_subpath_from_git_root() {
  local workspace_root="${1%/}" git_root="${2%/}"

  [ -n "$workspace_root" ] || return 1
  [ -n "$git_root" ] || return 1

  if [ "$workspace_root" = "$git_root" ]; then
    printf '\n'
    return 0
  fi

  case "$workspace_root/" in
    "$git_root"/*)
      printf '%s\n' "${workspace_root#"$git_root"/}"
      ;;
    *)
      return 1
      ;;
  esac
}

lbwc_apply_workspace_subpath() {
  local git_path="$1" workspace_subpath="$2"

  if [ -z "$workspace_subpath" ]; then
    printf '%s\n' "$git_path"
    return 0
  fi

  case "$git_path" in
    "$workspace_subpath"/*)
      printf '%s\n' "${git_path#"$workspace_subpath"/}"
      ;;
    "$workspace_subpath")
      printf '.\n'
      ;;
    *)
      return 1
      ;;
  esac
}

lbwc_git_path_to_workspace_path() {
  local git_path="$1" workspace_root="$2" git_root="$3" workspace_subpath

  [ -n "$git_path" ] || return 1

  case "$git_path" in
    /*)
      printf '%s\n' "$git_path"
      return 0
      ;;
  esac

  workspace_subpath=$(lbwc_workspace_subpath_from_git_root "$workspace_root" "$git_root" 2>/dev/null || true)
  lbwc_apply_workspace_subpath "$git_path" "$workspace_subpath"
}
