#!/bin/bash
# shellcheck disable=SC2034
# verification-freshness.sh: shared helpers for determining whether a
# VERIFICATION.md artifact is stale relative to current product-code state.
#
# Contract:
# - verification_is_stale FILE returns 0 when the verification should be treated
#   as stale/pending, 1 when it is fresh or the file is missing, and sets
#   VERIFICATION_FRESHNESS_REASON to a short diagnostic token.
# - When FILE is empty or does not exist, returns 1 with reason "missing_file".
# - Any git/provenance error fails closed to stale. Under heavy parallel test
#   load, transient git subprocess failures must not be misclassified as fresh.

# Contributors must not edit these 4 version-sync files (CLAUDE.md Version
# Management), so a release bump commit must not mark every phase stale.
FRESHNESS_EXCLUDE_PATHSPEC=(
  ':!.lbwc-planning' ':!CLAUDE.md' ':!VERSION'
  ':!.claude-plugin/plugin.json' ':!.claude-plugin/marketplace.json' ':!marketplace.json'
)
VERIFICATION_FRESHNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract_verified_at_commit() {
  local verif_file="$1"
  [ -n "$verif_file" ] && [ -f "$verif_file" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^verified_at_commit:/ { sub(/^verified_at_commit:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
  ' "$verif_file" 2>/dev/null || true
}

if ! declare -F summary_extract_frontmatter_array_items >/dev/null 2>&1; then
  summary_extract_frontmatter_array_items() {
    local file_path="$1" key_name="$2"
    awk -v key="$key_name" \
      -f "$VERIFICATION_FRESHNESS_DIR/extract-frontmatter-array-items.awk" \
      "$file_path" 2>/dev/null
  }
fi

export VERIFICATION_FRESHNESS_REASON=
_freshness_recorded_paths() {
  local phase_dir="$1" artifact
  for artifact in "$phase_dir"/*-PLAN.md "$phase_dir"/PLAN.md \
    "$phase_dir"/*-SUMMARY.md "$phase_dir"/SUMMARY.md; do
    [ -f "$artifact" ] || continue
    summary_extract_frontmatter_array_items "$artifact" files_modified
    summary_extract_frontmatter_array_items "$artifact" files_touched
  done
}

_freshness_working_tree_dirty() {
  local phase_dir="${1:-}"
  local -a pathspec=()

  if [ -n "$phase_dir" ]; then
    mapfile -t pathspec < <(_freshness_recorded_paths "$phase_dir")
  fi
  [ "${#pathspec[@]}" -gt 0 ] || pathspec=(.)

  git status --porcelain --untracked-files=normal -- "${pathspec[@]}" \
    "${FRESHNESS_EXCLUDE_PATHSPEC[@]}" 2>/dev/null
}

_freshness_stale_by_commit() {
  local _vac="$1" _cur_commit

  if ! _cur_commit=$(git log -1 --format='%H' -- . "${FRESHNESS_EXCLUDE_PATHSPEC[@]}" 2>/dev/null); then
    VERIFICATION_FRESHNESS_REASON="git_log_failed"
    return 0
  fi
  if [ -z "$_cur_commit" ]; then
    VERIFICATION_FRESHNESS_REASON="product_commit_unavailable"
    return 0
  fi
  if [ "$_cur_commit" != "$_vac" ]; then
    VERIFICATION_FRESHNESS_REASON="verified_at_commit_mismatch"
    return 0
  fi
  VERIFICATION_FRESHNESS_REASON="fresh"
  return 1
}

_freshness_stale_by_mtime() {
  local verif_file="$1" _cur_commit_ts _verif_mtime

  if ! _cur_commit_ts=$(git log -1 --format='%ct' -- . "${FRESHNESS_EXCLUDE_PATHSPEC[@]}" 2>/dev/null); then
    VERIFICATION_FRESHNESS_REASON="git_log_failed"
    return 0
  fi
  _verif_mtime=$(stat -c %Y "$verif_file" 2>/dev/null || stat -f %m "$verif_file" 2>/dev/null || true)
  if [ -z "$_cur_commit_ts" ] || [ -z "$_verif_mtime" ]; then
    VERIFICATION_FRESHNESS_REASON="freshness_baseline_unavailable"
    return 0
  fi
  if [ "$_cur_commit_ts" -ge "$_verif_mtime" ]; then
    VERIFICATION_FRESHNESS_REASON="product_changed_after_verification"
    return 0
  fi

  VERIFICATION_FRESHNESS_REASON="fresh"
  return 1
}

verification_is_stale() {
  local verif_file="$1"
  local phase_dir="${2:-}"
  local _dirty _vac

  VERIFICATION_FRESHNESS_REASON=""
  if [ -z "$verif_file" ] || [ ! -f "$verif_file" ]; then
    VERIFICATION_FRESHNESS_REASON="missing_file"
    return 1
  fi

  if ! _dirty=$(_freshness_working_tree_dirty "$phase_dir"); then
    VERIFICATION_FRESHNESS_REASON="git_status_failed"
    return 0
  fi
  if [ -n "$_dirty" ]; then
    VERIFICATION_FRESHNESS_REASON="working_tree_changed"
    return 0
  fi

  _vac=$(extract_verified_at_commit "$verif_file")
  if [ -n "$_vac" ]; then
    _freshness_stale_by_commit "$_vac"
    return $?
  fi

  _freshness_stale_by_mtime "$verif_file"
}
