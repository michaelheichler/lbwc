#!/bin/bash
set -u

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

rm -f "$PLANNING_DIR/.compaction-marker" "$PLANNING_DIR/.context-usage" 2>/dev/null || true

INPUT=$(cat)
NATIVE_AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
NAME_SOURCE=$(echo "$INPUT" | jq -r '.name // .agent_name // .agentName // .agent_type // ""' 2>/dev/null)

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

ROLE=$(normalize_agent_role "${NATIVE_AGENT_TYPE:-$NAME_SOURCE}") || ROLE=""

case "$ROLE" in
  lead)          FILES="STATE.md, ROADMAP.md, config.json, and current phase plans" ;;
  coding-dijkstra|python-engineer|web-engineer|test-dev)
                 FILES="your assigned PLAN.md, its CONTEXT.md, and relevant source files" ;;
  coding-dijkstra-critic|python-critic|web-code-critic|qa)
                 FILES="the artifact under review, and the plan's must_haves it is checked against" ;;
  qa-author)     FILES="the plan's must_haves and the tests already written" ;;
  scout)         FILES="research notes and REQUIREMENTS.md" ;;
  debugger)      FILES="the DEBUG-SESSION file, reproduction steps, and related source files" ;;
  architect)     FILES="REQUIREMENTS.md, ROADMAP.md, and phase structure" ;;
  docs)          FILES="the documentation files in progress and the source they document" ;;
  *)             FILES="STATE.md, your current task context, and any in-progress files" ;;
esac

if [ -f "$PLANNING_DIR/codebase/META.md" ]; then
  FILES="$FILES. If $PLANNING_DIR/codebase/META.md exists, re-read the codebase map docs it indexes"
fi

WORKTREE_CONTEXT=""
case "$ROLE" in
  coding-dijkstra|python-engineer|web-engineer|test-dev|debugger)
    WT=$(bash "$SCRIPT_DIR/worktree-agent-map.sh" get "$NAME_SOURCE" 2>/dev/null) || WT=""
    [ -n "$WT" ] && WORKTREE_CONTEXT=" Worktree working directory: ${WT}. All file operations must use this path."
    ;;
esac

ORCH_RESUME=""
if [ -z "$ROLE" ]; then
  ORCH_RESUME=" ORCHESTRATOR RESUME: re-read ${PLANNING_DIR}/STATE.md and run phase-detect.sh to see where the project stood before compaction, then resume the command you were executing from that point."
fi

jq -n --arg role "${ROLE:-orchestrator}" --arg files "$FILES" --arg worktree "$WORKTREE_CONTEXT" --arg orch "$ORCH_RESUME" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("Context was compacted. Role: " + $role + ". Re-read these key files from disk: " + $files + "." + $worktree + $orch)
  }
}'
exit 0
