#!/usr/bin/env bash
# Runtime CLI: look up DevIQ corpus articles by keyword, id, or grep.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CORPUS_DIR="$PLUGIN_ROOT/references/deviq-corpus"
INDEX="$CORPUS_DIR/index.json"

MODE="search"
SHOW_ID=""
GREP_QUERY=""
CATEGORY=""
QUERY_WORDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --show)
      MODE="show"
      SHOW_ID="${2:-}"
      shift 2
      ;;
    --grep)
      MODE="grep"
      GREP_QUERY="${2:-}"
      shift 2
      ;;
    --category)
      CATEGORY="${2:-}"
      shift 2
      ;;
    *)
      QUERY_WORDS+=("$1")
      shift
      ;;
  esac
done

QUERY="${QUERY_WORDS[*]:-}"

print_matches() {
  local matches="$1"
  if [ -z "$matches" ]; then
    echo "no match"
    return 0
  fi
  printf '%s\n' "$matches"
}

case "$MODE" in
  show)
    if [ -z "$SHOW_ID" ]; then
      echo "deviq-lookup: --show requires an id"
      exit 0
    fi
    ARTICLE="$CORPUS_DIR/$SHOW_ID.md"
    if [ ! -f "$ARTICLE" ]; then
      echo "deviq-lookup: no article found for id: $SHOW_ID"
      exit 0
    fi
    cat "$ARTICLE"
    exit 0
    ;;

  grep)
    command -v jq >/dev/null 2>&1 || { echo "no match"; exit 0; }
    [ -f "$INDEX" ] || { echo "no match"; exit 0; }
    if [ -z "$GREP_QUERY" ]; then
      echo "no match"
      exit 0
    fi
    if [ -n "$CATEGORY" ]; then
      GREP_TARGET="$CORPUS_DIR/$CATEGORY"
    else
      GREP_TARGET="$CORPUS_DIR"
    fi
    [ -d "$GREP_TARGET" ] || { echo "no match"; exit 0; }
    HITS=$(grep -ril -- "$GREP_QUERY" "$GREP_TARGET" --include='*.md' -r 2>/dev/null | head -8)
    if [ -z "$HITS" ]; then
      echo "no match"
      exit 0
    fi
    RESULT=""
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      rel="${hit#"$CORPUS_DIR"/}"
      id="${rel%.md}"
      line=$(jq -r --arg id "$id" '.[] | select(.id == $id) | "\(.id) | \(.title) | \(.description)"' "$INDEX")
      [ -n "$line" ] && RESULT="${RESULT}${RESULT:+$'\n'}${line}"
    done <<< "$HITS"
    print_matches "$RESULT"
    exit 0
    ;;

  search)
    command -v jq >/dev/null 2>&1 || { echo "no match"; exit 0; }
    [ -f "$INDEX" ] || { echo "no match"; exit 0; }
    RESULT=$(jq -r --arg qraw "$QUERY" --arg cat "$CATEGORY" '
      ($qraw | ascii_downcase) as $q
      | map(select(($cat == "") or (.category == $cat)))
      | map(select(
          ($q == "") or
          (.id | ascii_downcase | contains($q)) or
          (.title | ascii_downcase | contains($q)) or
          (.description | ascii_downcase | contains($q)) or
          ((.aliases // []) | map(ascii_downcase) | any(contains($q)))
        ))
      | .[0:8][]
      | "\(.id) | \(.title) | \(.description)"
    ' "$INDEX" 2>/dev/null)
    print_matches "$RESULT"
    exit 0
    ;;
esac
