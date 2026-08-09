#!/bin/bash
set -u

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INPUT=$(cat)
NATIVE_AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
NAME_SOURCE=$(echo "$INPUT" | jq -r '.name // .agent_name // .agentName // .agent_type // ""' 2>/dev/null)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // .matcher // "auto"' 2>/dev/null)

normalize_agent_role() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *coding-dijkstra-critic*) echo coding-dijkstra-critic ;;
    *coding-dijkstra*)        echo coding-dijkstra ;;
    *python-critic*)          echo python-critic ;;
    *python-engineer*)        echo python-engineer ;;
    *web-code-critic*)        echo web-code-critic ;;
    *web-engineer*)           echo web-engineer ;;
    *test-dev*)                echo test-dev ;;
    *qa-author*)               echo qa-author ;;
    *ux-oracle*)               echo ux-oracle ;;
    *architect*)               echo architect ;;
    *debugger*)                echo debugger ;;
    *scout*)                   echo scout ;;
    *lead*)                    echo lead ;;
    *docs*)                    echo docs ;;
    *qa*)                      echo qa ;;
    *) return 1 ;;
  esac
}

AGENT_ROLE=$(normalize_agent_role "${NATIVE_AGENT_TYPE:-$NAME_SOURCE}") || AGENT_ROLE=""

case "$AGENT_ROLE" in
  scout)
    PRIORITIES="Preserve research findings, sources, and confidence assessments."
    ;;
  coding-dijkstra|python-engineer|web-engineer|test-dev|docs)
    PRIORITIES="Preserve commit hashes, file paths modified, deviation decisions, and the current task."
    WT=$(bash "$SCRIPT_DIR/worktree-agent-map.sh" get "$NAME_SOURCE" 2>/dev/null) || WT=""
    [ -n "$WT" ] && PRIORITIES="$PRIORITIES CRITICAL: your working directory is ${WT}. All file operations must use this path."
    ;;
  coding-dijkstra-critic|python-critic|web-code-critic|qa)
    PRIORITIES="Preserve the pass/fail/partial verdict, findings, and any blocking issues found so far."
    ;;
  qa-author)
    PRIORITIES="Preserve which failing tests have been written and which must_haves remain uncovered."
    ;;
  lead)
    PRIORITIES="Preserve phase status, plan structure, and coordination decisions."
    ;;
  architect)
    PRIORITIES="Preserve requirement IDs, phase structure, and success criteria."
    ;;
  debugger)
    PRIORITIES="Preserve reproduction steps, hypotheses, evidence gathered, and the diagnosis so far."
    ;;
  ux-oracle)
    PRIORITIES="Preserve the open design question and any recommendation given so far."
    ;;
  *)
    PRIORITIES="Preserve the active command, the user's original request, current phase/plan context, file modification paths, and any pending user decisions. Discard tool output details and reference file contents, re-read those from disk."
    ;;
esac

if [ "$TRIGGER" = "manual" ]; then
  PRIORITIES="$PRIORITIES User requested this compaction."
else
  PRIORITIES="$PRIORITIES This is an automatic compaction at the context limit."
fi

CAVEMAN_CFG="$PLANNING_DIR/config.json"
if [ -f "$CAVEMAN_CFG" ] && command -v jq >/dev/null 2>&1; then
  CAVEMAN_STYLE=$(jq -r '.caveman_style // "none"' "$CAVEMAN_CFG" 2>/dev/null || echo "none")
  if [ "$CAVEMAN_STYLE" != "none" ] && [ "$CAVEMAN_STYLE" != "false" ]; then
    CAVEMAN_LEVEL="$CAVEMAN_STYLE"
    if [ "$CAVEMAN_LEVEL" = "auto" ] && [ -f "$SCRIPT_DIR/lib/resolve-caveman-level.sh" ]; then
      . "$SCRIPT_DIR/lib/resolve-caveman-level.sh"
      resolve_caveman_level "auto" "$PLANNING_DIR"
      CAVEMAN_LEVEL="$RESOLVED_CAVEMAN_LEVEL"
    fi
    [ "$CAVEMAN_LEVEL" != "none" ] && PRIORITIES="$PRIORITIES CAVEMAN MODE (${CAVEMAN_LEVEL}): respond in ${CAVEMAN_LEVEL} caveman style after compaction."
  fi
fi

[ -d "$PLANNING_DIR" ] && date +%s > "$PLANNING_DIR/.compaction-marker" 2>/dev/null

COMPACTION_LIMIT=10
# ponytail: count survives across sessions, add a startup reset if a stale count misfires.
if [ -d "$PLANNING_DIR" ]; then
  COUNT_FILE="$PLANNING_DIR/.compaction-count"
  PREV_COUNT=0
  [ -f "$COUNT_FILE" ] && PREV_COUNT=$(tr -dc '0-9' < "$COUNT_FILE" 2>/dev/null)
  [ -z "$PREV_COUNT" ] && PREV_COUNT=0
  NEW_COUNT=$((PREV_COUNT + 1))
  echo "$NEW_COUNT" > "$COUNT_FILE" 2>/dev/null || true
  if [ "$NEW_COUNT" -ge "$COMPACTION_LIMIT" ]; then
    PRIORITIES="CRITICAL, COMPACTION LOOP DETECTED (${NEW_COUNT} compactions). Stop all work immediately, do not read more files or call more tools. Tell the user the session context is too large for the effective context window and needs a smaller task scope."
  elif [ "$NEW_COUNT" -ge 3 ]; then
    PRIORITIES="WARNING: this session has compacted ${NEW_COUNT} times (limit ${COMPACTION_LIMIT}). Minimize file reads. $PRIORITIES"
  fi
fi

jq -n --arg ctx "$PRIORITIES" '{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ("Compaction priorities: " + $ctx + " Re-read assigned files from disk after compaction.")
  }
}'
exit 0
