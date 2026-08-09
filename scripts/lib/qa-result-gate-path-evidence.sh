#!/usr/bin/env bash

QA_RESULT_GATE_PATH_EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" -f "$QA_RESULT_GATE_PATH_EVIDENCE_DIR/extract-frontmatter-array-items.awk" "$file_path" 2>/dev/null
}

normalize_recorded_path() {
  local path="${1:-}"
  local leading_char=""
  local trailing_char=""
  local squote="'"
  local dquote='"'
  local bquote='`'

  path=$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/,$//')
  if [ -n "$path" ]; then
    leading_char=${path%"${path#?}"}
    case "$leading_char" in
      "$squote"|"$dquote"|"$bquote") path="${path#?}" ;;
    esac
  fi
  if [ -n "$path" ]; then
    trailing_char=${path#"${path%?}"}
    case "$trailing_char" in
      "$squote"|"$dquote"|"$bquote") path="${path%?}" ;;
    esac
  fi
  while [[ "$path" == ./* ]]; do
    path="${path#./}"
  done
  printf '%s' "$path"
}

path_is_recorded_non_code_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$base" in
    SOURCE-UAT.md|PLAN.md|SUMMARY.md|VERIFICATION.md|RESEARCH.md|CONTEXT.md|UAT.md|STATE.md|ROADMAP.md|PROJECT.md|REQUIREMENTS.md|RESUME.md|SHIPPED.md|*-PLAN.md|*-SUMMARY.md|*-VERIFICATION.md|*-RESEARCH.md|*-CONTEXT.md|*-UAT.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_implementation_asset_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$path" in
    docs/*|*/docs/*)
      return 1
      ;;
  esac
  case "$path" in
    assets/*|*/assets/*|asset/*|*/asset/*|resources/*|*/resources/*|resource/*|*/resource/*|public/*|*/public/*|static/*|*/static/*|*/Assets.xcassets/*|Assets.xcassets/*)
      case "$base" in
        *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.txt|Contents.json)
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

path_is_documentation_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$path" in
    docs/*|*/docs/*)
      return 0
      ;;
  esac
  if path_is_implementation_asset_artifact "$path"; then
    return 1
  fi
  case "$base" in
    AGENTS.md|README|README.*|CHANGELOG|CHANGELOG.*|CONTRIBUTING|CONTRIBUTING.*|LICENSE|LICENSE.*|*.md|*.mdx|*.txt|*.rst|*.adoc|*.asciidoc|*.pdf|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_repo_hygiene_artifact() {
  local path="${1:-}"
  local base="${path##*/}"
  case "$base" in
    .gitignore|.gitattributes|.editorconfig|.prettierignore|.eslintignore|.npmignore|.dockerignore|.stylelintignore|.markdownlint.json|.markdownlint.yaml|.markdownlint.yml|VERSION)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

path_is_metadata_artifact() {
  local path="${1:-}"
  case "$path" in
    .lbwc-planning/*|.claude/*)
      return 0
      ;;
  esac
  if path_is_recorded_non_code_artifact "$path"; then
    return 0
  fi
  path_is_documentation_artifact "$path"
}

path_is_code_fix_support_artifact() {
  local path="${1:-}"
  case "$path" in
    .lbwc-planning/*|.claude/*|.claude-plugin/*)
      return 0
      ;;
  esac
  if path_is_recorded_non_code_artifact "$path"; then
    return 0
  fi
  if path_is_documentation_artifact "$path"; then
    return 0
  fi
  path_is_repo_hygiene_artifact "$path"
}

path_is_process_exception_evidence_artifact() {
  local phase_dir="${1:-}"
  local path="${2:-}"
  if resolve_qa_remediation_round_artifact_path "$path" "$phase_dir" >/dev/null 2>&1; then
    return 0
  fi
  path_is_original_plan_artifact "$path" "$phase_dir"
}

path_is_qa_remediation_round_artifact() {
  local path="${1:-}"
  if [[ "$path" =~ (^|/)remediation/qa/round-([0-9]+)/R([0-9]+)-(PLAN|SUMMARY)\.md$ ]]; then
    [ "${BASH_REMATCH[2]}" = "${BASH_REMATCH[3]}" ]
    return
  fi
  return 1
}

resolve_existing_path_target() {
  local path="${1:-}"
  local max_hops=40
  local hop=0
  local path_dir=""
  local path_base=""
  local target=""

  [ -n "$path" ] || return 1
  [ -e "$path" ] || return 1

  while [ -L "$path" ]; do
    if [ "$hop" -ge "$max_hops" ]; then
      return 1
    fi
    path_dir="${path%/*}"
    path_base="${path##*/}"
    [ -n "$path_dir" ] || path_dir="."
    path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || return 1)"
    target="$(readlink "$path_dir/$path_base" 2>/dev/null || true)"
    [ -n "$target" ] || return 1
    case "$target" in
      /*)
        path="$target"
        ;;
      *)
        path="$path_dir/$target"
        ;;
    esac
    hop=$((hop + 1))
  done

  path_dir="${path%/*}"
  path_base="${path##*/}"
  [ -n "$path_dir" ] || path_dir="."
  path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || return 1)"
  [ -e "$path_dir/$path_base" ] || return 1
  printf '%s' "$path_dir/$path_base"
}

resolve_qa_remediation_round_artifact_path() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  local phase_dir_abs=""
  local phase_parent_abs=""
  local phase_basename=""
  local repo_root_abs=""
  local phase_dir_rel=""
  local candidate=""
  local candidate_rel=""

  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  [ -n "$phase_dir" ] || return 1

  case "$path" in
    ../*|*/../*|*/./*) return 1 ;;
  esac

  phase_dir_abs="$(cd "$phase_dir" 2>/dev/null && pwd -P || return 1)"
  phase_parent_abs="${phase_dir_abs%/*}"
  phase_basename="${phase_dir_abs##*/}"
  repo_root_abs="$(git -C "$phase_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root_abs" ] && [[ "$phase_dir_abs" == "$repo_root_abs/"* ]]; then
    phase_dir_rel="${phase_dir_abs#"$repo_root_abs"/}"
  fi

  if [[ "$path" == /* ]]; then
    candidate="$path"
  elif [ -n "$repo_root_abs" ] && [ -n "$phase_dir_rel" ] && [[ "$path" == "$phase_dir_rel/"* ]]; then
    candidate="$repo_root_abs/$path"
  elif [[ "$path" == remediation/qa/* ]]; then
    candidate="$phase_dir_abs/$path"
  elif [[ "$path" == "$phase_basename/"* ]]; then
    candidate="$phase_parent_abs/$path"
  else
    return 1
  fi

  candidate="$(resolve_existing_path_target "$candidate" 2>/dev/null || true)"
  [ -n "$candidate" ] || return 1
  [ -f "$candidate" ] || return 1
  [[ "$candidate" == "$phase_dir_abs/"* ]] || return 1

  candidate_rel="${candidate#"$phase_dir_abs"/}"
  if [[ "$candidate_rel" =~ ^remediation/qa/round-([0-9]+)/R([0-9]+)-(PLAN|SUMMARY)\.md$ ]]; then
    [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] || return 1
    printf '%s' "$candidate"
    return 0
  fi

  return 1
}

resolve_original_plan_artifact_path() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  local phase_dir_abs=""
  local repo_root_abs=""
  local phase_dir_rel=""
  local candidate=""
  local candidate_dir=""
  local candidate_base=""

  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  [ -n "$phase_dir" ] || return 1

  phase_dir_abs="$(cd "$phase_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir")"
  repo_root_abs="$(git -C "$phase_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root_abs" ] && [[ "$phase_dir_abs" == "$repo_root_abs/"* ]]; then
    phase_dir_rel="${phase_dir_abs#"$repo_root_abs"/}"
  fi

  case "$path" in
    ../*|*/../*|*/./*) return 1 ;;
    */remediation/*) return 1 ;;
  esac

  if [[ "$path" == /* ]]; then
    candidate="$path"
  elif [ -n "$phase_dir_rel" ] && [[ "$path" == "$phase_dir_rel/"* ]]; then
    candidate="$repo_root_abs/$path"
  elif [[ "$path" != */* ]] && { [[ "$path" == *-PLAN.md ]] || [[ "$path" == PLAN.md ]]; }; then
    candidate="$phase_dir_abs/$path"
  else
    return 1
  fi

  candidate_dir="${candidate%/*}"
  candidate_base="${candidate##*/}"
  if [ -d "$candidate_dir" ]; then
    candidate_dir="$(cd "$candidate_dir" 2>/dev/null && pwd -P || printf '%s' "$candidate_dir")"
    candidate="$candidate_dir/$candidate_base"
  fi

  candidate="$(resolve_existing_path_target "$candidate" 2>/dev/null || true)"
  [ -n "$candidate" ] || return 1
  candidate_dir="${candidate%/*}"
  candidate_base="${candidate##*/}"

  [ "$candidate_dir" = "$phase_dir_abs" ] || return 1

  if [[ "$candidate_base" =~ ^R[0-9]+(-.*)?-PLAN\.md$ ]]; then
    return 1
  fi
  case "$candidate_base" in
    *-PLAN.md|PLAN.md) ;;
    *) return 1 ;;
  esac

  [ -f "$candidate" ] || return 1
  printf '%s' "$candidate"
}

path_is_original_plan_artifact() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  resolve_original_plan_artifact_path "$path" "$phase_dir" >/dev/null 2>&1
}

canonicalize_phase_path() {
  local path="${1:-}"
  local phase_dir="${2:-}"
  local phase_dir_abs=""
  local repo_root_abs=""
  local phase_dir_rel=""
  local path_dir=""
  local path_base=""

  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1

  if [[ "$path" == /* ]]; then
    path_dir="${path%/*}"
    path_base="${path##*/}"
    if [ -d "$path_dir" ]; then
      path_dir="$(cd "$path_dir" 2>/dev/null && pwd -P || printf '%s' "$path_dir")"
      path="$path_dir/$path_base"
    fi
  elif [[ "$path" == */* ]] && [ -n "$phase_dir" ]; then
    path_dir="${path%/*}"
    path_base="${path##*/}"
    if [ -d "$phase_dir/$path_dir" ]; then
      path_dir="$(cd "$phase_dir/$path_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir/$path_dir")"
      path="$path_dir/$path_base"
    fi
  fi

  phase_dir_abs="$(cd "$phase_dir" 2>/dev/null && pwd -P || printf '%s' "$phase_dir")"
  repo_root_abs="$(git -C "$phase_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root_abs" ] && [[ "$phase_dir_abs" == "$repo_root_abs/"* ]]; then
    phase_dir_rel="${phase_dir_abs#"$repo_root_abs"/}"
  fi

  if [ -n "$repo_root_abs" ] && [[ "$path" == "$repo_root_abs/"* ]]; then
    printf '%s' "${path#"$repo_root_abs"/}"
    return 0
  fi

  if [ -n "$phase_dir_abs" ] && [[ "$path" == "$phase_dir_abs/"* ]]; then
    if [ -n "$repo_root_abs" ] && [[ "$path" == "$repo_root_abs/"* ]]; then
      printf '%s' "${path#"$repo_root_abs"/}"
    else
      printf '%s' "$path"
    fi
    return 0
  fi

  if [ -n "$phase_dir_rel" ] && [[ "$path" == "$phase_dir_rel/"* ]]; then
    printf '%s' "$path"
    return 0
  fi

  if [ -f "$phase_dir/$path" ]; then
    if [ -n "$phase_dir_rel" ]; then
      printf '%s' "$phase_dir_rel/$path"
    else
      printf '%s' "$phase_dir_abs/$path"
    fi
    return 0
  fi

  printf '%s' "$path"
}

canonicalize_recorded_paths() {
  local phase_dir="${1:-}"
  local path=""
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    [ -n "$path" ] || continue
    printf '%s\n' "$path"
  done | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u)
}

intersect_canonical_paths() {
  local candidate_paths="${1:-}"
  local reference_paths="${2:-}"
  local path=""
  [ -n "$candidate_paths" ] || return 0
  [ -n "$reference_paths" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if printf '%s\n' "$reference_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
    fi
  done <<< "$candidate_paths" | (sort -u 2>/dev/null || sort -u)
}

paths_include_original_plan_artifact() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if path_is_original_plan_artifact "$path" "$phase_dir"; then
      return 0
    fi
  done
  return 1
}

paths_include_non_metadata() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    if ! path_is_metadata_artifact "$path"; then
      return 0
    fi
  done
  return 1
}

paths_include_code_fix_evidence() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if [ -n "$phase_dir" ]; then
      path=$(canonicalize_phase_path "$path" "$phase_dir")
    fi
    if ! path_is_code_fix_support_artifact "$path"; then
      return 0
    fi
  done
  return 1
}

paths_include_documentation_fix_evidence() {
  local phase_dir="${1:-}"
  local required_paths="${2:-}"
  local changed_paths=""
  local required_path=""
  local changed_path=""
  local canonical_required=""
  local canonical_changed=""
  local found=false

  changed_paths=$(cat)
  while IFS= read -r required_path; do
    required_path=$(normalize_recorded_path "$required_path")
    [ -n "$required_path" ] || return 1
    canonical_required=$(canonicalize_phase_path "$required_path" "$phase_dir")
    path_is_documentation_artifact "$canonical_required" || return 1
    found=false
    while IFS= read -r changed_path; do
      changed_path=$(normalize_recorded_path "$changed_path")
      [ -n "$changed_path" ] || continue
      canonical_changed=$(canonicalize_phase_path "$changed_path" "$phase_dir")
      if [ "$canonical_required" = "$canonical_changed" ]; then
        found=true
        break
      fi
    done <<< "$changed_paths"
    [ "$found" = true ] || return 1
  done <<< "$required_paths"
  [ -n "$required_paths" ]
}

paths_include_process_exception_evidence() {
  local phase_dir="${1:-}"
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    if path_is_process_exception_evidence_artifact "$phase_dir" "$path"; then
      return 0
    fi
  done
  return 1
}

paths_are_process_exception_evidence_artifacts() {
  local phase_dir="${1:-}"
  local saw_path=false
  while IFS= read -r path; do
    path=$(normalize_recorded_path "$path")
    [ -n "$path" ] || continue
    saw_path=true
    if ! path_is_process_exception_evidence_artifact "$phase_dir" "$path"; then
      return 1
    fi
  done
  [ "$saw_path" = true ]
}

path_is_allowed_worktree_evidence_artifact() {
  local phase_dir="${1:-}"
  local path="${2:-}"
  path=$(normalize_recorded_path "$path")
  [ -n "$path" ] || return 1
  if resolve_qa_remediation_round_artifact_path "$path" "$phase_dir" >/dev/null 2>&1; then
    return 0
  fi
  path_is_original_plan_artifact "$path" "$phase_dir"
}

resolve_corroborated_recorded_paths() {
  local phase_dir="${1:-}"
  local recorded_paths="${2:-}"
  local committed_paths="${3:-}"
  local worktree_paths="${4:-}"
  local ignored_worktree_paths="${5:-}"
  local path=""

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if printf '%s\n' "$committed_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      continue
    fi
    if path_is_allowed_worktree_evidence_artifact "$phase_dir" "$path" \
      && printf '%s\n' "$worktree_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
      continue
    fi
    if [ -n "$ignored_worktree_paths" ] \
      && path_is_metadata_artifact "$path" \
      && path_is_allowed_worktree_evidence_artifact "$phase_dir" "$path" \
      && printf '%s\n' "$ignored_worktree_paths" | grep -Fx -- "$path" >/dev/null 2>&1; then
      printf '%s\n' "$path"
    fi
  done <<< "$recorded_paths" | (sort -u 2>/dev/null || sort -u)
}

recorded_paths_are_fully_corroborated() {
  local recorded_paths="${1:-}"
  local corroborated_paths="${2:-}"
  local recorded_count corroborated_count
  recorded_count=$(printf '%s\n' "$recorded_paths" | awk 'NF { count++ } END { print count + 0 }')
  corroborated_count=$(printf '%s\n' "$corroborated_paths" | awk 'NF { count++ } END { print count + 0 }')
  [ "$recorded_count" -eq "$corroborated_count" ] 2>/dev/null
}

commit_hashes_to_changed_files() {
  local repo_root="${1:-}"
  local commit_hashes="${2:-}"
  [ -n "$repo_root" ] || return 0
  [ -n "$commit_hashes" ] || return 0
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" show --name-only --format= "$commit_hash" 2>/dev/null || true
  done <<< "$commit_hashes"
}

commit_hashes_resolve_cleanly() {
  local repo_root="${1:-}"
  local commit_hashes="${2:-}"
  local commit_hash
  [ -n "$repo_root" ] || return 1
  [ -n "$commit_hashes" ] || return 1
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" cat-file -e "${commit_hash}^{commit}" 2>/dev/null || return 1
  done <<< "$commit_hashes"
  return 0
}

commit_hashes_are_round_local() {
  local repo_root="${1:-}"
  local round_anchor_commit="${2:-}"
  local commit_hashes="${3:-}"
  local head_commit=""
  local commit_hash
  [ -n "$repo_root" ] || return 1
  [ -n "$round_anchor_commit" ] || return 1
  [ -n "$commit_hashes" ] || return 1
  git -C "$repo_root" cat-file -e "${round_anchor_commit}^{commit}" 2>/dev/null || return 1
  head_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)
  [ -n "$head_commit" ] || return 1
  while IFS= read -r commit_hash; do
    commit_hash=$(printf '%s' "$commit_hash" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//;s/^['\"]//;s/['\"]$//")
    [ -n "$commit_hash" ] || continue
    git -C "$repo_root" cat-file -e "${commit_hash}^{commit}" 2>/dev/null || return 1
    [ "$commit_hash" != "$round_anchor_commit" ] || return 1
    git -C "$repo_root" merge-base --is-ancestor "$round_anchor_commit" "$commit_hash" 2>/dev/null || return 1
    git -C "$repo_root" merge-base --is-ancestor "$commit_hash" "$head_commit" 2>/dev/null || return 1
  done <<< "$commit_hashes"
  return 0
}

git_diff_paths_since_commit() {
  local repo_root="${1:-}"
  local anchor_commit="${2:-}"
  [ -n "$repo_root" ] || return 0
  [ -n "$anchor_commit" ] || return 0
  git -C "$repo_root" cat-file -e "${anchor_commit}^{commit}" 2>/dev/null || return 0
  git -C "$repo_root" diff --name-only "$anchor_commit"..HEAD 2>/dev/null || true
}

git_current_worktree_paths() {
  local repo_root="${1:-}"
  [ -n "$repo_root" ] || return 0
  git -C "$repo_root" diff --name-only HEAD 2>/dev/null || true
  git -C "$repo_root" ls-files --others --exclude-standard 2>/dev/null || true
}

git_ignored_metadata_worktree_paths() {
  local repo_root="${1:-}"
  local path
  [ -n "$repo_root" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if path_is_metadata_artifact "$path"; then
      printf '%s\n' "$path"
    fi
  done < <(git -C "$repo_root" ls-files --others --ignored --exclude-standard \
    -- .lbwc-planning .claude 2>/dev/null || true)
}

commit_is_ancestor_or_same() {
  local repo_root="${1:-}"
  local ancestor_commit="${2:-}"
  local descendant_commit="${3:-}"
  [ -n "$repo_root" ] || return 1
  [ -n "$ancestor_commit" ] || return 1
  [ -n "$descendant_commit" ] || return 1
  git -C "$repo_root" cat-file -e "${ancestor_commit}^{commit}" 2>/dev/null || return 1
  git -C "$repo_root" cat-file -e "${descendant_commit}^{commit}" 2>/dev/null || return 1
  git -C "$repo_root" merge-base --is-ancestor "$ancestor_commit" "$descendant_commit" 2>/dev/null
}

extract_verified_at_commit() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^verified_at_commit:/ {
      sub(/^verified_at_commit:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
    }
  ' "$file_path" 2>/dev/null
}
