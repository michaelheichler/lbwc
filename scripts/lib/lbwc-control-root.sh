#!/usr/bin/env bash

lbwc_control_root_canonical_path() {
  local candidate="$1"
  [ -n "$candidate" ] || return 1
  [ -d "$candidate" ] || return 1
  [ ! -L "$candidate" ] || return 1
  (cd "$candidate" 2>/dev/null && pwd -P 2>/dev/null) || return 1
}

lbwc_control_root_is_valid_json() {
  local config_path="$1"
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$config_path" ] || return 1
  jq -e 'type == "object"' "$config_path" >/dev/null 2>&1
}

lbwc_control_root_validate() {
  local candidate="$1" allow_manifest_only="${2:-0}" canonical project_root run_parent run_parent_parent run_id

  canonical=$(lbwc_control_root_canonical_path "$candidate") || return 1
  case "$(basename "$canonical")" in
    .lbwc-planning)
      project_root=$(dirname "$canonical")
      if ! lbwc_control_root_is_valid_json "$canonical/config.json"; then
        [ "$allow_manifest_only" = "1" ] || return 1
        [ -f "$canonical/.agent-manifest.json" ] || return 1
      fi
      LBWC_CONTROL_ROOT_KIND="active-planning"
      LBWC_CONTROL_ROOT="$canonical"
      LBWC_PROJECT_ROOT="$project_root"
      export LBWC_CONTROL_ROOT_KIND LBWC_CONTROL_ROOT LBWC_PROJECT_ROOT
      printf '%s\n' "$canonical"
      return 0
      ;;
  esac

  run_parent=$(dirname "$canonical")
  run_parent_parent=$(dirname "$run_parent")
  run_id=$(basename "$canonical")
  [ "$(basename "$run_parent")" = "runs" ] || return 1
  [ "$(basename "$run_parent_parent")" = ".temporary-agent-runfiles" ] || return 1
  [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  LBWC_CONTROL_ROOT_KIND="temporary-run"
  LBWC_CONTROL_ROOT="$canonical"
  LBWC_PROJECT_ROOT=$(dirname "$run_parent_parent")
  export LBWC_CONTROL_ROOT_KIND LBWC_CONTROL_ROOT LBWC_PROJECT_ROOT
  printf '%s\n' "$canonical"
}

lbwc_control_root_project_root() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  case "$(basename "$control_root")" in
    .lbwc-planning) dirname "$control_root" ;;
    *) dirname "$(dirname "$(dirname "$control_root")")" ;;
  esac
}

lbwc_control_root_manifest_path() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  if [ "$(basename "$control_root")" = ".lbwc-planning" ]; then
    printf '%s/.agent-manifest.json\n' "$control_root"
  else
    printf '%s/agent-manifest.json\n' "$control_root"
  fi
}

lbwc_control_root_lock_path() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  if [ "$(basename "$control_root")" = ".lbwc-planning" ]; then
    printf '%s/.agent-manifest.lock\n' "$control_root"
  else
    printf '%s/agent-manifest.lock\n' "$control_root"
  fi
}

lbwc_control_root_workflow_manifest_path() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  if [ "$(basename "$control_root")" = ".lbwc-planning" ]; then
    printf '%s/.workflow-manifest.json\n' "$control_root"
  else
    printf '%s/workflow-manifest.json\n' "$control_root"
  fi
}

lbwc_control_root_workflow_manifest_lock_path() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  if [ "$(basename "$control_root")" = ".lbwc-planning" ]; then
    printf '%s/.workflow-manifest.lock\n' "$control_root"
  else
    printf '%s/workflow-manifest.lock\n' "$control_root"
  fi
}

lbwc_control_root_workflows_dir() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  printf '%s/workflows\n' "$control_root"
}

lbwc_control_root_contracts_dir() {
  local control_root
  control_root=$(lbwc_control_root_canonical_path "$1") || return 1
  if [ "$(basename "$control_root")" = ".lbwc-planning" ]; then
    printf '%s/.contracts/tasks\n' "$control_root"
  else
    printf '%s/contracts/tasks\n' "$control_root"
  fi
}

lbwc_control_root_generated_agents_dir() {
  local project_root
  project_root=$(lbwc_control_root_project_root "$1") || return 1
  printf '%s/.claude/agents\n' "$project_root"
}

lbwc_control_root_find_from_start() {
  local start="$1" current candidate run_candidate selected_run
  current=$(cd "$start" 2>/dev/null && pwd -P) || return 1
  while :; do
    candidate="$current/.lbwc-planning"
    if [ -d "$candidate" ] && lbwc_control_root_validate "$candidate" 1 >/dev/null 2>&1; then
      printf '%s\n' "$(lbwc_control_root_canonical_path "$candidate")"
      return 0
    fi

    candidate="$current/.temporary-agent-runfiles/runs"
    if [ -d "$candidate" ]; then
      selected_run=""
      for run_candidate in "$candidate"/*; do
        [ -d "$run_candidate" ] || continue
        if [ "$current" = "$(lbwc_control_root_project_root "$run_candidate" 2>/dev/null || true)" ] && lbwc_control_root_validate "$run_candidate" 0 >/dev/null 2>&1; then
          [ -z "$selected_run" ] || return 1
          selected_run=$(lbwc_control_root_canonical_path "$run_candidate") || return 1
        fi
      done
      if [ -n "$selected_run" ]; then
        printf '%s\n' "$selected_run"
        return 0
      fi
    fi

    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  return 1
}

lbwc_resolve_control_root() {
  local requested_control="${1:-}" requested_project="${2:-}" start="${3:-${PWD:-}}" candidate

  if [ -n "$requested_control" ]; then
    lbwc_control_root_validate "$requested_control" 0
    return $?
  fi
  if [ -n "${LBWC_CONTROL_ROOT:-}" ]; then
    lbwc_control_root_validate "$LBWC_CONTROL_ROOT" 0
    return $?
  fi
  if [ -n "${LBWC_PLANNING_DIR:-}" ]; then
    lbwc_control_root_validate "$LBWC_PLANNING_DIR" 1
    return $?
  fi
  if [ -n "$requested_project" ]; then
    candidate=$(cd "$requested_project" 2>/dev/null && pwd -P)/.lbwc-planning || return 1
    lbwc_control_root_validate "$candidate" 0
    return $?
  fi
  lbwc_control_root_find_from_start "$start"
}
