#!/usr/bin/env bash

set -euo pipefail

extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" -f "${_CVC_SCRIPT_DIR}/extract-frontmatter-array-items.awk" "$file_path" 2>/dev/null
}

frontmatter_key_present() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 1
  [ -n "$key_name" ] || return 1
  awk -v key="$key_name" '
    BEGIN { in_fm = 0; found = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file_path" >/dev/null 2>&1
}

_CVC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_CVC_SCRIPT_DIR/summary-utils.sh" ]; then
  . "$_CVC_SCRIPT_DIR/summary-utils.sh"
else
  is_summary_terminal() { [ -f "$1" ]; }
fi

sanitize_summary_deviation_context_field() {
  printf '%s' "${1:-}" | tr '\r\n|' '   ' | awk '{ gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); print }'
}

REMEDIATION_ONLY=false
REMEDIATION_KIND=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --remediation-only) REMEDIATION_ONLY=true; shift ;;
    --remediation-kind)
      if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
        echo "error: --remediation-kind requires a value (qa or uat)" >&2
        exit 1
      fi
      REMEDIATION_KIND="$2"
      shift 2
      ;;
    --remediation-kind=*)
      REMEDIATION_KIND="${1#--remediation-kind=}"
      if [ -z "$REMEDIATION_KIND" ]; then
        echo "error: --remediation-kind requires a value (qa or uat)" >&2; exit 1
      fi
      shift
      ;;
    *) break ;;
  esac
done

if [ -n "$REMEDIATION_KIND" ]; then
  case "$REMEDIATION_KIND" in
    qa|uat) ;;
    *) echo "error: --remediation-kind must be 'qa' or 'uat', got: $REMEDIATION_KIND" >&2; exit 1 ;;
  esac
fi

PHASE_DIR="${1:?Usage: compile-verify-context.sh [--remediation-only] [--remediation-kind qa|uat] phase-dir}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "verify_context_error=no_phase_dir"
  exit 0
fi

find_active_qa_remediation_candidate() {
  local stage
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ] && [ "$REMEDIATION_KIND" != "uat" ] || return 1
  stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  case "${stage:-none}" in
    verify|done) ;;
    *) return 1 ;;
  esac
  _cvc_candidates+=("$PHASE_DIR/remediation/qa")
  _cvc_preferred_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  if ! [[ "${_cvc_preferred_round:-}" =~ ^[0-9]+$ ]]; then
    _cvc_preferred_round=""
  elif [ -n "$_cvc_preferred_round" ]; then
    _cvc_preferred_round=$(printf '%02d' "$((10#$_cvc_preferred_round))")
  fi
  _cvc_preferred_kind="qa"
  _active_remediation=true
}

find_active_uat_remediation_candidate() {
  local stage
  [ -f "$PHASE_DIR/remediation/uat/.uat-remediation-stage" ] && [ "$REMEDIATION_KIND" != "qa" ] || return 1
  [ "$_active_remediation" = false ] || return 1
  stage=$(grep '^stage=' "$PHASE_DIR/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  case "${stage:-none}" in
    research|plan|execute|fix|verify|done) ;;
    *) return 1 ;;
  esac
  _cvc_candidates+=("$PHASE_DIR/remediation/uat")
  _cvc_preferred_round=$(grep '^round=' "$PHASE_DIR/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  if ! [[ "${_cvc_preferred_round:-}" =~ ^[0-9]+$ ]]; then
    _cvc_preferred_round=""
  elif [ -n "$_cvc_preferred_round" ]; then
    _cvc_preferred_round=$(printf '%02d' "$((10#$_cvc_preferred_round))")
  fi
  _cvc_preferred_kind="uat"
  _active_remediation=true
}

fallback_remediation_candidates() {
  if [ "$REMEDIATION_KIND" = "uat" ]; then
    _cvc_candidates+=("$PHASE_DIR/remediation/uat")
  elif [ "$REMEDIATION_KIND" = "qa" ]; then
    _cvc_candidates+=("$PHASE_DIR/remediation/qa")
  else
    _cvc_candidates+=("$PHASE_DIR/remediation/uat" "$PHASE_DIR/remediation/qa")
  fi
}

resolve_remediation_candidates() {
  _cvc_candidates=()
  _active_remediation=false
  find_active_qa_remediation_candidate || true
  find_active_uat_remediation_candidate || true
  if [ "$_active_remediation" = false ]; then
    fallback_remediation_candidates
  fi
  return 0
}

pick_preferred_qa_round() {
  local candidate="$1" preferred_round_dir
  [ "$candidate" = "$PHASE_DIR/remediation/qa" ] && [ "$_cvc_preferred_kind" = "qa" ] && [ -n "$_cvc_preferred_round" ] || return 1
  preferred_round_dir="$candidate/round-$_cvc_preferred_round"
  if [ -d "$preferred_round_dir" ] && \
     ls "$preferred_round_dir"/R"$_cvc_preferred_round"-PLAN.md >/dev/null 2>&1 && \
     ls "$preferred_round_dir"/R"$_cvc_preferred_round"-SUMMARY.md >/dev/null 2>&1 && \
     is_summary_terminal "$preferred_round_dir/R${_cvc_preferred_round}-SUMMARY.md"; then
    LATEST_ROUND="$_cvc_preferred_round"
    REMED_DIR="$candidate"
    REMED_KIND="qa"
    return 0
  fi
  REMEDIATION_ONLY=false
  return 0
}

pick_preferred_uat_round() {
  local candidate="$1"
  [ "$candidate" = "$PHASE_DIR/remediation/uat" ] && [ "$_cvc_preferred_kind" = "uat" ] && [ -n "$_cvc_preferred_round" ] || return 1
  LATEST_ROUND="$_cvc_preferred_round"
  REMED_DIR="$candidate"
  REMED_KIND="uat"
}

pick_latest_terminal_round() {
  local candidate="$1" best_round_num=0 candidate_round="" round_dir round_num rr
  for round_dir in "$candidate"/round-*/; do
    [ -d "$round_dir" ] || continue
    round_num=$(basename "$round_dir" | sed 's/^round-0*//')
    round_num=${round_num:-0}
    rr=$(printf '%02d' "$round_num")
    if [ "$round_num" -gt "$best_round_num" ] 2>/dev/null && \
       ls "$round_dir"/R"${rr}"-PLAN.md >/dev/null 2>&1 && \
       ls "$round_dir"/R"${rr}"-SUMMARY.md >/dev/null 2>&1 && \
       is_summary_terminal "$round_dir/R${rr}-SUMMARY.md"; then
      best_round_num="$round_num"
      candidate_round="$rr"
    fi
  done
  [ -n "$candidate_round" ] || return 1
  LATEST_ROUND="$candidate_round"
  REMED_DIR="$candidate"
  case "$candidate" in
    */remediation/uat) REMED_KIND="uat" ;;
    */remediation/qa) REMED_KIND="qa" ;;
  esac
}

resolve_latest_remediation_round() {
  local candidate
  for candidate in "${_cvc_candidates[@]}"; do
    [ -d "$candidate" ] || continue
    if pick_preferred_qa_round "$candidate"; then
      [ -n "$LATEST_ROUND" ] && return 0
      [ "$REMEDIATION_ONLY" = false ] && return 0
    fi
    if pick_preferred_uat_round "$candidate"; then
      return 0
    fi
    if pick_latest_terminal_round "$candidate"; then
      return 0
    fi
  done
  return 1
}

resolve_legacy_remediation_round() {
  local best_round_num=0 round_dir round_num rr
  [ -z "$LATEST_ROUND" ] && [ -d "$PHASE_DIR/remediation" ] && [ "$REMEDIATION_KIND" != "qa" ] || return 0
  REMED_DIR="$PHASE_DIR/remediation"
  REMED_KIND="legacy"
  for round_dir in "$REMED_DIR"/round-*/; do
    [ -d "$round_dir" ] || continue
    round_num=$(basename "$round_dir" | sed 's/^round-0*//')
    round_num=${round_num:-0}
    rr=$(printf '%02d' "$round_num")
    if [ "$round_num" -gt "$best_round_num" ] 2>/dev/null && \
       ls "$round_dir"/R"${rr}"-PLAN.md >/dev/null 2>&1 && \
       ls "$round_dir"/R"${rr}"-SUMMARY.md >/dev/null 2>&1 && \
       is_summary_terminal "$round_dir/R${rr}-SUMMARY.md"; then
      best_round_num="$round_num"
      LATEST_ROUND="$rr"
    fi
  done
}

resolve_remediation_scope() {
  LATEST_ROUND=""
  REMED_DIR=""
  REMED_KIND=""
  _cvc_preferred_round=""
  _cvc_preferred_kind=""

  resolve_remediation_candidates
  resolve_latest_remediation_round || true
  resolve_legacy_remediation_round

  if [ -n "$LATEST_ROUND" ]; then
    local rr
    rr=$(printf '%02d' "$((10#$LATEST_ROUND))")
    ALL_PLAN_FILES=$(find "$REMED_DIR/round-$rr" -maxdepth 1 \( -name "R${rr}-PLAN.md" -o -name "R${rr}-*-PLAN.md" \) 2>/dev/null | sort)
    SCOPE_HEADER="verify_scope=remediation round=$rr"
    case "$REMED_KIND" in
      qa)
        UAT_PATH=$(bash "${_CVC_SCRIPT_DIR}/resolve-artifact-path.sh" uat "$PHASE_DIR")
        ;;
      *)
        UAT_PATH="${REMED_DIR#"$PHASE_DIR/"}/round-$rr/R${rr}-UAT.md"
        ;;
    esac
  else
    REMEDIATION_ONLY=false
  fi
}

if [ "$REMEDIATION_ONLY" = true ]; then
  resolve_remediation_scope
fi

resolve_full_scope() {
  local plan_files round_plan_files qa_round_plan_files extra_plans
  plan_files=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | sort)
  round_plan_files=$(find "$PHASE_DIR" -path '*/remediation/uat/round-*/R*-PLAN.md' 2>/dev/null | sort)
  if [ -z "$round_plan_files" ]; then
    round_plan_files=$(find "$PHASE_DIR" -path '*/remediation/round-*/R*-PLAN.md' 2>/dev/null | sort)
  fi

  qa_round_plan_files=$(find "$PHASE_DIR" -path '*/remediation/qa/round-*/R*-PLAN.md' 2>/dev/null | sort)

  ALL_PLAN_FILES="$plan_files"
  for extra_plans in "$round_plan_files" "$qa_round_plan_files"; do
    if [ -n "$extra_plans" ]; then
      if [ -n "$ALL_PLAN_FILES" ]; then
        ALL_PLAN_FILES=$(printf '%s\n%s' "$ALL_PLAN_FILES" "$extra_plans")
      else
        ALL_PLAN_FILES="$extra_plans"
      fi
    fi
  done
  SCOPE_HEADER="verify_scope=full"
  UAT_PATH=$(bash "${_CVC_SCRIPT_DIR}/resolve-artifact-path.sh" uat "$PHASE_DIR")
}

if [ "$REMEDIATION_ONLY" = false ]; then
  resolve_full_scope
fi

if [ -z "$ALL_PLAN_FILES" ]; then
  echo "verify_context=empty"
  exit 0
fi

echo "$SCOPE_HEADER"
echo "uat_path=$UAT_PATH"

PLAN_COUNT=0
ACCEPTED_DEVIATION_SIGNATURES=""
EMITTED_SUMMARY_DEVIATION_SIGNATURES=""
TRACK_UAT_DEVIATIONS_SCRIPT="$_CVC_SCRIPT_DIR/track-uat-deviations.sh"
if [ -x "$TRACK_UAT_DEVIATIONS_SCRIPT" ]; then
  ACCEPTED_DEVIATION_SIGNATURES=$(bash "$TRACK_UAT_DEVIATIONS_SCRIPT" accepted-signatures "$PHASE_DIR" 2>/dev/null || true)
fi

resolve_plan_id() {
  local plan_file="$1" plan_id
  plan_id=$(awk '/^---$/{n++; next} n==1 && /^plan:/{v=$2; gsub(/^["'"'"']|["'"'"']$/, "", v); print v; exit}' "$plan_file" 2>/dev/null) || plan_id=""
  if [ -z "$plan_id" ]; then
    case "$(basename "$plan_file")" in
      R*-PLAN.md) plan_id="$(basename "$plan_file" | sed 's/-PLAN\.md$//')" ;;
      *)
        plan_id=$(awk '/^---$/{n++; next} n==1 && /^round:/{v=$2; gsub(/^["'"'"']|["'"'"']$/, "", v); print "R" v; exit}' "$plan_file" 2>/dev/null) || plan_id=""
        ;;
    esac
  fi
  printf '%s' "$plan_id"
}

extract_must_haves() {
  local plan_file="$1"
  awk '
    BEGIN { in_front=0; in_mh=0; in_sub=0 }
    /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
    in_front && /^must_haves:/ { in_mh=1; next }
    in_front && in_mh && /^[[:space:]]+truths:/ { in_sub=1; next }
    in_front && in_mh && /^[[:space:]]+artifacts:/ { in_sub=1; next }
    in_front && in_mh && /^[[:space:]]+key_links:/ { in_sub=1; next }
    in_front && in_mh && in_sub && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      items = items (items ? "; " : "") line
      next
    }
    in_front && in_mh && !in_sub && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      items = items (items ? "; " : "") line
      next
    }
    in_front && in_mh && /^[^[:space:]]/ && !/^[[:space:]]+/ { exit }
    END { print items }
  ' "$plan_file" 2>/dev/null
}

resolve_summary_file() {
  local plan_file="$1" plan_base plan_dir
  plan_base=$(basename "$plan_file" | sed 's/-PLAN\.md$//')
  plan_dir=$(dirname "$plan_file")
  if [ "$(basename "$plan_file")" = "PLAN.md" ] && [ -f "$plan_dir/SUMMARY.md" ]; then
    printf '%s' "$plan_dir/SUMMARY.md"
  elif [[ "$plan_dir" == */round-* ]] && [[ "$plan_base" =~ ^R[0-9][0-9](-.*)?$ ]]; then
    local round_summary_base
    round_summary_base=$(printf '%s' "$plan_base" | sed 's/^\(R[0-9][0-9]\).*/\1/')
    printf '%s' "$plan_dir/${round_summary_base}-SUMMARY.md"
  else
    find "$plan_dir" -maxdepth 1 ! -name '.*' -name "${plan_base}-SUMMARY.md" 2>/dev/null | head -1
  fi
}

extract_what_built() {
  local summary_file="$1" what_built
  what_built=$(awk '
    /^## What Was Built/ { found=1; count=0; next }
    found && /^## / { exit }
    found && /^[[:space:]]*$/ { next }
    found { count++; if (count <= 5) print; if (count >= 5) exit }
  ' "$summary_file" 2>/dev/null) || what_built=""
  if [ -z "$what_built" ]; then
    what_built=$(awk '
      /^### What Was Built/ { found=1; next }
      found && /^### / { found=0; next }
      found && /^## / { found=0; next }
      found && /^[[:space:]]*$/ { next }
      found {
        count++
        if (count <= 5) print
      }
    ' "$summary_file" 2>/dev/null) || what_built=""
  fi
  printf '%s' "$what_built"
}

extract_files_modified() {
  local summary_file="$1" files_modified
  files_modified=$(extract_frontmatter_array_items "$summary_file" files_modified | awk '
    {
      files = files (files ? ", " : "") $0
    }
    END { print files }
  ' 2>/dev/null) || files_modified=""
  if [ -z "$files_modified" ]; then
    files_modified=$(awk '
      /^## Files Modified/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line = $0
        sub(/^- /, "", line)
        if (index(line, " -- ") > 0) {
          line = substr(line, 1, index(line, " -- ") - 1)
        }
        gsub(/`/, "", line)
        files = files (files ? ", " : "") line
      }
      END { print files }
    ' "$summary_file" 2>/dev/null) || files_modified=""
  fi
  printf '%s' "$files_modified"
}

extract_pre_existing_issues() {
  local summary_file="$1" pre_existing
  pre_existing=$(extract_frontmatter_array_items "$summary_file" pre_existing_issues | while IFS= read -r item; do
    [ -n "$item" ] || continue
    if ! printf '%s' "$item" | jq -e '
      type == "object"
      and (.test | type == "string")
      and (.file | type == "string")
      and (.error | type == "string")
    ' >/dev/null 2>&1; then
      continue
    fi
    _pre_test=$(printf '%s' "$item" | jq -r '.test')
    _pre_file=$(printf '%s' "$item" | jq -r '.file')
    _pre_error=$(printf '%s' "$item" | jq -r '.error')
    if [ "$_pre_file" = "$_pre_test" ]; then
      printf '%s: %s\n' "$_pre_test" "$_pre_error"
    else
      printf '%s (%s): %s\n' "$_pre_test" "$_pre_file" "$_pre_error"
    fi
  done | awk '
    {
      items = items (items ? "; " : "") $0
    }
    END { print items }
  ' 2>/dev/null) || pre_existing=""

  if [ -z "$pre_existing" ] && ! frontmatter_key_present "$summary_file" pre_existing_issues; then
    pre_existing=$(awk '
      /^## Pre-existing Issues/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line = $0
        sub(/^- /, "", line)
        items = items (items ? "; " : "") line
      }
      END { print items }
    ' "$summary_file" 2>/dev/null) || pre_existing=""
  fi
  printf '%s' "$pre_existing"
}

record_summary_deviation() {
  local deviation="$1" source_plan="$2" summary_rel_path="$3"
  local signature accepted=false candidate_source_plans candidate_source_plan candidate_signature
  local safe_plan safe_path safe_text

  signature=$(bash "$TRACK_UAT_DEVIATIONS_SCRIPT" signature "$source_plan" "$summary_rel_path" "$deviation" 2>/dev/null || true)
  [ -n "$signature" ] || return 0

  if [ -n "$ACCEPTED_DEVIATION_SIGNATURES" ]; then
    candidate_source_plans="$source_plan"
    if type summary_deviation_source_plan_candidates >/dev/null 2>&1; then
      candidate_source_plans=$(summary_deviation_source_plan_candidates "$SUMMARY_FILE" 2>/dev/null || true)
      candidate_source_plans="${candidate_source_plans:-$source_plan}"
    fi
    while IFS= read -r candidate_source_plan; do
      [ -n "$candidate_source_plan" ] || continue
      candidate_signature=$(bash "$TRACK_UAT_DEVIATIONS_SCRIPT" signature "$candidate_source_plan" "$summary_rel_path" "$deviation" 2>/dev/null || true)
      [ -n "$candidate_signature" ] || break
      if printf '%s\n' "$ACCEPTED_DEVIATION_SIGNATURES" | grep -Fx -- "$candidate_signature" >/dev/null 2>&1; then
        accepted=true
        break
      fi
    done <<< "$candidate_source_plans"
  fi
  [ "$accepted" = true ] && return 0

  if [ -n "$EMITTED_SUMMARY_DEVIATION_SIGNATURES" ] && printf '%s\n' "$EMITTED_SUMMARY_DEVIATION_SIGNATURES" | grep -Fx -- "$signature" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$EMITTED_SUMMARY_DEVIATION_SIGNATURES" ]; then
    EMITTED_SUMMARY_DEVIATION_SIGNATURES="${EMITTED_SUMMARY_DEVIATION_SIGNATURES}"$'\n'
  fi
  EMITTED_SUMMARY_DEVIATION_SIGNATURES="${EMITTED_SUMMARY_DEVIATION_SIGNATURES}${signature}"

  safe_plan=$(sanitize_summary_deviation_context_field "$source_plan")
  safe_path=$(sanitize_summary_deviation_context_field "$summary_rel_path")
  safe_text=$(sanitize_summary_deviation_context_field "$deviation")
  if [ -n "$SUMMARY_DEVIATION_RECORDS" ]; then
    SUMMARY_DEVIATION_RECORDS="${SUMMARY_DEVIATION_RECORDS}"$'\n'
  fi
  SUMMARY_DEVIATION_RECORDS="${SUMMARY_DEVIATION_RECORDS}SUMMARY_DEVIATION: signature=${signature} | source_plan=${safe_plan} | source_path=${safe_path} | text=${safe_text}"
}

collect_summary_deviations() {
  local plan_id="$1"
  [ -n "$SUMMARY_DEVIATIONS" ] && [ -x "$TRACK_UAT_DEVIATIONS_SCRIPT" ] || return 0
  local summary_rel_path source_plan deviation
  summary_rel_path="${SUMMARY_FILE#"$PHASE_DIR/"}"
  while IFS= read -r deviation; do
    [ -n "$deviation" ] || continue
    source_plan="${plan_id:-unknown}"
    if type summary_deviation_canonical_source_plan >/dev/null 2>&1; then
      source_plan=$(summary_deviation_canonical_source_plan "$SUMMARY_FILE" 2>/dev/null || true)
      source_plan="${source_plan:-unknown}"
    fi
    record_summary_deviation "$deviation" "$source_plan" "$summary_rel_path"
  done <<< "$SUMMARY_DEVIATIONS"
}

read_summary_fields() {
  local summary_file="$1"
  STATUS=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
  ' "$summary_file" 2>/dev/null) || STATUS="unknown"

  FILES_MODIFIED=$(extract_files_modified "$summary_file")
  WHAT_BUILT=$(extract_what_built "$summary_file")

  SUMMARY_DEVIATIONS=""
  DEVIATIONS=""
  if type extract_summary_deviations >/dev/null 2>&1; then
    SUMMARY_DEVIATIONS=$(extract_summary_deviations "$summary_file" 2>/dev/null || true)
    DEVIATIONS=$(printf '%s\n' "$SUMMARY_DEVIATIONS" | awk 'NF { items = items (items ? "; " : "") $0 } END { print items }')
  fi

  PRE_EXISTING=$(extract_pre_existing_issues "$summary_file")
}

print_plan_record() {
  local plan_id="$1" title="$2" must_haves="$3"

  echo "=== PLAN ${plan_id}: ${title} ==="
  echo "must_haves: ${must_haves:-none}"
  if [ -n "$WHAT_BUILT" ]; then
    echo "what_was_built:"
    echo "$WHAT_BUILT" | sed 's/^/  /'
  else
    echo "what_was_built: none"
  fi
  echo "files_modified: ${FILES_MODIFIED:-none}"
  echo "status: ${STATUS}"
  echo "deviations: ${DEVIATIONS:-none}"
  if [ -n "$SUMMARY_DEVIATION_RECORDS" ]; then
    printf '%s\n' "$SUMMARY_DEVIATION_RECORDS"
  else
    echo "summary_deviation_reviews: none"
  fi
  echo "pre_existing_issues: ${PRE_EXISTING:-none}"
  echo ""
}

process_plan_file() {
  local plan_file="$1"
  local plan_id title must_haves

  plan_id=$(resolve_plan_id "$plan_file")
  title=$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title: */, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit}' "$plan_file" 2>/dev/null) || title=""
  must_haves=$(extract_must_haves "$plan_file")

  SUMMARY_FILE=$(resolve_summary_file "$plan_file")
  STATUS="no_summary"
  WHAT_BUILT=""
  FILES_MODIFIED=""
  DEVIATIONS=""
  PRE_EXISTING=""
  SUMMARY_DEVIATIONS=""
  SUMMARY_DEVIATION_RECORDS=""

  if [ -n "$SUMMARY_FILE" ] && [ -f "$SUMMARY_FILE" ]; then
    read_summary_fields "$SUMMARY_FILE"
    collect_summary_deviations "$plan_id"
  fi

  print_plan_record "$plan_id" "$title" "$must_haves"
}

while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
  process_plan_file "$plan_file"
done <<< "$ALL_PLAN_FILES"

print_known_issues_section() {
  local known_issues_path="$PHASE_DIR/known-issues.json" known_issue_count
  [ -f "$known_issues_path" ] || return 0

  if jq -e '.issues | type == "array"' "$known_issues_path" >/dev/null 2>&1; then
    known_issue_count=$(jq '.issues | length' "$known_issues_path" 2>/dev/null || echo 0)
    if [ "${known_issue_count:-0}" -gt 0 ] 2>/dev/null; then
      echo "=== KNOWN ISSUES ==="
      echo "known_issues_path=$(basename "$known_issues_path")"
      echo "known_issue_count=${known_issue_count}"
      jq -r '
        .issues[]
        | "KNOWN_ISSUE: test=" + (.test // "-")
          + " | file=" + (.file // "-")
          + " | error=" + (.error // "-")
          + " | first_seen_in=" + (.first_seen_in // "-")
          + " | last_seen_in=" + (.last_seen_in // "-")
          + " | times_seen=" + ((.times_seen // 1) | tostring)
          + " | first_seen_round=" + ((.first_seen_round // 0) | tostring)
          + " | last_seen_round=" + ((.last_seen_round // 0) | tostring)
      ' "$known_issues_path" 2>/dev/null || true
      echo ""
    fi
  else
    echo "=== KNOWN ISSUES ==="
    echo "known_issues_error=malformed"
    echo ""
  fi
}

print_known_issues_section

resolve_source_fail_verif() {
  _cvc_source_fail_verif_missing=false
  _cvc_remediation_state_active=false
  [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ] || {
    if [ -z "$_cvc_source_fail_verif" ] && [ -n "$_cvc_phase_verif" ]; then
      _cvc_source_fail_verif="$_cvc_phase_verif"
    fi
    return 0
  }
  _cvc_remediation_state_active=true
  _cvc_active_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  if [[ "${_cvc_active_round:-}" =~ ^[0-9]+$ ]] && [ "$((10#${_cvc_active_round}))" -gt 1 ] 2>/dev/null; then
    _cvc_prev_round=$(printf '%02d' "$((10#${_cvc_active_round} - 1))")
    _cvc_expected_source_verif="$PHASE_DIR/remediation/qa/round-${_cvc_prev_round}/R${_cvc_prev_round}-VERIFICATION.md"
    if [ ! -f "$_cvc_expected_source_verif" ]; then
      _cvc_source_fail_verif_missing=true
      _cvc_source_fail_verif=""
    fi
  fi
  if [[ "${_cvc_active_round:-}" =~ ^[0-9]+$ ]] && [ -z "$_cvc_source_fail_verif" ]; then
    _cvc_source_fail_verif_missing=true
  fi
}

_cvc_phase_verif=$(bash "${_CVC_SCRIPT_DIR}/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
if [ -n "$_cvc_phase_verif" ] && [ ! -f "$_cvc_phase_verif" ]; then
  _cvc_phase_verif=""
fi

_cvc_source_fail_verif=$(bash "${_CVC_SCRIPT_DIR}/resolve-verification-path.sh" plan-input "$PHASE_DIR" 2>/dev/null || true)
if [ -n "$_cvc_source_fail_verif" ] && [ ! -f "$_cvc_source_fail_verif" ]; then
  _cvc_source_fail_verif=""
fi
resolve_source_fail_verif

_cvc_qa_round_verifs=$(find "$PHASE_DIR" -path '*/remediation/qa/round-*/R*-VERIFICATION.md' 2>/dev/null | sort)

_cvc_has_verif_history=false
if [ -n "$_cvc_phase_verif" ] && [ -f "$_cvc_phase_verif" ]; then
  _cvc_has_verif_history=true
fi
if [ -n "$_cvc_qa_round_verifs" ]; then
  _cvc_has_verif_history=true
fi
if [ "$_cvc_source_fail_verif_missing" = true ]; then
  _cvc_has_verif_history=true
fi

print_phase_verification_fails() {
  local vhist_result
  [ -n "$_cvc_phase_verif" ] && [ -f "$_cvc_phase_verif" ] || return 0
  vhist_result=$(awk '
    BEGIN { in_fm=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); print; exit }
  ' "$_cvc_phase_verif" 2>/dev/null) || vhist_result=""
  echo "--- Phase VERIFICATION (${vhist_result:-unknown}) ---"
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      for (i = 2; i < NF; i++) {
        cell = trim($i)
        if (cell == "Status") {
          status_col = i
          next
        }
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") print
      }
    }
  ' "$_cvc_phase_verif" 2>/dev/null || true
}

print_original_fail_resolution_status() {
  if [ "$_cvc_source_fail_verif_missing" = true ]; then
    echo "--- ORIGINAL FAIL RESOLUTION STATUS ---"
    echo "source_verification_missing=true"
    return 0
  fi
  [ -n "$_cvc_source_fail_verif" ] && [ -f "$_cvc_source_fail_verif" ] || return 0
  echo "--- ORIGINAL FAIL RESOLUTION STATUS ---"
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0; id_col = 0; desc_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
          if (cell == "ID") id_col = i
          if (cell == "Truth/Condition") desc_col = i
          if (cell == "Artifact") desc_col = i
          if (cell == "Convention") desc_col = i
          if (cell == "Description") desc_col = i
          if (cell == "Link") desc_col = i
          if (cell == "Pattern") desc_col = i
          if (cell == "Requirement") desc_col = i
          if (cell == "From") desc_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") {
          fail_index++
          fail_id = (id_col > 0) ? trim($(id_col)) : ""
          if (fail_id == "") fail_id = sprintf("FAIL-ROW-%02d", fail_index)
          desc = (desc_col > 0) ? trim($(desc_col)) : "No description"
          printf "FAIL_ID: %s | ORIGINAL: %s | RESOLUTION_REQUIRED: code-fix, plan-amendment, or documented process-exception\n", fail_id, desc
        }
      }
    }
  ' "$_cvc_source_fail_verif" 2>/dev/null || true
}

print_qa_round_verification_fails() {
  local verif_file vhist_rr vhist_rresult
  [ -n "$_cvc_qa_round_verifs" ] || return 0
  while IFS= read -r verif_file; do
    [ -f "$verif_file" ] || continue
    vhist_rr=$(basename "$verif_file" | sed 's/^R\([0-9]*\).*/\1/')
    vhist_rresult=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); print; exit }
    ' "$verif_file" 2>/dev/null) || vhist_rresult=""
    echo "--- Round ${vhist_rr} VERIFICATION (${vhist_rresult:-unknown}) ---"
    awk -F'|' '
      function trim(v) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        return v
      }
      /^\|/ {
        if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") {
            status_col = i
            next
          }
        }
        if (status_col > 0) {
          status = trim($(status_col))
          gsub(/\*+/, "", status)
          status = trim(status)
          if (status == "FAIL") print
        }
      }
    ' "$verif_file" 2>/dev/null || true
  done <<< "$_cvc_qa_round_verifs"
}

if [ "$_cvc_has_verif_history" = true ]; then
  echo "=== VERIFICATION HISTORY ==="
  print_phase_verification_fails
  print_original_fail_resolution_status
  print_qa_round_verification_fails
  echo ""
fi

echo "verify_plan_count=${PLAN_COUNT}"
