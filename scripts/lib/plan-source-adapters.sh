#!/usr/bin/env bash

plan_source_canonical_file() {
  local path="$1" canonical directory filename
  [ -f "$path" ] || return 1
  canonical=$(realpath "$path" 2>/dev/null || true)
  if [ -n "$canonical" ] && [ -f "$canonical" ]; then
    printf '%s\n' "$canonical"
    return 0
  fi
  directory=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
  filename=$(basename "$path")
  printf '%s/%s\n' "$directory" "$filename"
}

plan_source_digest() {
  local path="$1" digest
  if command -v shasum >/dev/null 2>&1; then
    digest=$(shasum -a 256 "$path" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    digest=$(sha256sum "$path" | awk '{print $1}')
  else
    return 1
  fi
  [ -n "$digest" ] || return 1
  printf 'sha256:%s\n' "$digest"
}

plan_source_mtime_epoch() {
  local path="$1" epoch
  epoch=$(stat -f '%m' "$path" 2>/dev/null || true)
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    epoch=$(stat -c '%Y' "$path" 2>/dev/null || true)
  fi
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$epoch"
}


plan_source_size_bytes() {
  local path="$1" size
  size=$(stat -f '%z' "$path" 2>/dev/null || true)
  if [[ ! "$size" =~ ^[0-9]+$ ]]; then
    size=$(stat -c '%s' "$path" 2>/dev/null || true)
  fi
  [[ "$size" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$size"
}

plan_source_modified_at() {
  local epoch="$1" value
  value=$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)
  if [ -z "$value" ]; then
    value=$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)
  fi
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

plan_source_title() {
  local path="$1" title
  title=$(awk '
    /^[[:space:]]*#[[:space:]]+/ {
      sub(/^[[:space:]]*#[[:space:]]+/, "")
      sub(/[[:space:]]+#+[[:space:]]*$/, "")
      print
      exit
    }
  ' "$path" 2>/dev/null || true)
  [ -n "$title" ] || title=$(basename "$path")
  printf '%s\n' "$title"
}

plan_source_status_hints() {
  local path="$1" line lower hints='[]'
  while IFS= read -r line || [ -n "$line" ]; do
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *completed*|*complete*|*done*)
        hints=$(jq -c '. + ["completion-claim"]' <<< "$hints")
        ;;
      *in.progress*|*in_progress*|*active*)
        hints=$(jq -c '. + ["in-progress-claim"]' <<< "$hints")
        ;;
      *pending*|*todo*|*not.started*)
        hints=$(jq -c '. + ["pending-claim"]' <<< "$hints")
        ;;
      *block*)
        hints=$(jq -c '. + ["blocked-claim"]' <<< "$hints")
        ;;
    esac
  done < "$path"
  jq -c 'unique' <<< "$hints"
}

plan_source_related_artifacts() {
  local path="$1" directory filename stem related='[]' sibling canonical
  directory=$(dirname "$path")
  filename=$(basename "$path")
  stem="$filename"
  stem="${stem%-PLAN.md}"
  stem="${stem%PLAN.md}"
  for sibling in "$directory/${stem}-SUMMARY.md" "$directory/${stem}SUMMARY.md" "$directory/${stem}-VERIFICATION.md"; do
    [ -f "$sibling" ] || continue
    canonical=$(plan_source_canonical_file "$sibling") || continue
    related=$(jq -c --arg path "$canonical" '. + [$path]' <<< "$related")
  done
  jq -c 'unique' <<< "$related"
}

plan_source_detection_evidence() {
  local evidence="$1"
  jq -Rsc 'split("\n") | map(select(length > 0))' <<< "$evidence"
}

plan_source_collect_lbwc() {
  local project_root="$1" planning_dir
  planning_dir="$project_root/.lbwc-planning"
  [ -d "$planning_dir" ] || return 0
  find "$planning_dir" \
    \( -path "$planning_dir/.cache" -o -path "$planning_dir/milestones" \) -prune -o \
    -type f \( -name 'PLAN.md' -o -name '*-PLAN.md' \) -print 2>/dev/null | LC_ALL=C sort
}

plan_source_collect_gsd() {
  local project_root="$1" planning_dir
  planning_dir="$project_root/.planning"
  [ -d "$planning_dir/phases" ] || return 0
  find "$planning_dir/phases" -type f \( -name 'PLAN.md' -o -name '*-PLAN.md' \) \
    -print 2>/dev/null | LC_ALL=C sort
}

plan_source_collect_external_codebase() {
  local project_root="$1" codebase_dir
  codebase_dir="$project_root/.planning/codebase"
  [ -d "$codebase_dir" ] || return 0
  find "$codebase_dir" -type f -print 2>/dev/null | LC_ALL=C sort
}

plan_source_collect_claude() {
  local plans_dir="$1" cap="$2" max_file_bytes="$3" max_total_bytes="$4" path epoch size total=0 count=0
  [ -d "$plans_dir" ] || return 0
  {
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      size=$(plan_source_size_bytes "$path") || continue
      [ "$size" -le "$max_file_bytes" ] || continue
      epoch=$(plan_source_mtime_epoch "$path") || continue
      printf '%s\t%s\t%s\n' "$epoch" "$size" "$path"
    done < <(find "$plans_dir" -type f -name '*.md' -print 2>/dev/null)
  } | LC_ALL=C sort -t $'\t' -k1,1nr -k3,3 | while IFS=$'\t' read -r epoch size path; do
    [ "$count" -lt "$cap" ] || break
    [ $((total + size)) -le "$max_total_bytes" ] || continue
    printf '%s\n' "$path"
    total=$((total + size))
    count=$((count + 1))
  done
}

plan_source_collect_generic_markdown() {
  local project_root="$1" cap="$2" exclude_dir="$3" max_file_bytes="$4" max_total_bytes="$5" path epoch size total=0 count=0
  {
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      size=$(plan_source_size_bytes "$path") || continue
      [ "$size" -le "$max_file_bytes" ] || continue
      epoch=$(plan_source_mtime_epoch "$path") || continue
      printf '%s\t%s\t%s\n' "$epoch" "$size" "$path"
    done < <(
      find "$project_root" \
        \( -path "$project_root/.git" -o -path "$project_root/.lbwc-planning" \
           -o -path "$project_root/.temporary-agent-runfiles" -o -path "$project_root/.planning" \
           -o -path "$project_root/.claude" -o -path "$project_root/node_modules" \
           -o -path "$project_root/.kilo" -o -path "$project_root/vendor" \
           -o -path "$project_root/target" \
           ${exclude_dir:+-o -path "$exclude_dir"} \) -prune -o \
        -type f -name '*.md' -print 2>/dev/null
    )
  } | LC_ALL=C sort -t $'\t' -k1,1nr -k3,3 | while IFS=$'\t' read -r epoch size path; do
    [ "$count" -lt "$cap" ] || break
    [ $((total + size)) -le "$max_total_bytes" ] || continue
    printf '%s\n' "$path"
    total=$((total + size))
    count=$((count + 1))
  done
}
