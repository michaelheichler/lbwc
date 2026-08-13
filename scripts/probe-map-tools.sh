#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"jq is required but not installed"}}'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(pwd)"
PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
GLOBAL_CONFIG_FILE="$HOME/.claude.json"
PROJECT_MCP_FILE="$PROJECT_DIR/.mcp.json"

SERENA_AVAILABLE=false
if [[ -f "$SETTINGS_FILE" ]] && jq -e '(.enabledPlugins // {}) | keys | any(startswith("serena@"))' "$SETTINGS_FILE" >/dev/null 2>&1; then
  SERENA_AVAILABLE=true
  SERENA_REASON="serena@... enabled in $SETTINGS_FILE .enabledPlugins"
elif [[ -f "$SETTINGS_FILE" ]]; then
  SERENA_REASON="no serena@... key in $SETTINGS_FILE .enabledPlugins"
else
  SERENA_REASON="$SETTINGS_FILE not found"
fi

GITNEXUS_AVAILABLE=false
GITNEXUS_REASON="no gitnexus entry found"
if [[ -f "$PROJECT_MCP_FILE" ]] && jq -e '(.mcpServers // {}) | has("gitnexus")' "$PROJECT_MCP_FILE" >/dev/null 2>&1; then
  GITNEXUS_AVAILABLE=true
  GITNEXUS_REASON="gitnexus configured in $PROJECT_MCP_FILE .mcpServers"
elif [[ -f "$GLOBAL_CONFIG_FILE" ]] && jq -e --arg p "$PROJECT_DIR" '(.projects[$p].mcpServers // {}) | has("gitnexus")' "$GLOBAL_CONFIG_FILE" >/dev/null 2>&1; then
  GITNEXUS_AVAILABLE=true
  GITNEXUS_REASON="gitnexus configured in $GLOBAL_CONFIG_FILE .projects[\"$PROJECT_DIR\"].mcpServers"
elif [[ -f "$GLOBAL_CONFIG_FILE" ]] && jq -e '(.mcpServers // {}) | has("gitnexus")' "$GLOBAL_CONFIG_FILE" >/dev/null 2>&1; then
  GITNEXUS_AVAILABLE=true
  GITNEXUS_REASON="gitnexus configured in $GLOBAL_CONFIG_FILE .mcpServers (global scope)"
elif [[ ! -f "$GLOBAL_CONFIG_FILE" ]]; then
  GITNEXUS_REASON="$GLOBAL_CONFIG_FILE not found"
fi

GITNEXUS_INDEXED=false
[[ -d "$PROJECT_DIR/.gitnexus" ]] && GITNEXUS_INDEXED=true

STACK_JSON=$(bash "$SCRIPT_DIR/detect-stack.sh" "$PROJECT_DIR" 2>/dev/null || echo '{"detected_stack":[]}')
DETECTED_STACK=$(echo "$STACK_JSON" | jq -c '.detected_stack // []' 2>/dev/null || echo '[]')
LSP_JSON=$(bash "$SCRIPT_DIR/resolve-lsp.sh" "$DETECTED_STACK" "$SETTINGS_FILE" 2>/dev/null || echo '{"env_needed":true,"plugins":[]}')
LSP_ENV_NEEDED=$(echo "$LSP_JSON" | jq -r '.env_needed' 2>/dev/null || echo true)

LSP_USABLE=false
if [[ "$LSP_ENV_NEEDED" == "false" ]] && echo "$LSP_JSON" | jq -e '(.plugins // []) | any(.plugin_enabled == true or .binary_installed == true)' >/dev/null 2>&1; then
  LSP_USABLE=true
fi

GIT_AVAILABLE=false
if command -v git >/dev/null 2>&1 && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_AVAILABLE=true
fi

CODEBASE_MAP_PATH=""
CODEBASE_MAP_DIGEST=""
CODEBASE_MAP_FRESHNESS="unavailable"
CODEBASE_MAP_META="$PLANNING_DIR/codebase/META.md"
if [[ -f "$CODEBASE_MAP_META" ]]; then
  CODEBASE_MAP_PATH=$(cd "$(dirname "$CODEBASE_MAP_META")" && pwd -P)/$(basename "$CODEBASE_MAP_META")
  if command -v shasum >/dev/null 2>&1; then
    CODEBASE_MAP_DIGEST=$(shasum -a 256 "$CODEBASE_MAP_META" | awk '{print "sha256:" $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    CODEBASE_MAP_DIGEST=$(sha256sum "$CODEBASE_MAP_META" | awk '{print "sha256:" $1}')
  fi
  CODEBASE_MAP_FRESHNESS="stale"
  saved_hash=$(awk '$1 == "git_hash:" {print $2; exit}' "$CODEBASE_MAP_META" 2>/dev/null || true)
  file_count=$(awk '$1 == "file_count:" {print $2; exit}' "$CODEBASE_MAP_META" 2>/dev/null || true)
  current_hash=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)
  if [[ -n "$current_hash" && "$saved_hash" == "$current_hash" && "$file_count" =~ ^[1-9][0-9]*$ ]]; then
    CODEBASE_MAP_FRESHNESS="fresh"
  fi
fi

if [[ "$SERENA_AVAILABLE" == true ]]; then
  RECOMMENDED_ROUTE="serena"
elif [[ "$GITNEXUS_AVAILABLE" == true ]]; then
  RECOMMENDED_ROUTE="gitnexus"
elif [[ "$LSP_USABLE" == true ]]; then
  RECOMMENDED_ROUTE="lsp"
else
  RECOMMENDED_ROUTE="grep-only"
fi

OUTPUT=$(jq -n \
  --argjson serena_available "$SERENA_AVAILABLE" \
  --arg serena_reason "$SERENA_REASON" \
  --argjson gitnexus_available "$GITNEXUS_AVAILABLE" \
  --arg gitnexus_reason "$GITNEXUS_REASON" \
  --argjson gitnexus_indexed "$GITNEXUS_INDEXED" \
  --argjson lsp_env_needed "$LSP_ENV_NEEDED" \
  --argjson lsp_plugins "$(echo "$LSP_JSON" | jq -c '.plugins // []')" \
  --argjson git_available "$GIT_AVAILABLE" \
  --arg recommended_route "$RECOMMENDED_ROUTE" \
  --arg map_path "$CODEBASE_MAP_PATH" \
  --arg map_digest "$CODEBASE_MAP_DIGEST" \
  --arg map_freshness "$CODEBASE_MAP_FRESHNESS" \
  '{
    serena: {available: $serena_available, reason: $serena_reason},
    gitnexus: {available: $gitnexus_available, reason: $gitnexus_reason, indexed: $gitnexus_indexed},
    lsp: {env_needed: $lsp_env_needed, plugins: $lsp_plugins},
    git: {available: $git_available},
    recommended_route: $recommended_route,
    codebase_map: {
      available: ($map_path != ""),
      canonical_path: (if $map_path == "" then null else $map_path end),
      digest: (if $map_digest == "" then null else $map_digest end),
      freshness: $map_freshness
    }
  }')

if [[ -d "$PLANNING_DIR" ]]; then
  printf '%s\n' "$OUTPUT" > "$PLANNING_DIR/MAP-TOOLS.json"
fi

jq -n --argjson data "$OUTPUT" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ($data | tostring)}}'
