#!/usr/bin/env bash

set -euo pipefail

STALE_WARN_THRESHOLD=10   # 1..WARN = inject with warning; >WARN = skip entirely

PLANNING_DIR="${1:-}"
if [ -z "$PLANNING_DIR" ]; then
  echo "Usage: compile-research-context.sh <planning-dir> [description]" >&2
  exit 0
fi
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

EXPLICIT_FILE=""
DESCRIPTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      EXPLICIT_FILE="${2:-}"
      if [ -z "$EXPLICIT_FILE" ]; then
        echo "[research] --file requires a path argument" >&2
        exit 0
      fi
      shift 2
      ;;
    *)
      if [ -n "$DESCRIPTION" ]; then
        DESCRIPTION="${DESCRIPTION} $1"
      else
        DESCRIPTION="$1"
      fi
      shift
      ;;
  esac
done

check_staleness() {
  local file="$1"
  local base_commit
  base_commit=$(awk '
    /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
    in_fm && index($0, "base_commit:") == 1 {
      val = substr($0, length("base_commit:") + 1)
      sub(/^[[:space:]]*/, "", val)
      print val
      exit
    }
  ' "$file")

  if [ -z "$base_commit" ]; then
    return 2  # No base_commit = treat as stale
  fi

  if [ "$base_commit" = "unknown" ]; then
    echo "unknown" >&2  # Migrated file, original commit not tracked
    return 1  # Warn but still inject (migrated files should be usable)
  fi

  if ! git rev-parse --verify "$base_commit^{commit}" > /dev/null 2>&1; then
    return 2  # Invalid commit = treat as stale
  fi

  local commit_count
  commit_count=$(git log --oneline "${base_commit}..HEAD" -- . ':!.lbwc-planning' ':!CLAUDE.md' 2>/dev/null | wc -l | tr -d ' ')

  if [ "$commit_count" -eq 0 ]; then
    return 0  # Fresh
  elif [ "$commit_count" -le "$STALE_WARN_THRESHOLD" ]; then
    echo "$commit_count" >&2  # Pass count via stderr for warning message
    return 1  # Warn but inject
  else
    echo "$commit_count" >&2  # Pass count via stderr for skip message
    return 2  # Too stale (> STALE_WARN_THRESHOLD)
  fi
}

emit_research() {
  local file="$1"
  local staleness_status commit_count_str

  commit_count_str=$(check_staleness "$file" 2>&1; echo "EXIT:$?") || true
  staleness_status="${commit_count_str##*EXIT:}"
  commit_count_str="${commit_count_str%EXIT:*}"
  commit_count_str=$(echo "$commit_count_str" | tr -d '[:space:]')

  case "$staleness_status" in
    0)
      echo "[research] Using fresh research: $(basename "$file")" >&2
      cat "$file"
      ;;
    1)
      local base_commit_short
      base_commit_short=$(awk '
        /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
        in_fm && index($0, "base_commit:") == 1 {
          val = substr($0, length("base_commit:") + 1)
          sub(/^[[:space:]]*/, "", val)
          print val
          exit
        }
      ' "$file" | head -c 8)
      if [ "$commit_count_str" = "unknown" ] || [ "$base_commit_short" = "unknown" ]; then
        echo "⚠ Staleness unknown, this research was migrated without a base commit. Verify findings against current code."
        echo "[research] Using research with staleness warning: $(basename "$file") (base_commit unknown; staleness not computed)" >&2
      else
        echo "⚠ ${commit_count_str} commits have landed since this research was created (${base_commit_short}..HEAD). Verify findings against current code."
        echo "[research] Using research with staleness warning: $(basename "$file") (${commit_count_str} commits since)" >&2
      fi
      echo ""
      cat "$file"
      ;;
    2|*)
      echo "[research] Skipping stale research ($(basename "$file")): ${commit_count_str:-unknown} commits since base_commit" >&2
      ;;
  esac
}

if [ -n "$EXPLICIT_FILE" ]; then
  if [ ! -f "$EXPLICIT_FILE" ]; then
    echo "[research] Specified file not found: $EXPLICIT_FILE" >&2
    exit 0
  fi
  echo "[research] Using explicitly specified research: $(basename "$EXPLICIT_FILE")" >&2
  cat "$EXPLICIT_FILE"
  exit 0
fi

RESEARCH_LIST=$(bash "$SCRIPT_DIR/research-session-state.sh" list "$PLANNING_DIR" --status complete 2>/dev/null || echo "")

if [ -z "$RESEARCH_LIST" ]; then
  exit 0
fi

if [ -z "$DESCRIPTION" ]; then
  exit 0
fi

DESC_WORDS=$(printf '%s' "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | awk 'length >= 3' | sort -u)

if [ -z "$DESC_WORDS" ]; then
  exit 0
fi

BEST_FILE=""
BEST_SCORE=0

while IFS= read -r line; do
  file=$(echo "$line" | jq -r '.file')
  title=$(echo "$line" | jq -r '.title')
  title_lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')

  score=0
  while IFS= read -r word; do
    [ -z "$word" ] && continue
    case "$title_lower" in
      *"$word"*) score=$((score + 1)) ;;
    esac
  done <<< "$DESC_WORDS"

  if [ "$score" -gt "$BEST_SCORE" ]; then
    BEST_SCORE=$score
    BEST_FILE=$file
  fi
done <<< "$RESEARCH_LIST"

if [ "$BEST_SCORE" -ge 2 ] && [ -n "$BEST_FILE" ] && [ -f "$BEST_FILE" ]; then
  emit_research "$BEST_FILE"
fi

exit 0
