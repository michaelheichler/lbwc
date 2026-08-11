#!/usr/bin/env bash

_walk_up_for_lbwc_root() {
  local _cwd="$1" _prev
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.lbwc-planning/config.json" ]; then
      export LBWC_CONFIG_ROOT="$_cwd"
      export LBWC_PLANNING_DIR="$_cwd/.lbwc-planning"
      return 0
    fi
    _prev="$_cwd"
    _cwd=$(dirname "$_cwd")
    [ "$_cwd" = "$_prev" ] && break
  done
  return 1
}

_prefer_claude_sidechain_host_root() {
  local _cwd="$1" _probe _parent _grandparent _host

  _probe="$_cwd"
  while [ "$_probe" != "/" ]; do
    case "$(basename "$_probe")" in
      agent-*)
        _parent=$(dirname "$_probe")
        _grandparent=$(dirname "$_parent")
        if [ "$(basename "$_parent")" = "worktrees" ] && [ "$(basename "$_grandparent")" = ".claude" ]; then
          _host=$(dirname "$_grandparent")
          if [ -f "$_host/.lbwc-planning/config.json" ]; then
            export LBWC_CONFIG_ROOT="$_host"
            export LBWC_PLANNING_DIR="$_host/.lbwc-planning"
            export LBWC_CLAUDE_SIDECHAIN_ROOT="$_probe"
            export LBWC_CLAUDE_SIDECHAIN_HOST_ROOT="$_host"
            return 0
          fi
        fi
        ;;
    esac

    _parent=$(dirname "$_probe")
    [ "$_parent" = "$_probe" ] && break
    _probe="$_parent"
  done

  return 1
}

find_lbwc_root() {
  if [ -n "${LBWC_CONFIG_ROOT:-}" ]; then
    export LBWC_CONFIG_ROOT
    export LBWC_PLANNING_DIR="${LBWC_CONFIG_ROOT}/.lbwc-planning"
    return 0
  fi

  local _start_dir _cwd_dir
  _cwd_dir=$(pwd -P 2>/dev/null || pwd)

  if [ -n "${1:-}" ]; then
    _prefer_claude_sidechain_host_root "$_cwd_dir" && return 0
    _walk_up_for_lbwc_root "$_cwd_dir" && return 0
    if _start_dir=$(cd "$1" 2>/dev/null && pwd -P 2>/dev/null); then
      _walk_up_for_lbwc_root "$_start_dir" && return 0
    else
      _walk_up_for_lbwc_root "$_cwd_dir" && return 0
    fi
  else
    _prefer_claude_sidechain_host_root "$_cwd_dir" && return 0
    _walk_up_for_lbwc_root "$_cwd_dir" && return 0
  fi

  export LBWC_CONFIG_ROOT="$_cwd_dir"
  export LBWC_PLANNING_DIR="$_cwd_dir/.lbwc-planning"
}
