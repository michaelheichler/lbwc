#!/usr/bin/env bash

set -u

LBWC_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

LBWC_CANONICAL_HEADERS=(
  "## Active Context"
  "## LBWC Rules"
  "## Code Intelligence"
  "## Plugin Isolation"
)
: "${LBWC_CANONICAL_HEADERS[*]}"

lbwc_generate_active_context_section() {
  cat <<'EOF'
## Active Context

**Work:** No active milestone
**Last shipped:** _(none yet)_
**Next action:** Run /lbwc:vibe to start a new milestone, or /lbwc:status to review progress
EOF
}

lbwc_generate_lbwc_rules_section() {
  cat <<'EOF'
## LBWC Rules

- **Always use LBWC commands** for project work. Do not manually edit files in `.lbwc-planning/`.
- **Commit format:** `{type}({scope}): {description}`, types: feat, fix, test, refactor, perf, docs, style, chore.
- **One commit per task.** Each task in a plan gets exactly one atomic commit.
- **Never commit secrets.** Do not stage .env, .pem, .key, credentials, or token files.
- **Plan before building.** Use /lbwc:vibe for all lifecycle actions. Plans are the source of truth.
- **Do not fabricate content.** Only use what the user explicitly states in project-defining flows.
- **Git stays in the main session.** Do not use Git in delegated work. Never push unless the user explicitly requests it. Run `scripts/version-bump.sh` only when the user asks.
EOF
}

lbwc_generate_code_intelligence_section() {
  echo "## Code Intelligence"
  lbwc_generate_code_intelligence_guidance
}

lbwc_generate_code_intelligence_guidance() {
  cat "$LBWC_LIB_DIR/claude-md-code-intelligence.txt"
}

lbwc_generate_plugin_isolation_section() {
  echo "## Plugin Isolation"
  cat "$LBWC_LIB_DIR/claude-md-plugin-isolation.txt"
}

lbwc_markdown_has_exact_heading() {
  local file="$1"
  local heading="$2"

  [ -f "$file" ] || return 1

  awk -v heading="$heading" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (line == heading) {
        found = 1
        exit 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

lbwc_markdown_has_heading_title() {
  local file="$1"
  local title="$2"

  [ -f "$file" ] || return 1

  awk -v title="$title" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    /^#{1,6}[[:space:]]+/ {
      line = $0
      sub(/^#{1,6}[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == title) {
        found = 1
        exit 0
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

lbwc_markdown_has_text_outside_fences() {
  local file="$1"
  local needle="$2"

  [ -f "$file" ] || return 1

  awk -v needle="$needle" '
    BEGIN { in_fence = 0; found = 0 }
    /^[[:space:]]*```/ || /^[[:space:]]*~~~/ { in_fence = !in_fence; next }
    in_fence { next }
    index($0, needle) > 0 {
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

lbwc_markdown_has_code_intelligence() {
  local file="$1"

  if lbwc_markdown_has_heading_title "$file" "Code Intelligence"; then
    return 0
  fi

  if lbwc_markdown_has_text_outside_fences "$file" "Prefer LSP over"; then
    return 0
  fi

  return 1
}

lbwc_should_emit_managed_section() {
  local file="$1"
  local title="$2"
  local exact_heading="$3"

  if lbwc_markdown_has_exact_heading "$file" "$exact_heading"; then
    return 0
  fi

  if lbwc_markdown_has_heading_title "$file" "$title"; then
    return 1
  fi

  return 0
}

lbwc_should_emit_code_intelligence_section() {
  local file="$1"

  if lbwc_markdown_has_exact_heading "$file" "## Code Intelligence"; then
    return 0
  fi

  if lbwc_markdown_has_code_intelligence "$file"; then
    return 1
  fi

  return 0
}

lbwc_strip_legacy_refresh_sections() {
  local input="$1"
  local output="$2"
  local awk_program="$LBWC_LIB_DIR/claude-md-strip-legacy.awk"

  awk -f "$awk_program" "$input" > "$output"
}