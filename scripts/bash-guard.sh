#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
LBWC_PLANNING_DIR="${LBWC_PLANNING_DIR:-.lbwc-planning}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate bash command" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || { echo "Blocked: unable to read bash guard input" >&2; exit 2; }
[ -n "$INPUT" ] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || COMMAND=""
[ -z "$COMMAND" ] && exit 0

ALLOW_DESTRUCTIVE=0
[ "${LBWC_ALLOW_DESTRUCTIVE:-0}" = "1" ] && ALLOW_DESTRUCTIVE=1

command_without_quoted_text() {
  local command="$1" index=0 length character output="" in_single=0 in_double=0 escaped=0
  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"
    if [ "$escaped" -eq 1 ]; then
      output="${output} "; escaped=0; index=$((index + 1)); continue
    fi
    if [ "$in_single" -eq 1 ]; then
      [ "$character" = "'" ] && in_single=0
      output="${output} "; index=$((index + 1)); continue
    fi
    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then escaped=1
      elif [ "$character" = '"' ]; then in_double=0
      fi
      output="${output} "; index=$((index + 1)); continue
    fi
    case "$character" in
      "'") in_single=1; output="${output} " ;;
      '"') in_double=1; output="${output} " ;;
      "\\") escaped=1; output="${output} " ;;
      *) output="${output}${character}" ;;
    esac
    index=$((index + 1))
  done
  printf '%s' "$output"
}

command_without_shell_syntax() {
  local command="$1" index=0 length character output="" in_single=0 in_double=0 escaped=0
  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"
    if [ "$escaped" -eq 1 ]; then
      output="${output}${character}"; escaped=0; index=$((index + 1)); continue
    fi
    if [ "$in_single" -eq 1 ]; then
      if [ "$character" = "'" ]; then in_single=0; else output="${output}${character}"; fi
      index=$((index + 1)); continue
    fi
    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then escaped=1
      elif [ "$character" = '"' ]; then in_double=0
      else output="${output}${character}"
      fi
      index=$((index + 1)); continue
    fi
    case "$character" in
      "'") in_single=1 ;;
      '"') in_double=1 ;;
      "\\") escaped=1 ;;
      *) output="${output}${character}" ;;
    esac
    index=$((index + 1))
  done
  printf '%s' "$output"
}

MASKED_COMMAND=$(command_without_quoted_text "$COMMAND")

if [ "$ALLOW_DESTRUCTIVE" != "1" ]; then
  PATTERNS=""
  for PFILE in "$PLUGIN_ROOT/config/destructive-commands.txt" "$LBWC_PLANNING_DIR/destructive-commands.local.txt"; do
    [ -f "$PFILE" ] || continue
    FILE_PATTERNS=$(grep -v '^[[:space:]]*#' "$PFILE" | grep -v '^[[:space:]]*$' | tr '\n' '|' | sed 's/|$//')
    [ -n "$FILE_PATTERNS" ] && { [ -n "$PATTERNS" ] && PATTERNS="$PATTERNS|$FILE_PATTERNS" || PATTERNS="$FILE_PATTERNS"; }
  done

  if [ -n "$PATTERNS" ] && printf '%s' "$MASKED_COMMAND" | grep -iqE "$PATTERNS"; then
    MATCH=$(printf '%s' "$MASKED_COMMAND" | grep -ioE "$PATTERNS" | head -1)
    echo "Blocked: destructive command detected ($MATCH)
Hint: Use LBWC_ALLOW_DESTRUCTIVE=1 to override.
See: config/destructive-commands.txt for the full blocklist." >&2
    exit 2
  fi
fi

resolve_agent_role() {
  local identifier="$1" manifest_path
  [ -n "$identifier" ] || return 1
  manifest_path="$LBWC_PLANNING_DIR/.agent-manifest.json"
  [ -f "$manifest_path" ] || return 1
  jq -r --arg id "$identifier" '.agents[$id].role // empty' "$manifest_path" 2>/dev/null
}

generated_agent_policy_state() {
  local identifier="$1" manifest_path
  case "$identifier" in lbwc-?*) ;; *) return 1 ;; esac
  manifest_path="$LBWC_PLANNING_DIR/.agent-manifest.json"
  [ -f "$manifest_path" ] || { printf '%s' "unverified"; return 0; }
  if ! jq -e --arg id "$identifier" '
    .agents[$id]
    | select(.state == "registered" or .state == "running")
  ' "$manifest_path" >/dev/null 2>&1; then
    printf '%s' "unverified"
    return 0
  fi
  printf '%s' "active"
}

command_mentions_shell() {
  local command="$1"
  printf '%s' "$command" | grep -qiE '(^|[^[:alnum:]_.-])(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'
}

command_runs_shell_code() {
  local command="$1"
  command_mentions_shell "$command" || return 1
  printf '%s' "$command" | grep -qiE '(^|[^[:alnum:]_.-])-[[:alpha:]]*c([^[:alnum:]_.-]|$)'
}

command_invokes_shell_interpreter() {
  local command="$1"
  if printf '%s' "$command" | grep -qiE '(^|[;&|()])[[:space:]]*(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  if printf '%s' "$command" | grep -qiE '(^|[;&|()])[[:space:]]*(command|exec)[[:space:]]+(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  if printf '%s' "$command" | grep -qiE '(^|[;&|()])[[:space:]]*rtk[[:space:]]+proxy[[:space:]]+(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  printf '%s' "$command" | grep -qiE '(^|[;&|()])[[:space:]]*env([[:space:]]+[^[:space:]]+)*[[:space:]]+(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'
}

command_uses_shell_stdin() {
  local command="$1"
  command_mentions_shell "$command" || return 1
  if printf '%s' "$command" | grep -q '<'; then
    return 0
  fi
  printf '%s' "$command" | grep -qE '\|[[:space:]]*(env[[:space:]]+[^|[:space:]]+[[:space:]]+)?(bash|sh|zsh|dash|ksh|fish)([^[:alnum:]_.-]|$)'
}

command_uses_source() {
  local command="$1"
  printf '%s' "$command" | grep -qE '(^|[;&|])[[:space:]]*(source([[:space:]]|\$[{]?IFS[}]?)|\.[[:space:]])'
}

command_targets_protected_control_path() {
  local command="$1" normalized
  normalized=$(command_without_shell_syntax "$command")
  case "$command" in
    *config/*|*.lbwc-planning/config.json*|*.lbwc-planning/.agent-manifest*|*.lbwc-planning/.contracts*|*.temporary-agent-runfiles*|*.claude/agents*|*.git/*|*scripts/agent-generator.sh*|*scripts/agent-lifecycle.sh*|*scripts/agent-spawn-guard.sh*|*scripts/bash-guard.sh*|*scripts/file-guard.sh*|*scripts/security-filter.sh*|*scripts/task-contract.sh*|*scripts/render-agent-template.sh*|*scripts/lib/agent-manifest.sh*) return 0 ;;
  esac
  case "$normalized" in
    *config/*|*.lbwc-planning/config.json*|*.lbwc-planning/.agent-manifest*|*.lbwc-planning/.contracts*|*.temporary-agent-runfiles*|*.claude/agents*|*.git/*|*scripts/agent-generator.sh*|*scripts/agent-lifecycle.sh*|*scripts/agent-spawn-guard.sh*|*scripts/bash-guard.sh*|*scripts/file-guard.sh*|*scripts/security-filter.sh*|*scripts/task-contract.sh*|*scripts/render-agent-template.sh*|*scripts/lib/agent-manifest.sh*) return 0 ;;
  esac
  case "$normalized" in
    *python*-c*config*subagent-critical-execution.txt*|*python*-c*subagent-critical-execution.txt*config*) return 0 ;;
  esac
  return 1
}

command_invokes_git() {
  local command="$1" unquoted normalized
  unquoted=$(command_without_quoted_text "$command")
  if printf '%s' "$unquoted" | grep -qiE '(^|[^[:alnum:]_.-])([^[:space:]]*/)?git([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  normalized=$(command_without_shell_syntax "$command")
  if printf '%s' "$normalized" | grep -qiE '(^|[^[:alnum:]_.-])([^[:space:]]*/)?git([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  if printf '%s' "$command" | grep -qiE '(^|[^[:alnum:]_.-])\\git([^[:alnum:]_.-]|$)'; then
    return 0
  fi
  command_runs_shell_code "$command" || return 1
  printf '%s' "$command" | grep -qiE '(^|[^[:alnum:]_.-])([^[:space:]]*/)?git([^[:alnum:]_.-]|$)'
}

critical_execution_patterns() {
  local policy_file="$PLUGIN_ROOT/config/subagent-critical-execution.txt" line patterns=""
  [ -f "$policy_file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*|'|') continue ;;
      '|'*) line="${line#|}" ;;
    esac
    patterns="${patterns:+$patterns|}$line"
  done < "$policy_file"
  [ -n "$patterns" ] || return 1
  printf '%s' "$patterns"
}

command_is_critical_execution() {
  local command="$1" patterns unquoted normalized
  patterns=$(critical_execution_patterns) || return 2
  unquoted=$(command_without_quoted_text "$command")
  if printf '%s' "$unquoted" | grep -qiE "$patterns"; then
    return 0
  fi
  normalized=$(command_without_shell_syntax "$command")
  if printf '%s' "$normalized" | grep -qiE "$patterns"; then
    return 0
  fi
  command_runs_shell_code "$command" || return 1
  printf '%s' "$command" | grep -qiE "$patterns"
}

AGENT_IDENTIFIER=$(printf '%s' "$INPUT" | jq -r '
  .agent_id // .agentId // .agent_type // .agentType // .subagent_type // .subagentType // .name // empty
' 2>/dev/null) || AGENT_IDENTIFIER=""
AGENT_ROLE=$(resolve_agent_role "$AGENT_IDENTIFIER")

POLICY_STATE=$(generated_agent_policy_state "$AGENT_IDENTIFIER") || POLICY_STATE=""
if [ -n "$POLICY_STATE" ]; then
  if command_targets_protected_control_path "$COMMAND"; then
    echo "Blocked: generated agent cannot target a protected control path" >&2
    exit 2
  fi
  if command_uses_source "$COMMAND" || command_uses_shell_stdin "$COMMAND" || command_invokes_shell_interpreter "$COMMAND" || command_runs_shell_code "$COMMAND"; then
    echo "Blocked: generated agent cannot use a shell execution route" >&2
    exit 2
  fi
  if command_invokes_git "$COMMAND"; then
    echo "Blocked: Git is reserved for the main session" >&2
    exit 2
  fi
  if command_is_critical_execution "$COMMAND"; then
    echo "Blocked: generated agent cannot run a critical execution command" >&2
    exit 2
  else
    POLICY_CHECK_STATUS=$?
    if [ "$POLICY_CHECK_STATUS" -eq 2 ]; then
      echo "Blocked: generated agent critical execution policy is unavailable" >&2
      exit 2
    fi
  fi
fi

case "$AGENT_ROLE" in
  scout|qa)
    if printf '%s' "$MASKED_COMMAND" | grep -qE '(^|[[:space:];|&])(rm|mv|cp|mkdir|rmdir|touch|chmod|chown|ln|install|truncate|tee)([[:space:]]|$)'; then
      echo "Blocked: role '$AGENT_ROLE' is read-only (filesystem mutation command)" >&2
      exit 2
    fi
    if printf '%s' "$MASKED_COMMAND" | grep -qE '(^|[^><])>{1,2}[^&]|(^|[[:space:];|&])eval([[:space:];|&()]|$)|\$\(|`'; then
      echo "Blocked: role '$AGENT_ROLE' is read-only (write redirection, substitution, or eval)" >&2
      exit 2
    fi
    if printf '%s' "$MASKED_COMMAND" | grep -qE '(^|[[:space:];|&])(bash|sh|zsh|dash|ksh|fish)([[:space:]]+[^;|&]*)?[[:space:]]-[a-zA-Z]*c'; then
      echo "Blocked: role '$AGENT_ROLE' is read-only (nested shell execution)" >&2
      exit 2
    fi
    ;;
esac

exit 0
