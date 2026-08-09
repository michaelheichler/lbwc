#!/bin/bash
set -u

PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

[ ! -d "$PLANNING_DIR" ] && exit 0

_QG_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_QG_SUPPORT_LOADED=false
_QG_SUPPORT_READY=true

if [ -f "$_QG_SCRIPT_DIR/summary-utils.sh" ]; then
  if ! . "$_QG_SCRIPT_DIR/summary-utils.sh" >/dev/null 2>&1; then
    _QG_SUPPORT_READY=false
  fi
else
  _QG_SUPPORT_READY=false
fi

for _qg_dependency in \
  verification-freshness.sh \
  lib/phase-detect-support.sh \
  resolve-verification-path.sh \
  qa-result-gate.sh \
  lib/qa-gate-decision.sh \
  lib/qa-result-gate-path-evidence.sh \
  lib/qa-result-gate-fail-classifications.sh \
  lib/qa-result-gate-known-issues.sh \
  lib/qa-result-gate-summary-deviations.sh; do
  [ -r "$_QG_SCRIPT_DIR/$_qg_dependency" ] || _QG_SUPPORT_READY=false
done

if [ "$_QG_SUPPORT_READY" = true ]; then
  _SCRIPT_DIR_PD="$_QG_SCRIPT_DIR"
  if ! . "$_QG_SCRIPT_DIR/verification-freshness.sh" >/dev/null 2>&1 ||
     ! . "$_QG_SCRIPT_DIR/lib/phase-detect-support.sh" >/dev/null 2>&1 ||
     ! . "$_QG_SCRIPT_DIR/lib/qa-gate-decision.sh" >/dev/null 2>&1; then
    _QG_SUPPORT_READY=false
  else
    _QG_SUPPORT_LOADED=true
  fi
fi

if [ "$_QG_SUPPORT_READY" = false ]; then
  echo "qa-gate: dependency load failed, cannot verify SUMMARY.md gate" >&2
  exit 2
fi

[ -t 0 ] || { while IFS= read -r -t 2 _qg_line; do :; done; }

PLANS_TOTAL=0
SUMMARIES_TOTAL=0

for phase_dir in "$PLANNING_DIR/phases"/*/; do
  [ -d "$phase_dir" ] || continue
  PLANS=$(ls -1 "$phase_dir"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  COMPLETE_SUMMARIES=$(count_complete_summaries "$phase_dir")
  if phase_execution_is_satisfied "$phase_dir" "$PLANS" "$COMPLETE_SUMMARIES"; then
    SUMMARIES="$PLANS"
  else
    SUMMARIES="$COMPLETE_SUMMARIES"
  fi
  PLANS_TOTAL=$(( PLANS_TOTAL + PLANS ))
  SUMMARIES_TOTAL=$(( SUMMARIES_TOTAL + SUMMARIES ))
done

if qa_gate_summary_gap_is_allowed "$PLANS_TOTAL" "$SUMMARIES_TOTAL" unavailable; then
  exit 0
fi

NOW=$(date +%s 2>/dev/null) || exit 2
TWO_HOURS=7200
if command -v jq &>/dev/null && [ -f "$PLANNING_DIR/config.json" ]; then
  _window=$(jq -r '.qa_commit_window_seconds // 7200' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "${_window:-0}" -gt 0 ] 2>/dev/null && TWO_HOURS="$_window"
fi

GIT_EVIDENCE=unavailable
RECENT_COMMITS=$(git log --oneline -10 --format="%ct %s" 2>/dev/null) || RECENT_COMMITS=""

if [ -n "$RECENT_COMMITS" ]; then
  GIT_EVIDENCE=nonconforming
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
    COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)

    if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
      if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore)\([0-9]{2}-[0-9]{2}\):'; then
        AGE=$(( NOW - COMMIT_TS ))
        if [ "$AGE" -ge 0 ] && [ "$AGE" -le "$TWO_HOURS" ]; then
          GIT_EVIDENCE=fresh-conforming
          break
        fi
        GIT_EVIDENCE=stale
      fi
    fi
  done <<< "$RECENT_COMMITS"
fi

if qa_gate_summary_gap_is_allowed "$PLANS_TOTAL" "$SUMMARIES_TOTAL" "$GIT_EVIDENCE"; then
  exit 0
fi

echo "QA gate: SUMMARY.md gap detected ($SUMMARIES_TOTAL summaries for $PLANS_TOTAL plans)" >&2
exit 2
