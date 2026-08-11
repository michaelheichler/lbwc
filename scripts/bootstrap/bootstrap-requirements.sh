#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: bootstrap-requirements.sh OUTPUT_PATH DISCOVERY_JSON_PATH [RESEARCH_FILE]" >&2
  exit 1
fi

OUTPUT_PATH="$1"
DISCOVERY_JSON="$2"
RESEARCH_FILE="${3:-}"

if [[ ! -f "$DISCOVERY_JSON" ]]; then
  echo "Error: Discovery file not found: $DISCOVERY_JSON" >&2
  exit 1
fi

if ! jq empty "$DISCOVERY_JSON" 2>/dev/null; then
  echo "Error: Invalid JSON in $DISCOVERY_JSON" >&2
  exit 1
fi

RESEARCH_AVAILABLE=false
if [ -n "$RESEARCH_FILE" ] && [ -f "$RESEARCH_FILE" ]; then
  RESEARCH_AVAILABLE=true
fi

CREATED=$(date +%Y-%m-%d)

mkdir -p "$(dirname "$OUTPUT_PATH")"

ANSWERED_COUNT=$(jq '[.answered[]? | if type == "string" then . elif type == "object" then .answer? else empty end | select(type == "string" and length > 0)] | length' "$DISCOVERY_JSON")
INFERRED_COUNT=$(jq '[.inferred[]? | select((.text? // .) | type == "string" and length > 0)] | length' "$DISCOVERY_JSON")

{
  echo "# Requirements"
  echo ""
  echo "Defined: ${CREATED}"
  echo ""
  echo "## Requirements"
  echo ""

  REQ_NUM=1
  # Invariant: The emitted answered prefix is contiguous and its count is one less than REQ_NUM. Variant: ANSWERED_COUNT minus i.
  for ((i = 0; i < ANSWERED_COUNT; i++)); do
    REQ_ID=$(printf "REQ-%02d" "$REQ_NUM")
    REQ_TEXT=$(jq -r --argjson i "$i" '[.answered[]? | if type == "string" then . elif type == "object" then .answer? else empty end | select(type == "string" and length > 0)][$i]' "$DISCOVERY_JSON")

    echo "### ${REQ_ID}: ${REQ_TEXT}"
    echo "**Must-have**"
    echo ""
    REQ_NUM=$((REQ_NUM + 1))
  done

  # Invariant: The emitted answered-first prefix is contiguous and its count is one less than REQ_NUM. Variant: INFERRED_COUNT minus i.
  for ((i = 0; i < INFERRED_COUNT; i++)); do
    REQ_ID=$(printf "REQ-%02d" "$REQ_NUM")
    REQ_TEXT=$(jq -r --argjson i "$i" '[.inferred[]? | select((.text? // .) | type == "string" and length > 0)][$i] | .text? // .' "$DISCOVERY_JSON")
    REQ_PRIORITY=$(jq -r --argjson i "$i" '[.inferred[]? | select((.text? // .) | type == "string" and length > 0)][$i] | .priority? // "Must-have"' "$DISCOVERY_JSON")

    echo "### ${REQ_ID}: ${REQ_TEXT}"
    echo "**${REQ_PRIORITY}**"
    echo ""
    REQ_NUM=$((REQ_NUM + 1))
  done

  if ((REQ_NUM == 1)); then
    echo "_(No requirements defined yet)_"
    echo ""
  fi

  echo "## Out of Scope"
  echo ""
  echo "_(To be defined)_"
  echo ""
} > "$OUTPUT_PATH"

if [ "$RESEARCH_AVAILABLE" = true ]; then
  DOMAIN=$(jq -r 'first(.answered[]? | if type == "object" then select(has("category") and has("answer") and .category == "scope" and (.answer | type == "string")) | .answer elif type == "string" then . else empty end | select(length > 0)) // ""' "$DISCOVERY_JSON" | awk '{print $1}')
  DATE=$(date +%Y-%m-%d)
  jq --arg domain "$DOMAIN" --arg date "$DATE" \
     '.research_summary = {available: true, domain: $domain, date: $date, key_findings: []}' \
     "$DISCOVERY_JSON" > "$DISCOVERY_JSON.tmp" && mv "$DISCOVERY_JSON.tmp" "$DISCOVERY_JSON"
else
  jq '.research_summary = {available: false}' "$DISCOVERY_JSON" > "$DISCOVERY_JSON.tmp" && mv "$DISCOVERY_JSON.tmp" "$DISCOVERY_JSON"
fi

exit 0
