#!/usr/bin/env bash
# Known-issues registry for one phase: .lbwc-planning/phases/{NN}-{slug}/known-issues.json
#
# Each entry carries a deterministic 12-hex signature (sha256 of normalized
# test+file+error) as its unique identifier, so the same issue reported twice
# is one entry, and resolution is checked against evidence, not agent claims.
#
#   track-known-issues.sh status <phase-dir>
#       Prints known_issues_path= / known_issues_status=missing|present|malformed
#       / known_issues_count=N (count of entries whose disposition is unresolved).
#   track-known-issues.sh sync-verification <phase-dir> <verification-file>
#       Reads `pre_existing_issues` (JSON array of {test,file,file? ,error}) from the
#       verification file's frontmatter, upserts entries, and marks entries absent
#       from a PASSing verification as resolved.
#   track-known-issues.sh resolve <phase-dir> <signature>
#       Mark one entry resolved by its signature.
#   track-known-issues.sh clear <phase-dir>
#       Remove the registry (round closed clean).
set -euo pipefail

CMD="${1:-}"
PHASE_DIR="${2:-}"
VERIFICATION_FILE="${3:-}"

usage() {
  echo "usage: track-known-issues.sh <status|sync-verification|resolve|clear> <phase-dir> [verification-file|signature]" >&2
  exit 1
}

case "$CMD" in
  status|clear) [ -n "$PHASE_DIR" ] || usage ;;
  sync-verification|resolve) [ -n "$PHASE_DIR" ] && [ -n "$VERIFICATION_FILE" ] || usage ;;
  *) usage ;;
esac

REGISTRY="${PHASE_DIR%/}/known-issues.json"

status_output() {
  echo "known_issues_path=$REGISTRY"
  echo "known_issues_status=$1"
  echo "known_issues_count=$2"
}

registry_valid() {
  [ -f "$REGISTRY" ] || return 1
  jq -e '
    type == "object"
    and (.schema_version | type == "number")
    and (.phase | type == "string")
    and (.issues | type == "array")
    and all(.issues[]; (.signature | type == "string") and (.signature | test("^[0-9a-f]{12}$")))
  ' "$REGISTRY" >/dev/null 2>&1
}

signature_for() {
  jq -rn --arg t "$1" --arg f "$2" --arg e "$3" \
    '[$t, $f, $e] | map(ascii_downcase | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")) | join("\n")' \
    | shasum -a 256 2>/dev/null | cut -c1-12
}

empty_registry() {
  jq -n --arg phase "$(basename "${PHASE_DIR%/}" | sed 's/^\([0-9]*\).*/\1/')" \
    '{schema_version: 1, phase: $phase, issues: []}'
}

write_registry() {
  local tmp
  tmp=$(mktemp "${REGISTRY}.tmp.XXXXXX") || return 1
  printf '%s\n' "$1" > "$tmp" && mv "$tmp" "$REGISTRY" || { rm -f "$tmp"; return 1; }
}

# --- status -----------------------------------------------------------------
if [ "$CMD" = "status" ]; then
  if [ ! -f "$REGISTRY" ]; then
    status_output missing 0; exit 0
  fi
  if ! registry_valid; then
    status_output malformed 0; exit 0
  fi
  COUNT=$(jq '[.issues[] | select((.disposition // "unresolved") == "unresolved")] | length' "$REGISTRY")
  status_output present "$COUNT"
  exit 0
fi

# --- clear ------------------------------------------------------------------
if [ "$CMD" = "clear" ]; then
  rm -f "$REGISTRY"
  status_output missing 0
  exit 0
fi

# --- resolve ----------------------------------------------------------------
if [ "$CMD" = "resolve" ]; then
  SIG="$VERIFICATION_FILE"
  registry_valid || { status_output missing 0; exit 0; }
  UPDATED=$(jq --arg sig "$SIG" '
    .issues = [.issues[] | if .signature == $sig then . + {disposition: "resolved"} else . end]
  ' "$REGISTRY")
  write_registry "$UPDATED"
  status_output present "$(jq '[.issues[] | select((.disposition // "unresolved") == "unresolved")] | length' <<< "$UPDATED")"
  exit 0
fi

# --- sync-verification --------------------------------------------------------
# Frontmatter shape consumed:
#   result: PASS|FAIL|PARTIAL
#   pre_existing_issues:
#     - '{"test":"...","file":"...","error":"..."}'
[ -f "$VERIFICATION_FILE" ] || { status_output missing 0; exit 0; }

RESULT=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^result:[[:space:]]*/ { sub(/^result:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print toupper($0); exit }
' "$VERIFICATION_FILE")

ISSUES_JSON=$(python3 - "$VERIFICATION_FILE" <<'PYEOF'
import json, sys

lines = open(sys.argv[1], encoding="utf-8", errors="ignore").read().splitlines()
in_fm = in_key = False
out = []
for line in lines:
    s = line.strip()
    if not in_fm:
        if s == "---":
            in_fm = True
        continue
    if s == "---":
        break
    if line.startswith("pre_existing_issues:"):
        in_key = True
        continue
    if in_key and line[:1].isalpha() and ":" in line:
        in_key = False
    if in_key and s.startswith("- "):
        payload = s[2:].strip().strip("'\"")
        try:
            item = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict) and item.get("test") and item.get("error"):
            out.append({"test": item["test"], "file": item.get("file") or item["test"], "error": item["error"]})
print(json.dumps(out))
PYEOF
)

# Current registry, or an empty shell.
if registry_valid; then
  CURRENT=$(cat "$REGISTRY")
else
  CURRENT=$(empty_registry)
fi

# Sign each incoming issue, then merge: existing entries keep their history,
# a repeat sighting bumps times_seen, and unresolved prior entries this sync
# did not report stay open until a PASSing verification says otherwise.
NEW_ISSUES="[]"
while IFS= read -r item; do
  [ -n "$item" ] || continue
  T=$(jq -r '.test' <<< "$item")
  F=$(jq -r '.file' <<< "$item")
  E=$(jq -r '.error' <<< "$item")
  SIG=$(signature_for "$T" "$F" "$E")
  NEW_ISSUES=$(jq -cn --argjson arr "$NEW_ISSUES" --arg t "$T" --arg f "$F" --arg e "$E" --arg sig "$SIG" \
    '$arr + [{test: $t, file: $f, error: $e, signature: $sig}]')
done < <(jq -c '.[]' <<< "$ISSUES_JSON" 2>/dev/null)

MERGED=$(jq -cn --argjson current "$CURRENT" --argjson new "$NEW_ISSUES" '
  ($current.issues // []) as $existing
  | ($existing | map(.signature)) as $existing_sigs
  | [ $new[] | . as $n
      | if ($existing_sigs | index($n.signature)) then
          ($existing[] | select(.signature == $n.signature))
          | . + {times_seen: ((.times_seen // 1) + 1)}
        else
          $n + {times_seen: 1, disposition: "unresolved"}
        end
    ] as $synced
  | $synced + [ $existing[]
      | select((.disposition // "unresolved") == "unresolved")
      | select(.signature as $s | [$synced[].signature] | index($s) | not) ]
  | unique_by(.signature)
' 2>/dev/null || printf '%s' "$CURRENT" | jq -c '.issues // []')

# A PASSing verification is evidence the carried issues are gone.
if [ "$RESULT" = "PASS" ]; then
  MERGED=$(jq '[.[] | . + {disposition: "resolved"}]' <<< "$MERGED")
fi

FINAL=$(jq -n --arg phase "$(basename "${PHASE_DIR%/}" | sed 's/^\([0-9]*\).*/\1/')" --argjson issues "$MERGED" \
  '{schema_version: 1, phase: $phase, issues: $issues}')
write_registry "$FINAL"
status_output present "$(jq '[.issues[] | select((.disposition // "unresolved") == "unresolved")] | length' "$REGISTRY")"
