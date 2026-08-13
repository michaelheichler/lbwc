#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SOURCE="${1:-}"
if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
  printf '%s\n' '{"latest_milestone":null,"recent_phases":[],"key_decisions":[],"current_work":null}'
  exit 0
fi

temporary=$(mktemp "${TMPDIR:-/tmp}/lbwc-gsd-summary.XXXXXX")
trap 'rm -f "$temporary"' EXIT
bash "$SCRIPT_DIR/plan-import.sh" normalize --adapter gsd --source "$SOURCE" --output "$temporary"

jq '
  . as $ir
  | {
      latest_milestone: (if ($ir.milestones | length) == 0 then null else {
        name: $ir.milestones[-1].name,
        phase_count: ($ir.phases | length),
        status: (if (($ir.phases | length) > 0 and ([.phases[] | select(.status == "complete")] | length) == ($ir.phases | length)) then "complete" else "in_progress" end)
      } end),
      recent_phases: ([$ir.phases[] | select(.status == "complete") | {
        name: (if .number == null then .slug else ((.number|tostring) + "-" + .slug) end),
        tasks: (.plans | length),
        commits: 0
      }] | .[-3:]),
      key_decisions: [$ir.decisions[].text],
      current_work: ([$ir.phases[] | select(.status != "complete" and .status != null) | {
        phase: (if .number == null then .slug else ((.number|tostring) + "-" + .slug) end),
        status: .status
      }] | .[0] // null)
    }
' "$temporary"
