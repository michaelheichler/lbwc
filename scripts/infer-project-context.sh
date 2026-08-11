#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: infer-project-context.sh CODEBASE_DIR [REPO_ROOT]"
  echo ""
  echo "Extract project context from codebase mapping files."
  echo ""
  echo "  CODEBASE_DIR  Path to .lbwc-planning/codebase/ mapping files"
  echo "  REPO_ROOT     Optional, defaults to current directory"
  echo ""
  echo "Outputs structured JSON to stdout with source attribution per field."
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Error: CODEBASE_DIR is required" >&2
  echo "Usage: infer-project-context.sh CODEBASE_DIR [REPO_ROOT]" >&2
  exit 1
fi

CODEBASE_DIR="$1"
REPO_ROOT="${2:-$(pwd)}"

if [[ ! -d "$CODEBASE_DIR" ]]; then
  echo "Error: CODEBASE_DIR does not exist: $CODEBASE_DIR" >&2
  exit 1
fi

NAME_VALUE=""
NAME_SOURCE=""

if [[ -z "$NAME_VALUE" ]]; then
  repo_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
  if [[ -n "$repo_url" ]]; then
    repo_name=$(echo "$repo_url" | sed 's/.*\///' | sed 's/\.git$//')
    if [[ -n "$repo_name" ]]; then
      NAME_VALUE="$repo_name"
      NAME_SOURCE="repo"
    fi
  fi
fi

if [[ -z "$NAME_VALUE" ]]; then
  plugin_json="$REPO_ROOT/.claude-plugin/plugin.json"
  if [[ -f "$plugin_json" ]]; then
    pname=$(jq -r '.name // empty' "$plugin_json" 2>/dev/null || true)
    if [[ -n "$pname" ]]; then
      NAME_VALUE="$pname"
      NAME_SOURCE="plugin.json"
    fi
  fi
fi

if [[ -z "$NAME_VALUE" ]]; then
  NAME_VALUE=$(basename "$REPO_ROOT")
  NAME_SOURCE="directory"
fi

NAME_JSON=$(jq -n --arg v "$NAME_VALUE" --arg s "$NAME_SOURCE" \
  '{value: $v, source: $s}')

STACK_FILE="$CODEBASE_DIR/STACK.md"
if [[ -f "$STACK_FILE" ]]; then
  stack_items=()

  # Parse Languages table: lines matching "| Name | ..." pattern (skip header/separator)
  in_languages=false
  while IFS= read -r line; do
    if [[ "$line" == "## Languages" ]]; then
      in_languages=true
      continue
    fi
    if $in_languages; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "| "* && "$line" != "| Language"* && "$line" != "|--"* && "$line" != "|-"* ]]; then
        lang=$(echo "$line" | sed 's/^| *//' | sed 's/ *|.*//')
        if [[ -n "$lang" ]]; then
          stack_items+=("$lang")
        fi
      fi
    fi
  done < "$STACK_FILE"

  in_key_tech=false
  while IFS= read -r line; do
    if [[ "$line" == "## Key Technologies" ]]; then
      in_key_tech=true
      continue
    fi
    if $in_key_tech; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "- "* ]]; then
        tech=$(echo "$line" | sed 's/^- \*\*//' | sed 's/\*\*.*//')
        if [[ -n "$tech" ]]; then
          stack_items+=("$tech")
        fi
      fi
    fi
  done < "$STACK_FILE"

  if [[ ${#stack_items[@]} -gt 0 ]]; then
    STACK_JSON=$(printf '%s\n' "${stack_items[@]}" | jq -R . | jq -s '{value: ., source: "STACK.md"}')
  else
    STACK_JSON='{"value": null, "source": null}'
  fi
else
  STACK_JSON='{"value": null, "source": null}'
fi

ARCH_FILE="$CODEBASE_DIR/ARCHITECTURE.md"
if [[ -f "$ARCH_FILE" ]]; then
  arch_text=""
  in_overview=false
  while IFS= read -r line; do
    if [[ "$line" == "## Overview" ]]; then
      in_overview=true
      continue
    fi
    if $in_overview; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ -n "$line" ]]; then
        if [[ -n "$arch_text" ]]; then
          arch_text="$arch_text $line"
        else
          arch_text="$line"
        fi
      fi
    fi
  done < "$ARCH_FILE"

  if [[ -n "$arch_text" ]]; then
    ARCH_JSON=$(jq -n --arg v "$arch_text" '{value: $v, source: "ARCHITECTURE.md"}')
  else
    ARCH_JSON='{"value": null, "source": null}'
  fi
else
  ARCH_JSON='{"value": null, "source": null}'
fi

extract_first_paragraph() {
  local file="$1" heading="$2" in_section=false paragraph="" line

  # Invariant: paragraph contains only the selected section's first paragraph. Variant: unread input lines.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$heading" ]]; then
      in_section=true
      continue
    fi
    $in_section || continue
    [[ "$line" == "## "* ]] && break
    if [[ -z "$line" ]]; then
      [[ -n "$paragraph" ]] && break
      continue
    fi
    paragraph+="${paragraph:+ }$line"
  done < "$file"

  printf '%s' "$paragraph"
}

PURPOSE_JSON='{"value": null, "source": null}'
if [[ -f "$STACK_FILE" ]]; then
  purpose_heading="## Purpose"
  purpose_text=$(extract_first_paragraph "$STACK_FILE" "$purpose_heading")

  if [[ -z "$purpose_text" ]]; then
    purpose_heading="## What this repo is"
    purpose_text=$(extract_first_paragraph "$STACK_FILE" "$purpose_heading")
  fi

  if [[ -n "$purpose_text" ]]; then
    purpose_source="STACK.md: ${purpose_heading#\#\# }"
    PURPOSE_JSON=$(jq -n --arg v "$purpose_text" --arg s "$purpose_source" '{value: $v, source: $s}')
  fi
fi

INDEX_FILE="$CODEBASE_DIR/INDEX.md"
if [[ -f "$INDEX_FILE" ]]; then
  features=()
  in_themes=false
  while IFS= read -r line; do
    if [[ "$line" == "## Cross-Cutting Themes" ]]; then
      in_themes=true
      continue
    fi
    if $in_themes; then
      if [[ "$line" == "##"* ]]; then
        break
      fi
      if [[ "$line" == "- "* ]]; then
        feature=$(echo "$line" | sed 's/^- \*\*//' | sed 's/\*\*:.*//')
        if [[ -n "$feature" ]]; then
          features+=("$feature")
        fi
      fi
    fi
  done < "$INDEX_FILE"

  if [[ ${#features[@]} -gt 0 ]]; then
    FEATURES_JSON=$(printf '%s\n' "${features[@]}" | jq -R . | jq -s '{value: ., source: "INDEX.md"}')
  else
    FEATURES_JSON='{"value": null, "source": null}'
  fi
else
  FEATURES_JSON='{"value": null, "source": null}'
fi

jq -n \
  --argjson name "$NAME_JSON" \
  --argjson tech_stack "$STACK_JSON" \
  --argjson architecture "$ARCH_JSON" \
  --argjson purpose "$PURPOSE_JSON" \
  --argjson features "$FEATURES_JSON" \
  '{
    name: $name,
    tech_stack: $tech_stack,
    architecture: $architecture,
    purpose: $purpose,
    features: $features
  }'

exit 0
