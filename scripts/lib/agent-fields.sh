#!/usr/bin/env bash
# Shared field-token map and role validation for the agent-generation cluster.
# Sourced by agent-generator.sh, render-agent-template.sh, and resolve-agent-settings.sh.
set -u

# Map a frontmatter field name (any accepted casing) to its {{TOKEN}} name.
# Prints the token on success, returns 1 for an unknown field.
agent_field_token() {
  case "$1" in
    name|NAME) printf 'NAME' ;;
    description|DESCRIPTION|--description) printf 'DESCRIPTION' ;;
    tools|TOOLS|--tools) printf 'TOOLS' ;;
    disallowedTools|DISALLOWED_TOOLS|--disallowed-tools) printf 'DISALLOWED_TOOLS' ;;
    model|MODEL|--model) printf 'MODEL' ;;
    permissionMode|PERMISSION_MODE|--permission-mode) printf 'PERMISSION_MODE' ;;
    maxTurns|MAX_TURNS|--max-turns) printf 'MAX_TURNS' ;;
    skills|SKILLS|--skills) printf 'SKILLS' ;;
    mcpServers|MCP_SERVERS|--mcp-servers) printf 'MCP_SERVERS' ;;
    memory|MEMORY|--memory) printf 'MEMORY' ;;
    background|BACKGROUND|--background) printf 'BACKGROUND' ;;
    effort|EFFORT|--effort) printf 'EFFORT' ;;
    isolation|ISOLATION|--isolation) printf 'ISOLATION' ;;
    color|COLOR|--color) printf 'COLOR' ;;
    initialPrompt|INITIAL_PROMPT|--initial-prompt) printf 'INITIAL_PROMPT' ;;
    reasoning|REASONING|--reasoning) printf 'REASONING' ;;
    job|JOB|--job) printf 'JOB' ;;
    *) return 1 ;;
  esac
}

# Return 0 when $1 is a role defined in the given model-profiles JSON, else 1.
# Usage: agent_role_is_valid <role> <model-profiles.json>
agent_role_is_valid() {
  jq -e --arg r "$1" '[.quality, .balanced, .budget | keys[]] | index($r) != null' \
    "$2" >/dev/null 2>&1
}
