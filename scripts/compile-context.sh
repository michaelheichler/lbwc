#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: compile-context.sh <phase-number> <role> [phases-dir]" >&2
  exit 1
fi

PHASE="$1"
ROLE="$2"
PHASES_DIR_INPUT="${3:-}"
PLAN_PATH="${4:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "${SCRIPT_DIR}/lib/lbwc-target-root.sh"
. "${SCRIPT_DIR}/lib/lbwc-settings.sh"

TARGET_SCOPE_EXPLICIT=0
if [ -n "${LBWC_PLANNING_DIR:-}" ] || [ $# -ge 3 ] || [ $# -ge 4 ]; then
  TARGET_SCOPE_EXPLICIT=1
fi

resolve_preferred_planning_dir() {
  local explicit_planning_dir

  explicit_planning_dir=$(lbwc_resolve_target_planning_dir "1" "$PLAN_PATH" "$PHASES_DIR_INPUT" 2>/dev/null || true)
  if [ -n "$explicit_planning_dir" ]; then
    printf '%s\n' "$explicit_planning_dir"
    return 0
  fi

  if [ -n "${LBWC_PLANNING_DIR:-}" ]; then
    printf '%s\n' "$LBWC_PLANNING_DIR"
    return 0
  fi

  lbwc_resolve_target_planning_dir "$TARGET_SCOPE_EXPLICIT" "$PLAN_PATH" "$PHASES_DIR_INPUT" 2>/dev/null || printf '%s\n' '.lbwc-planning'
}

PLANNING_DIR=$(resolve_preferred_planning_dir)
PLANNING_DIR=$(lbwc_candidate_dir_for_path "$PLANNING_DIR" 2>/dev/null || printf '%s\n' "$PLANNING_DIR")
TARGET_ROOT=$(lbwc_resolve_target_root "$TARGET_SCOPE_EXPLICIT" "$PLAN_PATH" "$PHASES_DIR_INPUT" "$PLANNING_DIR" || true)

if [ -n "$TARGET_ROOT" ] && [ -d "$TARGET_ROOT/.lbwc-planning" ] && [ ! -d "$PLANNING_DIR" ]; then
  PLANNING_DIR="$TARGET_ROOT/.lbwc-planning"
fi

PHASES_DIR="${PHASES_DIR_INPUT:-${PLANNING_DIR}/phases}"

case "$PHASES_DIR" in
  */.lbwc-planning/milestones/*|.lbwc-planning/milestones/*)
    echo "Error: refusing to compile context for archived milestone path: $PHASES_DIR" >&2
    echo "Execution must target active phases in .lbwc-planning/phases/" >&2
    exit 1
    ;;
esac

update_context_index() {
  local cache_key="$1" context_path="$2" role="$3" phase="$4"
  local index_path="${PLANNING_DIR}/.cache/context-index.json"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

  mkdir -p "$(dirname "$index_path")" 2>/dev/null || return 0

  if [ ! -f "$index_path" ]; then
    echo '{"entries":{}}' > "$index_path" 2>/dev/null || return 0
  fi

  local tmp
  tmp=$(mktemp 2>/dev/null) || return 0
  if jq --arg key "$cache_key" \
       --arg path "$context_path" \
       --arg role "$role" \
       --arg phase "$phase" \
       --arg ts "$timestamp" \
       '.entries[$key] = {path: $path, role: $role, phase: $phase, timestamp: $ts}' \
       "$index_path" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$index_path" 2>/dev/null || rm -f "$tmp"
  else
    rm -f "$tmp"
  fi
}

PHASE_NUM=$(echo "$PHASE" | sed 's/^0*//')
if [ -z "$PHASE_NUM" ]; then PHASE_NUM="0"; fi

PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)

resolve_research_file_per_plan() {
  local phase_dir="$1" plan_path="$2" plan_basename plan_prefix per_plan_research

  [ -n "$plan_path" ] && [ -f "$plan_path" ] || return 0
  plan_basename=$(basename "$plan_path" .md)
  plan_prefix=$(echo "$plan_basename" | sed 's/-PLAN$//')
  per_plan_research="${phase_dir}/${plan_prefix}-RESEARCH.md"
  [ -f "$per_plan_research" ] && echo "$per_plan_research"
}

resolve_research_file_phase_wide() {
  local phase_dir="$1" phase_base phase_num phase_wide_research

  phase_base=$(basename "$phase_dir")
  phase_num=$(echo "$phase_base" | sed 's/^\([0-9]*\).*/\1/')
  [ -n "$phase_num" ] || return 0
  phase_num=$(printf "%02d" "$((10#$phase_num))")
  phase_wide_research="${phase_dir}/${phase_num}-RESEARCH.md"
  [ -f "$phase_wide_research" ] && echo "$phase_wide_research"
}

resolve_research_file() {
  local phase_dir="$1" plan_path="$2" found

  found=$(resolve_research_file_per_plan "$phase_dir" "$plan_path")
  [ -n "$found" ] && { echo "$found"; return; }

  found=$(resolve_research_file_phase_wide "$phase_dir")
  [ -n "$found" ] && { echo "$found"; return; }

  find "$phase_dir" -maxdepth 1 -name "*-RESEARCH.md" -print -quit 2>/dev/null || true
}

if [ -z "$PHASE_DIR" ]; then
  PADDED=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
  PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PADDED}-*" 2>/dev/null | head -1)
fi
if [ -z "$PHASE_DIR" ]; then
  echo "Phase ${PHASE} directory not found" >&2
  exit 1
fi

ROADMAP="$PLANNING_DIR/ROADMAP.md"

PHASE_SECTION=""
PHASE_GOAL="Not available"
PHASE_REQS="Not available"
PHASE_SUCCESS="Not available"

if [ -f "$ROADMAP" ]; then
  PHASE_SECTION=$(sed -n "/^## Phase ${PHASE_NUM}:/,/^## Phase [0-9]/p" "$ROADMAP" 2>/dev/null | sed '$d') || true
  if [ -n "$PHASE_SECTION" ]; then
    PHASE_GOAL=$(echo "$PHASE_SECTION" | grep '^\*\*Goal:\*\*' 2>/dev/null | sed 's/\*\*Goal:\*\* *//' ) || PHASE_GOAL="Not available"
    PHASE_REQS=$(echo "$PHASE_SECTION" | grep '^\*\*Reqs:\*\*' 2>/dev/null | sed 's/\*\*Reqs:\*\* *//' ) || PHASE_REQS="Not available"
    PHASE_SUCCESS=$(echo "$PHASE_SECTION" | grep '^\*\*Success:\*\*' 2>/dev/null | sed 's/\*\*Success:\*\* *//' ) || PHASE_SUCCESS="Not available"
  fi
fi

REQ_PATTERN=""
if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
  REQ_PATTERN=$(echo "$PHASE_REQS" | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//' | paste -sd '|' -) || true
fi

V3_CACHE_ENABLED=true
CACHE_HASH=""
CONFIG_PATH="${PLANNING_DIR}/config.json"
MERGED_CONFIG=$(lbwc_merged_config "$CONFIG_PATH")

V3_DELTA_ENABLED=true
V3_METRICS_ENABLED=true
START_TIME=""

if command -v jq &>/dev/null; then
  V3_METRICS_ENABLED=$(jq -r 'if .metrics != null then .metrics elif .v3_metrics != null then .v3_metrics else true end' <<< "$MERGED_CONFIG" 2>/dev/null || echo "true")
fi

ROLLING_SUMMARY=false
if command -v jq &>/dev/null; then
  ROLLING_SUMMARY=$(jq -r 'if .rolling_summary != null then .rolling_summary elif .v3_rolling_summary != null then .v3_rolling_summary else false end' <<< "$MERGED_CONFIG" 2>/dev/null || echo "false")
fi

ROLLING_CONTEXT_PATH="${PLANNING_DIR}/ROLLING-CONTEXT.md"
ROLLING_CONTEXT_SECTION=""
if [ "$ROLLING_SUMMARY" = "true" ] && [ "$PHASE_NUM" -gt 1 ] 2>/dev/null && [ -f "$ROLLING_CONTEXT_PATH" ]; then
  ROLLING_CONTEXT_SECTION=$(cat "$ROLLING_CONTEXT_PATH" 2>/dev/null || true)
fi

MILESTONE_CONTEXT_PATH="${PLANNING_DIR}/CONTEXT.md"
MILESTONE_CONTEXT_SECTION=""
if [ -f "$MILESTONE_CONTEXT_PATH" ]; then
  MILESTONE_CONTEXT_SECTION=$(sed '1{/^# /d;}' "$MILESTONE_CONTEXT_PATH" 2>/dev/null || true)
fi

CAVEMAN_STYLE="none"
CAVEMAN_COMMIT="false"
CAVEMAN_REVIEW="false"
if command -v jq &>/dev/null; then
  CAVEMAN_STYLE=$(jq -r '.caveman_style // "none"' <<< "$MERGED_CONFIG" 2>/dev/null || echo "none")
  CAVEMAN_COMMIT=$(jq -r 'if .caveman_commit == null then false else .caveman_commit end' <<< "$MERGED_CONFIG" 2>/dev/null || echo "false")
  CAVEMAN_REVIEW=$(jq -r 'if .caveman_review == null then false else .caveman_review end' <<< "$MERGED_CONFIG" 2>/dev/null || echo "false")
fi

if [ "$V3_METRICS_ENABLED" = "true" ]; then
  START_TIME=$(date +%s 2>/dev/null || echo "0")
fi

try_serve_from_cache() {
  local cache_result cache_status cache_hash cached_path output_path

  cache_result=$(bash "${SCRIPT_DIR}/cache-context.sh" "$PHASE" "$ROLE" "$CONFIG_PATH" "$PLAN_PATH" 2>/dev/null || echo "miss nohash")
  cache_status=$(echo "$cache_result" | cut -d' ' -f1)
  cache_hash=$(echo "$cache_result" | cut -d' ' -f2)
  CACHE_HASH="$cache_hash"

  [ "$cache_status" = "hit" ] || return 1

  cached_path=$(echo "$cache_result" | cut -d' ' -f3)
  output_path="${PHASE_DIR}/.context-${ROLE}.md"
  cp "$cached_path" "$output_path" 2>/dev/null || { echo "V3 fallback: cache copy failed for ${ROLE}, compiling fresh" >&2; return 1; }

  update_context_index "$cache_hash" "$cached_path" "$ROLE" "$PHASE"
  if [ "$V3_METRICS_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
    bash "${SCRIPT_DIR}/collect-metrics.sh" cache_hit "$PHASE" "role=${ROLE}" 2>/dev/null || true
  fi
  echo "$output_path"
  return 0
}

if [ "$V3_CACHE_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/cache-context.sh" ]; then
  try_serve_from_cache && exit 0
elif [ "$V3_CACHE_ENABLED" = "true" ]; then
  echo "V3 fallback: cache-context.sh not found, skipping cache" >&2
fi

emit_codebase_map_file_list() {
  local doc map_files=""
  for doc in ARCHITECTURE CONCERNS PATTERNS DEPENDENCIES STRUCTURE CONVENTIONS TESTING STACK; do
    if [ -f "$PLANNING_DIR/codebase/${doc}.md" ]; then
      map_files="${map_files} ${doc}"
    fi
  done
  printf '%s' "$map_files"
}

emit_codebase_priority_guidance() {
  local priority_files=("$@") pfile guidance_files="" comma_count

  for pfile in "${priority_files[@]}"; do
    if [ -f "$PLANNING_DIR/codebase/${pfile}.md" ]; then
      if [ -z "$guidance_files" ]; then
        guidance_files="${pfile}.md"
      else
        guidance_files="${guidance_files}, ${pfile}.md"
      fi
    fi
  done

  comma_count=$(echo "$guidance_files" | tr -cd ',' | wc -c | tr -d ' ')
  if [ "$comma_count" -eq 1 ]; then
    guidance_files=$(echo "$guidance_files" | sed 's/, / and /')
  elif [ "$comma_count" -gt 1 ]; then
    guidance_files=$(echo "$guidance_files" | sed 's/\(.*\), /\1, and /')
  fi
  if [ -n "$guidance_files" ]; then
    echo "Read ${guidance_files} first to bootstrap codebase understanding."
  fi
}

emit_codebase_mapping_hint() {
  local map_files doc

  [ -f "$PLANNING_DIR/codebase/META.md" ] || return 0
  map_files=$(emit_codebase_map_file_list)
  [ -n "$map_files" ] || return 0

  echo ""
  echo "### Codebase Map Available"
  echo "Codebase mapping exists in \`.lbwc-planning/codebase/\`. Key files:"
  for doc in $map_files; do
    echo "- \`${doc}.md\`"
  done
  echo ""

  emit_codebase_priority_guidance "$@"
  return 0
}

emit_caveman_directive() {
  local level="$CAVEMAN_STYLE" extra="${1:-}"

  if [ "$CAVEMAN_STYLE" = "none" ] || [ "$CAVEMAN_STYLE" = "false" ]; then
    return 0
  fi
  if [ "$level" = "auto" ]; then
    . "${SCRIPT_DIR}/lib/resolve-caveman-level.sh"
    resolve_caveman_level "auto" "$PLANNING_DIR"
    level="$RESOLVED_CAVEMAN_LEVEL"
  fi
  [ "$level" = "none" ] && return 0

  echo ""
  echo "### Caveman Language (${level})"
  echo "Respond in ${level} caveman language. Follow rules in \`references/caveman-language.md\`."
  if [ "$extra" = "commit" ] && [ "$CAVEMAN_COMMIT" = "true" ]; then
    echo "Write commit messages per \`references/caveman-commit.md\`."
  fi
  if [ "$extra" = "review" ] && [ "$CAVEMAN_REVIEW" = "true" ]; then
    echo "Format code review output per \`references/caveman-review.md\`."
  fi
  return 0
}

emit_delta_changed_files_section() {
  local delta_files="$1" f

  echo ""
  echo "### Changed Files (Delta)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "- \`$f\`"
  done <<< "$delta_files"
  return 0
}

emit_delta_code_slice() {
  local f="$1" source_path="$2" slice_lines
  slice_lines=$(wc -l < "$source_path" 2>/dev/null | tr -d ' ' || echo "0")
  if [ "$slice_lines" -le 50 ]; then
    echo ""
    echo "#### \`$f\` (${slice_lines} lines)"
    echo '```'
    cat "$source_path" 2>/dev/null || true
    echo '```'
  else
    echo ""
    echo "#### \`$f\` (${slice_lines} lines, first 30 shown)"
    echo '```'
    head -30 "$source_path" 2>/dev/null || true
    echo '```'
  fi
}

emit_delta_code_slices_section() {
  local delta_files="$1" source_root="$2" f source_path

  echo ""
  echo "### Code Slices"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    lbwc_is_safe_relative_path "$f" || continue
    source_path=$(lbwc_resolve_repo_path "$source_root" "$f") || continue
    [ -f "$source_path" ] && emit_delta_code_slice "$f" "$source_path"
  done <<< "$delta_files"
  return 0
}

emit_active_decisions_section() {
  local decisions
  echo ""
  echo "### Active Decisions"
  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    decisions=$(awk '
      { low = tolower($0) }
      low ~ /^##[[:space:]]+(key[[:space:]]+)?decisions[[:space:]]*$/ { found=1; next }
      found && /^##[[:space:]]/ { found=0 }
      found && low ~ /^###[[:space:]]+pending[[:space:]]+todos[[:space:]]*$/ { found=0; skip_skills=0; next }
      found && low ~ /^###[[:space:]]+skills[[:space:]]*$/ { skip_skills=1; next }
      skip_skills && /^###?#? / { skip_skills=0 }
      found && !skip_skills { print }
    ' "$PLANNING_DIR/STATE.md" 2>/dev/null) || true
    echo "${decisions:-None}"
  else
    echo "None"
  fi
  return 0
}

emit_requirements_section() {
  local heading="$1"
  echo ""
  echo "### ${heading}"
  if [ -n "$REQ_PATTERN" ] && [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
    grep -E "($REQ_PATTERN)" "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null || echo "No matching requirements found"
  else
    echo "No matching requirements found"
  fi
  return 0
}

emit_conventions_section() {
  local heading="$1" conventions
  [ -f "$PLANNING_DIR/conventions.json" ] && command -v jq &>/dev/null || return 0
  conventions=$(jq -r '.conventions[] | "- [\(.tag)] \(.rule)"' "$PLANNING_DIR/conventions.json" 2>/dev/null) || true
  [ -n "$conventions" ] || return 0
  echo ""
  echo "### ${heading}"
  echo "$conventions"
}

emit_research_findings_section() {
  local research_file
  research_file=$(resolve_research_file "$PHASE_DIR" "$PLAN_PATH")
  [ -n "$research_file" ] && [ -f "$research_file" ] || return 1
  echo ""
  echo "### Research Findings"
  cat "$research_file"
}

emit_prior_context_sections() {
  if [ -n "$ROLLING_CONTEXT_SECTION" ]; then
    echo ""
    echo "### Prior Phase Context (Rolling Summary)"
    echo "$ROLLING_CONTEXT_SECTION"
    echo ""
  fi
  if [ -n "$MILESTONE_CONTEXT_SECTION" ]; then
    echo ""
    echo "### Milestone Scope Context"
    echo "$MILESTONE_CONTEXT_SECTION"
    echo ""
  fi
  return 0
}

emit_goal_and_success() {
  echo ""
  echo "### Goal"
  echo "$PHASE_GOAL"
  echo ""
  echo "### Success Criteria"
  echo "$PHASE_SUCCESS"
  return 0
}

emit_deviq_digest_section() {
  local digest
  [ -f "${SCRIPT_DIR}/lib/deviq-digest.sh" ] || return 0
  digest=$(bash "${SCRIPT_DIR}/lib/deviq-digest.sh" --phase "$PHASE" --root "${PLANNING_DIR}/deviq" 2>/dev/null) || return 0
  [ -n "$digest" ] || return 0
  echo ""
  echo "$digest"
  return 0
}

emit_delta_context_for_role() {
  local include_code_slices="$1" delta_files
  [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ] || return 0
  delta_files=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null || true)
  [ -n "$delta_files" ] || return 0
  emit_delta_changed_files_section "$delta_files"
  if [ "$include_code_slices" = "true" ]; then
    emit_delta_code_slices_section "$delta_files" "$TARGET_ROOT"
  fi
  return 0
}

compile_context_lead() {
  local total_reqs matched_reqs others
  {
    echo "## Phase ${PHASE} Context (Compiled)"
    emit_prior_context_sections
    emit_goal_and_success
    emit_requirements_section "Requirements (${PHASE_REQS})"
    echo ""
    total_reqs=$(grep -c '^\- \[' "$PLANNING_DIR/REQUIREMENTS.md" 2>/dev/null) || total_reqs=0
    matched_reqs=0
    if [ "$PHASE_REQS" != "Not available" ] && [ -n "$PHASE_REQS" ]; then
      matched_reqs=$(echo "$PHASE_REQS" | tr ',' '\n' | wc -l | tr -d ' ')
    fi
    others=$((total_reqs - matched_reqs))
    if [ "$others" -gt 0 ]; then
      echo "(${others} other requirements exist for other phases -- not shown)"
    fi
    emit_active_decisions_section
    emit_deviq_digest_section
    if ! emit_research_findings_section; then
      emit_codebase_mapping_hint ARCHITECTURE CONCERNS STRUCTURE
    fi
    emit_caveman_directive commit
  } > "${PHASE_DIR}/.context-lead.md"
}

compile_context_dev() {
  {
    echo "## Phase ${PHASE} Context"
    emit_prior_context_sections
    echo ""
    echo "### Goal"
    echo "$PHASE_GOAL"
    emit_conventions_section "Conventions"
    emit_codebase_mapping_hint CONVENTIONS PATTERNS STRUCTURE DEPENDENCIES
    emit_delta_context_for_role true
    if [ "$V3_DELTA_ENABLED" = "true" ] && [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
      echo ""
      echo "### Active Plan"
      cat "$PLAN_PATH"
    fi
    emit_research_findings_section || true
    emit_caveman_directive commit
  } > "${PHASE_DIR}/.context-dev.md"
}

compile_context_qa() {
  {
    echo "## Phase ${PHASE} Verification Context"
    emit_prior_context_sections
    emit_goal_and_success
    emit_requirements_section "Requirements to Verify"
    emit_conventions_section "Conventions to Check"
    emit_codebase_mapping_hint TESTING CONCERNS ARCHITECTURE
    emit_caveman_directive review
  } > "${PHASE_DIR}/.context-qa.md"
}

compile_context_scout() {
  {
    echo "## Phase ${PHASE} Research Context"
    emit_prior_context_sections
    emit_goal_and_success
    emit_requirements_section "Requirements (${PHASE_REQS})"
    emit_conventions_section "Conventions"
    emit_research_findings_section || true
    emit_delta_context_for_role false
    emit_caveman_directive
  } > "${PHASE_DIR}/.context-scout.md"
}

compile_context_debugger() {
  local activity
  {
    echo "## Phase ${PHASE} Debug Context"
    emit_prior_context_sections
    emit_goal_and_success
    echo ""
    echo "### Recent Activity"
    if [ -f "$PLANNING_DIR/STATE.md" ]; then
      activity=$(awk '
        /^## (Recent Activity|Activity Log|Activity)$/ { found=1; next }
        found && /^## / { exit }
        found { print }
      ' "$PLANNING_DIR/STATE.md" 2>/dev/null) || true
      echo "${activity:-None}"
    else
      echo "None"
    fi
    emit_conventions_section "Conventions"
    emit_codebase_mapping_hint ARCHITECTURE CONCERNS PATTERNS DEPENDENCIES
    emit_deviq_digest_section
    emit_research_findings_section || true
    emit_delta_context_for_role true
    emit_caveman_directive
  } > "${PHASE_DIR}/.context-debugger.md"
}

compile_context_architect() {
  {
    echo "## Phase ${PHASE} Architecture Context"
    emit_prior_context_sections
    emit_goal_and_success
    echo ""
    echo "### Full Requirements"
    if [ -f "$PLANNING_DIR/REQUIREMENTS.md" ]; then
      cat "$PLANNING_DIR/REQUIREMENTS.md"
    else
      echo "No requirements file found"
    fi
    emit_conventions_section "Conventions"
    emit_codebase_mapping_hint ARCHITECTURE STACK
    emit_deviq_digest_section
    emit_research_findings_section || true
    emit_caveman_directive
  } > "${PHASE_DIR}/.context-architect.md"
}

case "$ROLE" in
  lead) compile_context_lead ;;
  dev) compile_context_dev ;;
  qa) compile_context_qa ;;
  scout) compile_context_scout ;;
  debugger) compile_context_debugger ;;
  architect) compile_context_architect ;;
  *)
    echo "Unknown role: $ROLE. Valid roles: lead, dev, qa, scout, debugger, architect" >&2
    exit 1
    ;;
esac

if [ "$V3_CACHE_ENABLED" = "true" ] && [ -n "$CACHE_HASH" ] && [ "$CACHE_HASH" != "nohash" ]; then
  CACHE_DIR="${PLANNING_DIR}/.cache/context"
  if mkdir -p "$CACHE_DIR" 2>/dev/null; then
    cp "${PHASE_DIR}/.context-${ROLE}.md" "${CACHE_DIR}/${CACHE_HASH}.md" 2>/dev/null || echo "V3 fallback: cache write failed for ${ROLE}" >&2
    update_context_index "$CACHE_HASH" "${CACHE_DIR}/${CACHE_HASH}.md" "$ROLE" "$PHASE"
  else
    echo "V3 fallback: could not create cache dir" >&2
  fi
fi

if [ "$V3_METRICS_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/collect-metrics.sh" ]; then
  END_TIME=$(date +%s 2>/dev/null || echo "0")
  DURATION_MS=$(( (END_TIME - ${START_TIME:-0}) * 1000 ))
  DELTA_COUNT=0
  if [ "$V3_DELTA_ENABLED" = "true" ] && [ -f "${SCRIPT_DIR}/delta-files.sh" ]; then
    DELTA_COUNT=$(bash "${SCRIPT_DIR}/delta-files.sh" "$PHASE_DIR" "$PLAN_PATH" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  fi
  bash "${SCRIPT_DIR}/collect-metrics.sh" compile_context "$PHASE" "role=${ROLE}" "duration_ms=${DURATION_MS}" "delta_files=${DELTA_COUNT}" "cache=miss" 2>/dev/null || true
fi

echo "${PHASE_DIR}/.context-${ROLE}.md"
