#!/bin/bash
set -u



PORCELAIN=""
PORCELAIN=$(git worktree list --porcelain 2>/dev/null) || true

json_items=""

current_path=""
current_branch=""
in_lbwc_worktree=0

process_stanza() {
  local path="$1"
  local branch="$2"
  local is_lbwc="$3"

  [ "$is_lbwc" -eq 0 ] && return
  [ -z "$path" ] && return
  [ -z "$branch" ] && return

  local short_branch="${branch#refs/heads/}"

  local suffix="${short_branch#lbwc/}"
  local phase="${suffix%%-*}"
  local plan="${suffix#*-}"

  local escaped_path
  escaped_path=$(printf '%s' "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')
  local escaped_branch
  escaped_branch=$(printf '%s' "$short_branch" | sed 's/\\/\\\\/g; s/"/\\"/g')

  local entry
  entry="{\"path\":\"${escaped_path}\",\"branch\":\"${escaped_branch}\",\"phase\":\"${phase}\",\"plan\":\"${plan}\"}"

  if [ -z "$json_items" ]; then
    json_items="$entry"
  else
    json_items="${json_items},${entry}"
  fi
}

while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$line" ]; then
    process_stanza "$current_path" "$current_branch" "$in_lbwc_worktree"
    current_path=""
    current_branch=""
    in_lbwc_worktree=0
    continue
  fi

  key="${line%% *}"
  value="${line#* }"

  case "$key" in
    worktree)
      current_path="$value"
      case "$value" in
        *".lbwc-worktrees/"*) in_lbwc_worktree=1 ;;
        *)                    in_lbwc_worktree=0 ;;
      esac
      ;;
    branch)
      current_branch="$value"
      ;;
  esac
done <<EOF
$PORCELAIN
EOF

process_stanza "$current_path" "$current_branch" "$in_lbwc_worktree"

printf '[%s]\n' "$json_items"

exit 0
