#!/usr/bin/env bash

# Extract a single scalar from YAML frontmatter. This intentionally matches
# compile-verify-context.sh's simple frontmatter lookup for plan identity.
extract_frontmatter_scalar_value() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function strip_quotes(v, first, last) {
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if (first == "\"" && last == "\"") return substr(v, 2, length(v) - 2)
      if (first == squote && last == squote) {
        v = substr(v, 2, length(v) - 2); gsub(squote squote, squote, v)
        return v
      }
      return v
    }
    BEGIN { in_fm = 0; squote = sprintf("%c", 39) }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      value = $0
      sub("^" key ":[[:space:]]*", "", value)
      value = strip_quotes(trim(value))
      if (value != "") print value
      exit
    }
  ' "$file_path" 2>/dev/null
}

summary_plan_id_from_plan_file() {
  local plan_file="${1:-}"
  local plan_id=""
  local round_id=""
  local plan_base=""
  [ -f "$plan_file" ] || return 0

  plan_id=$(extract_frontmatter_scalar_value "$plan_file" plan | head -1)
  if [ -z "$plan_id" ]; then
    plan_base=$(basename "$plan_file")
    case "$plan_base" in
      R*-PLAN.md)
        plan_id="${plan_base%-PLAN.md}"
        ;;
      *)
        round_id=$(extract_frontmatter_scalar_value "$plan_file" round | head -1)
        if [ -n "$round_id" ]; then
          plan_id="R${round_id}"
        fi
        ;;
    esac
  fi

  printf '%s\n' "${plan_id:-unknown}"
}

source_plan_ids_for_summary() {
  local summary_file="${1:-}"
  local summary_dir=""
  local summary_base=""
  local summary_prefix=""
  local round_summary_base=""
  local plan_file=""

  [ -f "$summary_file" ] || return 0
  summary_dir=$(dirname "$summary_file")
  summary_base=$(basename "$summary_file")

  if [ "$summary_base" = "SUMMARY.md" ]; then
    plan_file="$summary_dir/PLAN.md"
    [ -f "$plan_file" ] && summary_plan_id_from_plan_file "$plan_file"
    return 0
  fi

  case "$summary_base" in
    *-SUMMARY.md)
      summary_prefix="${summary_base%-SUMMARY.md}"
      ;;
    *)
      return 0
      ;;
  esac

  if [[ "$summary_dir" == */round-* ]] && [[ "$summary_prefix" =~ ^R[0-9][0-9]$ ]]; then
    round_summary_base="$summary_prefix"
    while IFS= read -r plan_file; do
      [ -f "$plan_file" ] || continue
      summary_plan_id_from_plan_file "$plan_file"
    done < <(find "$summary_dir" -maxdepth 1 ! -name '.*' \( -name "${round_summary_base}-PLAN.md" -o -name "${round_summary_base}-*-PLAN.md" \) 2>/dev/null | (sort -V 2>/dev/null || sort))
    return 0
  fi

  plan_file="$summary_dir/${summary_prefix}-PLAN.md"
  [ -f "$plan_file" ] && summary_plan_id_from_plan_file "$plan_file"
}

summary_deviation_matches_any_signature() {
  local accepted_signatures="${1:-}"
  local source_plan_ids="${2:-}"
  local source_path="${3:-}"
  local deviation_text="${4:-}"
  local source_plan_id=""
  local signature=""
  while IFS= read -r source_plan_id; do
    [ -n "$source_plan_id" ] || continue
    signature=$(bash "$TRACK_UAT_DEVIATIONS_SCRIPT" signature "$source_plan_id" "$source_path" "$deviation_text" 2>/dev/null || true)
    [ -n "$signature" ] || return 1
    if printf '%s\n' "$accepted_signatures" | grep -Fx -- "$signature" >/dev/null 2>&1; then
      return 0
    fi
  done <<< "$source_plan_ids"
  return 1
}

round_classification_scan_is_valid() {
  local phase_dir="${1:-}"
  local scan_dir="${2:-}"
  local summary_file="${3:-}"
  local deviation_text="${4:-}"
  local round_plan_dir="${5:-}"
  phase_dir="${phase_dir%/}"
  scan_dir="${scan_dir%/}"
  round_plan_dir="${round_plan_dir%/}"
  [ -n "$phase_dir" ] && [ -n "$scan_dir" ] && [ -n "$round_plan_dir" ] || return 1
  [ "$scan_dir" != "$phase_dir" ] && [ "$scan_dir" = "$round_plan_dir" ] || return 1
  [ -d "$round_plan_dir" ] && [ -f "$summary_file" ] && [ -n "$deviation_text" ] || return 1
  case "$summary_file" in
    "$scan_dir"/*) return 0 ;;
    *) return 1 ;;
  esac
}

round_classification_pair_matches_deviation() {
  local deviation_text="${1:-}"
  local classified_pairs="${2:-}"
  local classification_id=""
  local classification_type=""
  local bare_id=""
  # Invariant: no rejected pair has matched, variant: unread classification pairs.
  while IFS=$'\t' read -r classification_id classification_type; do
    [ -n "$classification_id" ] && [ -n "$classification_type" ] || return 1
    case "$classification_type" in
      process-exception|plan-amendment)
        bare_id="${classification_id#FAIL-}"
        [[ "$bare_id" =~ ^[[:alnum:]_.-]+$ ]] || return 1
        if printf '%s\n' "$deviation_text" | grep -Fw -- "$bare_id" >/dev/null 2>&1 \
          || printf '%s\n' "$deviation_text" | grep -Fw -- "FAIL-$bare_id" >/dev/null 2>&1; then
          return 0
        fi
        ;;
      code-fix|doc-fix) ;;
      *) return 1 ;;
    esac
  done <<< "$classified_pairs"
  return 1
}

summary_deviation_matches_round_classification() {
  local phase_dir="${1:-}"
  local scan_dir="${2:-}"
  local summary_file="${3:-}"
  local deviation_text="${4:-}"
  local round_plan_dir="${5:-}"
  local classified_pairs=""
  round_classification_scan_is_valid "$phase_dir" "$scan_dir" "$summary_file" "$deviation_text" "$round_plan_dir" || return 1
  type collect_fail_classification_id_type_pairs_in_dir >/dev/null 2>&1 || return 1
  classified_pairs=$(collect_fail_classification_id_type_pairs_in_dir "$round_plan_dir" 2>/dev/null) || return 1
  [ -n "$classified_pairs" ] || return 1
  round_classification_pair_matches_deviation "$deviation_text" "$classified_pairs"
}

summary_deviation_is_accepted() {
  local phase_dir="${1:-}"
  local summary_file="${2:-}"
  local deviation_text="${3:-}"
  local accepted_signatures="${4:-}"
  local source_path=""
  local source_plan_ids=""

  [ -n "$accepted_signatures" ] || return 1
  [ -x "$TRACK_UAT_DEVIATIONS_SCRIPT" ] || return 1
  [ -f "$summary_file" ] || return 1
  [ -n "$deviation_text" ] || return 1

  phase_dir="${phase_dir%/}"
  source_path="${summary_file#"$phase_dir/"}"
  [ -n "$source_path" ] || return 1

  if type summary_deviation_source_plan_candidates >/dev/null 2>&1; then
    source_plan_ids=$(summary_deviation_source_plan_candidates "$summary_file" 2>/dev/null || true)
  else
    source_plan_ids=$(source_plan_ids_for_summary "$summary_file")
  fi
  [ -n "$source_plan_ids" ] || return 1

  summary_deviation_matches_any_signature "$accepted_signatures" "$source_plan_ids" "$source_path" "$deviation_text"
}

count_yaml_summary_deviations() {
  extract_frontmatter_array_items "${1:-}" deviations | awk '
    { lc=tolower($0); if (lc ~ /^none\.?$/ || lc ~ /^n\/a\.?$/ || lc ~ /^na\.?$/ || lc ~ /^no deviations/) next; count++ }
    END { print count + 0 }
  ' 2>/dev/null
}

count_body_summary_deviations() {
  awk '
    BEGIN { count=0; found=0 }
    /^## Deviations/ || /^### Deviations/ { found=1; in_comment=0; next }
    found && (/^## / || /^### /) { found=0; next }
    found && /^[[:space:]]*$/ { next }
    found && /^[[:space:]]*<!--/ {
      in_comment=1
      if ($0 ~ /-->/) in_comment=0
      next
    }
    found && in_comment {
      if ($0 ~ /-->/) in_comment=0
      next
    }
    found {
      line=$0
      sub(/^- /, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
      sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
      if (line == "") next
      lc = tolower(line)
      if (lc ~ /^none(\.[[:space:]].*|\.?)$/ || lc ~ /^n\/a(\.[[:space:]].*|\.?)$/ || lc ~ /^na(\.[[:space:]].*|\.?)$/ || lc ~ /^no deviations($|[.:].*)/) next
      count++
    }
    END { print count }
  ' "${1:-}" 2>/dev/null
}

count_summary_fallback_deviations() {
  local summary_file="${1:-}"
  local yaml_count=""
  yaml_count=$(count_yaml_summary_deviations "$summary_file")
  if [ "${yaml_count:-0}" -eq 0 ] 2>/dev/null; then
    count_body_summary_deviations "$summary_file"
  else
    printf '%s\n' "$yaml_count"
  fi
}

count_deviations_in_summary() {
  local phase_dir="${1:-}"
  local scan_dir="${2:-}"
  local summary_file="${3:-}"
  local round_plan_dir="${4:-}"
  local accepted_signatures="${5:-}"
  local deviations=0
  if type extract_summary_deviations >/dev/null 2>&1; then
    while IFS= read -r deviation_text; do
      [ -n "$deviation_text" ] || continue
      if summary_deviation_is_accepted "$phase_dir" "$summary_file" "$deviation_text" "$accepted_signatures"; then
        continue
      fi
      if [ -n "$round_plan_dir" ] && summary_deviation_matches_round_classification \
        "$phase_dir" "$scan_dir" "$summary_file" "$deviation_text" "$round_plan_dir"; then
        continue
      fi
      deviations=$((deviations + 1))
    done < <(extract_summary_deviations "$summary_file" 2>/dev/null || true)
  else
    deviations=$(count_summary_fallback_deviations "$summary_file")
  fi
  printf '%s\n' "$deviations"
}

# Count active, non-placeholder deviations across SUMMARY.md files in a given directory.
# Accepted UAT process exceptions are suppressed using the same signature identity
# emitted by compile-verify-context.sh; when that identity cannot be derived, the
# gate fails closed and counts the deviation as active.
# Arguments: $1 = phase directory, $2 = directory to scan for SUMMARY.md files
count_deviations_in_dir() {
  local phase_dir="${1:-}"
  local scan_dir="${2:-${1:-}}"
  local round_plan_dir="${3:-}"
  local accepted_signatures=""
  local total=0
  [ -d "$scan_dir" ] || { echo 0; return; }
  if [ -x "$TRACK_UAT_DEVIATIONS_SCRIPT" ]; then
    accepted_signatures=$(bash "$TRACK_UAT_DEVIATIONS_SCRIPT" accepted-signatures "$phase_dir" 2>/dev/null || true)
  fi
  while IFS= read -r summary_file; do
    [ -f "$summary_file" ] || continue
    total=$((total + $(count_deviations_in_summary "$phase_dir" "$scan_dir" "$summary_file" "$round_plan_dir" "$accepted_signatures")))
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  echo "$total"
}
