#!/bin/bash
set -u

CONFIG_FILE="$PLANNING_DIR/config.json"

CFG_EFFORT="balanced"
CFG_AUTONOMY="standard"
CFG_AUTO_COMMIT="true"
CFG_PLANNING_TRACKING="manual"
CFG_AUTO_PUSH="never"
CFG_VERIFICATION_TIER="standard"
CFG_PREFER_TEAMS="auto"
CFG_MAX_TASKS="5"
CFG_COMPACTION="130000"
CFG_CONTEXT_COMPILER="true"
CFG_AUTO_UAT="false"

if [ "$JQ_AVAILABLE" = true ]; then
  MERGED_CONFIG_ENV=$(lbwc_merged_config "$CONFIG_FILE")
  while IFS=$'\t' read -r cfg_key cfg_value; do
    case "$cfg_key" in
      effort) CFG_EFFORT=$cfg_value ;;
      autonomy) CFG_AUTONOMY=$cfg_value ;;
      auto_commit) CFG_AUTO_COMMIT=$cfg_value ;;
      planning_tracking) CFG_PLANNING_TRACKING=$cfg_value ;;
      auto_push) CFG_AUTO_PUSH=$cfg_value ;;
      verification_tier) CFG_VERIFICATION_TIER=$cfg_value ;;
      max_tasks) CFG_MAX_TASKS=$cfg_value ;;
      context_compiler) CFG_CONTEXT_COMPILER=$cfg_value ;;
      compaction) CFG_COMPACTION=$cfg_value ;;
      auto_uat) CFG_AUTO_UAT=$cfg_value ;;
    esac
  done < <(jq -r '[
    ["effort", (.effort // "balanced")],
    ["autonomy", (.autonomy // "standard")],
    ["auto_commit", (if .auto_commit == null then true else .auto_commit end)],
    ["planning_tracking", (.planning_tracking // "manual")],
    ["auto_push", (.auto_push // "never")],
    ["verification_tier", (.verification_tier // "standard")],
    ["max_tasks", (.max_tasks_per_plan // 5)],
    ["context_compiler", (if .context_compiler == null then true else .context_compiler end)],
    ["compaction", (.compaction_threshold // 130000)],
    ["auto_uat", (if .auto_uat == null then false else .auto_uat end)]
  ][] | @tsv' <<< "$MERGED_CONFIG_ENV" 2>/dev/null || true)
  CFG_PREFER_TEAMS=$(bash "$_SCRIPT_DIR_PD/normalize-prefer-teams.sh" "$CONFIG_FILE" 2>/dev/null || echo "auto")
fi

echo "config_effort=$CFG_EFFORT"
echo "config_autonomy=$CFG_AUTONOMY"
echo "config_auto_commit=$CFG_AUTO_COMMIT"
echo "config_planning_tracking=$CFG_PLANNING_TRACKING"
echo "config_auto_push=$CFG_AUTO_PUSH"
echo "config_verification_tier=$CFG_VERIFICATION_TIER"
echo "config_prefer_teams=$CFG_PREFER_TEAMS"
echo "config_max_tasks_per_plan=$CFG_MAX_TASKS"
echo "config_context_compiler=$CFG_CONTEXT_COMPILER"
echo "config_require_phase_discussion=$CFG_REQUIRE_PHASE_DISCUSSION"
echo "config_auto_uat=$CFG_AUTO_UAT"
echo "config_compaction_threshold=$CFG_COMPACTION"

if [ -f "$PLANNING_DIR/codebase/META.md" ]; then
  echo "has_codebase_map=true"
else
  echo "has_codebase_map=false"
fi

BROWNFIELD=false
if git ls-files . 2>/dev/null | head -1 | grep -q .; then
  BROWNFIELD=true
fi
echo "brownfield=$BROWNFIELD"

EXEC_STATE_FILE="$PLANNING_DIR/.execution-state.json"
EXEC_STATE="none"
if [ -f "$EXEC_STATE_FILE" ] && [ "$JQ_AVAILABLE" = true ]; then
  if parsed_exec_state=$(jq -r '.status // "none"' "$EXEC_STATE_FILE" 2>/dev/null) && [ -n "$parsed_exec_state" ]; then
    EXEC_STATE=$parsed_exec_state
  fi
fi
if [ -f "$EXEC_STATE_FILE" ] && [ "$JQ_AVAILABLE" != true ]; then
  EXEC_STATE="none"
fi
echo "execution_state=$EXEC_STATE"

true
