#!/bin/bash
set -u

MODE="${1:-execute}"

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
USAGE_FILE="$PLANNING_DIR/.context-usage"

_SC_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_SC_SCRIPT_DIR/summary-utils.sh" ]; then
  . "$_SC_SCRIPT_DIR/summary-utils.sh"
else
  count_complete_summaries() { echo "0"; }
fi

. "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT=$(find "${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/cache/lbwc-marketplace/lbwc" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1 || true)
fi
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

AUTONOMY="standard"
EFFORT="balanced"
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  AUTONOMY=$(jq -r '.autonomy // "standard"' "$PLANNING_DIR/config.json" 2>/dev/null) || AUTONOMY="standard"
  EFFORT=$(jq -r '.effort // "balanced"' "$PLANNING_DIR/config.json" 2>/dev/null) || EFFORT="balanced"
fi

CHARS_PER_TOKEN=5
BASELINE_OVERHEAD=1500

sum_bytes() {
  local total=0
  for f in "$@"; do
    if [ -f "$f" ]; then
      local size
      size=$(wc -c < "$f" 2>/dev/null) || continue
      total=$((total + size))
    fi
  done
  echo "$total"
}

sum_glob() {
  local dir="$1" pattern="$2"
  local total=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local size
    size=$(wc -c < "$f" 2>/dev/null) || continue
    total=$((total + size))
  done < <(find "$dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
  echo "$total"
}

effort_file() {
  case "$EFFORT" in
    thorough) echo "$PLUGIN_ROOT/references/effort-profile-thorough.md" ;;
    fast)     echo "$PLUGIN_ROOT/references/effort-profile-fast.md" ;;
    turbo)    echo "$PLUGIN_ROOT/references/effort-profile-turbo.md" ;;
    *)        echo "$PLUGIN_ROOT/references/effort-profile-balanced.md" ;;
  esac
}

detect_phase_dir() {
  if [ ! -d "$PLANNING_DIR/phases" ]; then
    echo ""
    return
  fi
  local last_dir=""
  for d in "$PLANNING_DIR"/phases/*/; do
    [ ! -d "$d" ] && continue
    last_dir="$d"
    local plans summaries
    plans=$(find "$d" -maxdepth 1 -name '*-PLAN.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    summaries=$(count_complete_summaries "$d")
    if [ "$plans" -gt 0 ] && [ "$summaries" -lt "$plans" ]; then
      echo "$d"
      return
    fi
  done
  echo "${last_dir:-}"
}

PHASE_DIR=$(detect_phase_dir)
FIXED_BYTES=0
VARIABLE_BYTES=0

case "$MODE" in
  execute)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/execute-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
      "$PLUGIN_ROOT/references/lbwc-brand-essentials.md" \
      "$(effort_file)" \
      "$PLUGIN_ROOT/templates/agent-roles/dev.md.tpl" \
      "$PLUGIN_ROOT/templates/agent-roles/qa.md.tpl" \
      "$PLUGIN_ROOT/references/verification-protocol.md" \
      "$PLUGIN_ROOT/templates/SUMMARY.md" \
    )
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$(( \
        $(sum_glob "$PHASE_DIR" "*-PLAN.md") + \
        $(sum_glob "$PHASE_DIR" "*-SUMMARY.md") + \
        $(sum_bytes "$PHASE_DIR/.context-dev.md" "$PHASE_DIR/.context-qa.md") \
      ))
    fi
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/CONVENTIONS.md" \
      "$PLANNING_DIR/codebase/PATTERNS.md" \
      "$PLANNING_DIR/codebase/STRUCTURE.md" \
      "$PLANNING_DIR/codebase/DEPENDENCIES.md" \
    )))
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
      "$PLANNING_DIR/.execution-state.json" \
    )))
    ;;

  plan)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/templates/agent-roles/lead.md.tpl" \
      "$PLUGIN_ROOT/templates/PLAN.md" \
    )
    VARIABLE_BYTES=$(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
      "$PLANNING_DIR/REQUIREMENTS.md" \
    )
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-CONTEXT.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-RESEARCH.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes "$PHASE_DIR/.context-lead.md")))
    fi
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/ARCHITECTURE.md" \
      "$PLANNING_DIR/codebase/CONCERNS.md" \
      "$PLANNING_DIR/codebase/STRUCTURE.md" \
    )))
    ;;

  verify)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/templates/UAT.md" \
      "$PLUGIN_ROOT/references/lbwc-brand-essentials.md" \
    )
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/STATE.md")
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-PLAN.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-SUMMARY.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-UAT.md") - $(sum_glob "$PHASE_DIR" "*-SOURCE-UAT.md")))
    fi
    ;;

  qa)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/templates/agent-roles/qa.md.tpl" \
      "$PLUGIN_ROOT/references/verification-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
      "$PLUGIN_ROOT/references/lbwc-brand-essentials.md" \
      "$(effort_file)" \
    )
    VARIABLE_BYTES=$(sum_bytes \
      "$PLANNING_DIR/STATE.md" \
      "$PLANNING_DIR/ROADMAP.md" \
    )
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-PLAN.md")))
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-SUMMARY.md")))
    fi
    VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_bytes \
      "$PLANNING_DIR/codebase/TESTING.md" \
      "$PLANNING_DIR/codebase/CONCERNS.md" \
      "$PLANNING_DIR/codebase/ARCHITECTURE.md" \
    )))
    ;;

  discuss)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/discussion-engine.md" \
    )
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/ROADMAP.md")
    if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
      VARIABLE_BYTES=$((VARIABLE_BYTES + $(sum_glob "$PHASE_DIR" "*-CONTEXT.md")))
    fi
    ;;

  *)
    FIXED_BYTES=$(sum_bytes \
      "$PLUGIN_ROOT/references/execute-protocol.md" \
      "$PLUGIN_ROOT/references/handoff-schemas.md" \
    )
    VARIABLE_BYTES=$(sum_bytes "$PLANNING_DIR/STATE.md" "$PLANNING_DIR/ROADMAP.md")
    ;;
esac

TOTAL_BYTES=$((FIXED_BYTES + VARIABLE_BYTES))
EST_COST=$(( TOTAL_BYTES / CHARS_PER_TOKEN + BASELINE_OVERHEAD ))

authoritative_session_id() {
  local sid="${1:-}"

  [ -n "$sid" ] || return 1
  [ "$sid" = "unknown" ] && return 1
  [[ "$sid" =~ [^a-zA-Z0-9._-] ]] && return 1

  return 0
}

if [ ! -f "$USAGE_FILE" ]; then
  exit 0
fi

IFS='|' read -r FIELD1 FIELD2 FIELD3 < "$USAGE_FILE" 2>/dev/null || exit 0

if [ -n "${FIELD3:-}" ] && [[ "${FIELD2:-}" =~ ^[0-9]+$ ]] && [[ "${FIELD3:-}" =~ ^[0-9]+$ ]]; then
  FILE_SID="$FIELD1"
  USED_PCT="$FIELD2"
  CTX_SIZE="$FIELD3"
  CURRENT_SID="${CLAUDE_SESSION_ID:-}"
  authoritative_session_id "$FILE_SID" || exit 0
  authoritative_session_id "$CURRENT_SID" || exit 0
  if [ "$FILE_SID" != "$CURRENT_SID" ]; then
    exit 0
  fi
elif [[ "${FIELD1:-}" =~ ^[0-9]+$ ]] && [[ "${FIELD2:-}" =~ ^[0-9]+$ ]] && [ -z "${FIELD3:-}" ]; then
  exit 0
else
  exit 0
fi

[ "$CTX_SIZE" -eq 0 ] && exit 0

REMAINING=$(( CTX_SIZE * (100 - USED_PCT) / 100 ))

THRESHOLD=""
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  THRESHOLD=$(jq -r '.compaction_threshold // empty' "$PLANNING_DIR/config.json" 2>/dev/null)
fi

NEEDED=$(( EST_COST + EST_COST * 15 / 100 ))

USED_TOKENS=$(( CTX_SIZE * USED_PCT / 100 ))
THRESHOLD_EXCEEDED=false
if [[ "${THRESHOLD:-}" =~ ^[0-9]+$ ]] && [ "$THRESHOLD" -gt 0 ]; then
  PROJECTED=$(( USED_TOKENS + EST_COST ))
  if [ "$PROJECTED" -gt "$THRESHOLD" ]; then
    THRESHOLD_EXCEEDED=true
  fi
fi

if [ "$REMAINING" -lt "$NEEDED" ] || [ "$THRESHOLD_EXCEEDED" = true ]; then
  if [ "$AUTONOMY" = "confident" ] || [ "$AUTONOMY" = "pure-vibe" ]; then
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom (${FIXED_BYTES}B fixed + ${VARIABLE_BYTES}B project files). Running /compact now to prevent mid-workflow compaction.

**ACTION REQUIRED:** Run /compact before proceeding with this workflow. Auto-compacting now because autonomy is set to ${AUTONOMY}.
EOF
  else
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (~${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom (${FIXED_BYTES}B fixed + ${VARIABLE_BYTES}B project files). Starting now risks mid-workflow auto-compaction, which degrades context quality.

**RECOMMENDED:** Run \`/compact\` first, then re-run this command. Or run \`/lbwc:pause\` then \`/lbwc:resume\` for a clean context reload.
EOF
  fi
fi

exit 0
