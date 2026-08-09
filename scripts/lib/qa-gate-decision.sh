#!/bin/bash

qa_gate_summary_gap_is_allowed() {
  local plans_total="${1:-}"
  local summaries_total="${2:-}"
  local git_evidence="${3:-}"
  local summary_gap

  case "$plans_total" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$summaries_total" in
    ''|*[!0-9]*) return 1 ;;
  esac

  if [ "$plans_total" -eq 0 ] || [ "$summaries_total" -ge "$plans_total" ]; then
    return 0
  fi

  summary_gap=$((plans_total - summaries_total))
  [ "$summary_gap" -le 1 ] && [ "$git_evidence" = fresh-conforming ]
}
