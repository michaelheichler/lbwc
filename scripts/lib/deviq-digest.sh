#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN_FILTER="$SCRIPT_DIR/deviq-open-blocks.jq"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
NUDGES_FILE="$PLUGIN_ROOT/config/deviq-nudges.json"

ROOT=".lbwc-planning/deviq"
PHASE_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)
      PHASE_FILTER="${2:?--phase requires a value}"
      shift 2
      ;;
    --root)
      ROOT="${2:?--root requires a value}"
      shift 2
      ;;
    *)
      echo "deviq-digest: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

newest_matching() {
  local file="$1" select="$2" format="$3"
  [ -s "$file" ] || return 0
  jq -c --arg phase "$PHASE_FILTER" "$select" "$file" \
    | tail -n 5 \
    | jq -s -r "$format"
}

NUDGES_JSON=$(jq -c '.' "$NUDGES_FILE" 2>/dev/null) || NUDGES_JSON='[]'
[ -n "$NUDGES_JSON" ] || NUDGES_JSON='[]'

OPEN_ISSUES=""
if [ -s "$ROOT/blocks.jsonl" ]; then
  OPEN_ISSUES=$(jq -c --arg phase "$PHASE_FILTER" 'select($phase == "" or .phase == $phase)' "$ROOT/blocks.jsonl" \
    | jq -s -c -f "$OPEN_FILTER" \
    | jq -r --argjson nudges "$NUDGES_JSON" '
        .[-5:] | reverse[] |
        (.trigger // "") as $t |
        ([$nudges[] | . as $n | select($t != "" and (try ($t | test($n.pattern; "i")) catch false))] | first) as $hit |
        "- [\(.phase)] \($t) (fix: \(.fix // ""))"
          + (if $hit then " (see: \($hit.article))" else "" end)
      ')
fi

RECENT_DECISIONS=$(newest_matching "$ROOT/decisions.jsonl" \
  'select($phase == "" or .phase == $phase)' \
  'reverse[] | "- [\(.phase)] \(.summary // "")"')

if [ -n "$OPEN_ISSUES" ]; then
  printf '## Recent open issues\n%s\n' "$OPEN_ISSUES"
fi

if [ -n "$RECENT_DECISIONS" ]; then
  [ -n "$OPEN_ISSUES" ] && printf '\n'
  printf '## Recent decisions\n%s\n' "$RECENT_DECISIONS"
fi

exit 0
