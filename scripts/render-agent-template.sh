#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE_DIR="$SCRIPT_DIR/../templates/agent-roles"
ROLE="${1:-}"
shift || true
. "$SCRIPT_DIR/lib/agent-fields.sh"

fail() {
  printf 'render-agent-template: %s\n' "$1" >&2
  exit 1
}

token_for_key() { agent_field_token "$1"; }

PROFILES_PATH="$SCRIPT_DIR/../config/model-profiles.json"
[ -f "$PROFILES_PATH" ] || fail "model profiles not found: $PROFILES_PATH"
agent_role_is_valid "$ROLE" "$PROFILES_PATH" || fail "invalid role '$ROLE'"

TEMPLATE="$TEMPLATE_DIR/$ROLE.md.tpl"
DEFAULTS="$TEMPLATE_DIR/defaults.json"
[ -f "$TEMPLATE" ] || fail "template not found for role '$ROLE'"
[ -f "$DEFAULTS" ] || fail "defaults not found"

declare -A VALUES=()
declare -A EMPTY_TOKENS=()
for field in name description tools disallowedTools model permissionMode maxTurns skills mcpServers memory background effort isolation color initialPrompt; do
  token=$(token_for_key "$field")
  value=$(jq -r --arg role "$ROLE" --arg field "$field" '.[$role][$field] // empty' "$DEFAULTS")
  if [ -n "$value" ]; then
    VALUES["$token"]="$value"
  else
    EMPTY_TOKENS["$token"]=1
  fi
done

for assignment in "$@"; do
  key=${assignment%%=*}
  [ "$key" != "$assignment" ] || fail "expected KEY=VALUE, got '$assignment'"
  value=${assignment#*=}
  token=$(token_for_key "$key") || fail "unknown field '$key'"
  if [ -n "$value" ]; then
    VALUES["$token"]="$value"
    unset "EMPTY_TOKENS[$token]"
  else
    unset "VALUES[$token]"
    EMPTY_TOKENS["$token"]=1
  fi
done

for required in NAME MODEL DESCRIPTION JOB; do
  [ "${VALUES[$required]+set}" = set ] && [ -n "${VALUES[$required]}" ] || fail "missing required field $required"
done

rendered=$(cat "$TEMPLATE")
check_rendered="$rendered"
# Two-pass substitution so user-supplied values can never re-expand tokens.
# Pass 1: replace every {{TOKEN}} with a private sentinel. Pass 2 (below): fill
# each sentinel with the real value. A value containing a literal "{{NAME}}" is
# inserted verbatim because all {{TOKEN}} markers are already gone. Values are
# JSON-escaped (except JOB) so embedded quotes cannot break the frontmatter.
# check_rendered tracks the same passes but masks user content, so the final
# grep for leftover {{TOKEN}} detects an unfilled slot rather than user text.
all_tokens=(NAME DESCRIPTION TOOLS DISALLOWED_TOOLS MODEL PERMISSION_MODE MAX_TURNS SKILLS MCP_SERVERS MEMORY BACKGROUND EFFORT ISOLATION COLOR INITIAL_PROMPT JOB)
for token in "${all_tokens[@]}"; do
  marker="{{$token}}"
  sentinel="__LBWC_TEMPLATE_SLOT_${token}__"
  rendered=${rendered//"$marker"/"$sentinel"}
  check_rendered=${check_rendered//"$marker"/"$sentinel"}
done

for token in "${!VALUES[@]}"; do
  value=${VALUES[$token]}
  if [ "$token" = "JOB" ]; then
    escaped="$value"
  else
    escaped=$(jq -Rn --arg value "$value" '$value')
    escaped=${escaped:1:${#escaped}-2}
  fi
  sentinel="__LBWC_TEMPLATE_SLOT_${token}__"
  rendered=${rendered//"$sentinel"/"$escaped"}
  check_rendered=${check_rendered//"$sentinel"/__LBWC_USER_CONTENT__}
done

for token in "${!EMPTY_TOKENS[@]}"; do
  marker="{{$token}}"
  sentinel="__LBWC_TEMPLATE_SLOT_${token}__"
  rendered=${rendered//"$sentinel"/"$marker"}
  check_rendered=${check_rendered//"$sentinel"/"$marker"}
done

filter_optional_frontmatter() {
  local source=$1
  local filtered=""
  local in_front=0
  local first_line=1
  local field_name field_token
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first_line" -eq 1 ] && [ "$line" = "---" ]; then
      in_front=1
      first_line=0
      filtered+="$line"$'\n'
      continue
    fi
    first_line=0
    if [ "$in_front" -eq 1 ] && [ "$line" = "---" ]; then
      in_front=0
      filtered+="$line"$'\n'
      continue
    fi
    if [ "$in_front" -eq 1 ] && [[ "$line" == *:* ]]; then
      field_name=${line%%:*}
      field_token=$(token_for_key "$field_name" 2>/dev/null || true)
      if [ -n "$field_token" ] && [ "${EMPTY_TOKENS[$field_token]+set}" = set ] && [ "$line" = "$field_name: \"{{$field_token}}\"" ]; then
        continue
      fi
    fi
    filtered+="$line"$'\n'
  done <<< "$source"
  printf '%s' "$filtered"
}

filtered=$(filter_optional_frontmatter "$rendered")
filtered_check=$(filter_optional_frontmatter "$check_rendered")
if grep -qE '\{\{[A-Z_][A-Z0-9_]*\}\}' <<< "$filtered_check"; then
  fail "unresolved template token"
fi
printf '%s' "$filtered"
