#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/lib/claude-md-lbwc-sections.sh"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"
CLAUDE_MD="CLAUDE.md"

if [ ! -f "$LIB" ]; then
  echo "ERROR: helper library not found at $LIB" >&2
  exit 2
fi

source "$SCRIPT_DIR/lib/claude-md-lbwc-sections.sh"

FIX=false
JSON=false
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=true ;;
    --json) JSON=true ;;
  esac
done

LBWC_SECTION_TITLES=(
  "Active Context"
  "LBWC Rules"
  "Code Intelligence"
  "Plugin Isolation"
)

if [ ! -d "$PLANNING_DIR" ]; then
  if [ "$JSON" = true ]; then
    echo '{"stale":false,"reason":"no_project","missing_sections":[],"version_mismatch":false}'
  fi
  exit 0
fi

if [ ! -f "$CLAUDE_MD" ]; then
  if [ "$JSON" = true ]; then
    echo '{"stale":true,"reason":"no_claude_md","missing_sections":[],"version_mismatch":false}'
  fi
  if [ "$FIX" = true ]; then
    exit 2
  fi
  exit 1
fi

INSTALLED_VER=""
if [ -f "$SCRIPT_DIR/../.claude-plugin/plugin.json" ] && command -v jq &>/dev/null; then
  INSTALLED_VER=$(jq -r '.version // ""' "$SCRIPT_DIR/../.claude-plugin/plugin.json" 2>/dev/null) || INSTALLED_VER=""
elif [ -f "$SCRIPT_DIR/../VERSION" ]; then
  INSTALLED_VER=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null | tr -d '[:space:]') || INSTALLED_VER=""
fi

MARKER_FILE="$PLANNING_DIR/.claude-md-version"
MARKER_VER=""
if [ -f "$MARKER_FILE" ]; then
  MARKER_VER=$(cat "$MARKER_FILE" 2>/dev/null | tr -d '[:space:]') || MARKER_VER=""
fi

MISSING_SECTIONS=()
for title in "${LBWC_SECTION_TITLES[@]}"; do
  if [ "$title" = "Code Intelligence" ]; then
    if lbwc_markdown_has_code_intelligence "$CLAUDE_MD"; then
      continue
    fi
  else
    if lbwc_markdown_has_heading_title "$CLAUDE_MD" "$title"; then
      continue
    fi
  fi

  MISSING_SECTIONS+=("## $title")
done

VERSION_MISMATCH=false
if [ -n "$INSTALLED_VER" ] && [ "$INSTALLED_VER" != "$MARKER_VER" ]; then
  VERSION_MISMATCH=true
fi

STALE=false
REASON=""
if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then
  STALE=true
  REASON="missing_sections"
elif [ "$VERSION_MISMATCH" = true ]; then
  STALE=true
  REASON="version_mismatch"
fi

if [ "$JSON" = true ] && [ "$FIX" = false ]; then
  MISSING_JSON="["
  first=true
  for s in "${MISSING_SECTIONS[@]+"${MISSING_SECTIONS[@]}"}"; do
    if [ "$first" = true ]; then first=false; else MISSING_JSON="$MISSING_JSON,"; fi
    MISSING_JSON="$MISSING_JSON\"$s\""
  done
  MISSING_JSON="$MISSING_JSON]"

  echo "{\"stale\":$STALE,\"reason\":\"${REASON:-fresh}\",\"missing_sections\":$MISSING_JSON,\"version_mismatch\":$VERSION_MISMATCH,\"installed_version\":\"${INSTALLED_VER:-unknown}\",\"marker_version\":\"${MARKER_VER:-none}\"}"

  if [ "$STALE" = true ]; then exit 1; else exit 0; fi
fi

if [ "$FIX" = true ] && [ "$STALE" = true ]; then
  REFRESHER="$SCRIPT_DIR/refresh-claude-md-lbwc-sections.sh"
  if [ ! -f "$REFRESHER" ]; then
    echo "ERROR: refresh-claude-md-lbwc-sections.sh not found at $REFRESHER" >&2
    exit 2
  fi

  if bash "$REFRESHER" "$CLAUDE_MD" 2>/dev/null; then
    echo "$INSTALLED_VER" > "$MARKER_FILE" 2>/dev/null || true

    if [ "$JSON" = true ]; then
      echo "{\"fixed\":true,\"installed_version\":\"${INSTALLED_VER:-unknown}\",\"previous_marker\":\"${MARKER_VER:-none}\"}"
    else
      echo "CLAUDE.md LBWC sections refreshed in place (${MARKER_VER:-none} -> ${INSTALLED_VER:-unknown}). Non-LBWC content preserved."
    fi
    exit 0
  else
    echo "ERROR: refresh-claude-md-lbwc-sections.sh failed" >&2
    exit 2
  fi
fi

if [ "$STALE" = true ]; then
  echo "STALE: CLAUDE.md LBWC sections need refresh"
  if [ ${#MISSING_SECTIONS[@]} -gt 0 ]; then
    echo "  Missing sections:"
    for s in "${MISSING_SECTIONS[@]}"; do
      echo "    - $s"
    done
  fi
  if [ "$VERSION_MISMATCH" = true ]; then
    echo "  Version: marker=${MARKER_VER:-none}, installed=${INSTALLED_VER:-unknown}"
  fi
  echo "  Run with --fix to refresh LBWC-owned sections in place (all other CLAUDE.md content preserved)."
  exit 1
else
  if [ -n "$INSTALLED_VER" ] && [ ! -f "$MARKER_FILE" ]; then
    echo "$INSTALLED_VER" > "$MARKER_FILE" 2>/dev/null || true
  fi
  echo "FRESH: CLAUDE.md LBWC sections are current (v${INSTALLED_VER:-unknown})"
  exit 0
fi
