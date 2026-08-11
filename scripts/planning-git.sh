#!/usr/bin/env bash
set -euo pipefail
MD_HASH="#"


COMMAND="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

read_config() {
  local config_file="$1"

  CFG_PLANNING_TRACKING="manual"
  CFG_AUTO_PUSH="never"

  if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
    CFG_PLANNING_TRACKING=$(jq -r '.planning_tracking // "manual"' "$config_file" 2>/dev/null || echo "manual")
    CFG_AUTO_PUSH=$(jq -r '.auto_push // "never"' "$config_file" 2>/dev/null || echo "never")
  fi
}

write_transient_ignore_runtime() {
  local ignore_file="$1"
  cat > "$ignore_file" <<EOF
${MD_HASH} LBWC transient runtime artifacts
.execution-state.json
.execution-state.json.tmp
.context-*.md
.context-usage
.contracts/
.locks/
.token-state/
EOF
}

write_transient_ignore_tracking() {
  local ignore_file="$1"
  cat >> "$ignore_file" <<EOF

${MD_HASH} Session & agent tracking
.lbwc-context
.lbwc-session
.active-agent
.active-agents/
.active-agent-count
.active-agent-roles
.active-agent-role-pids
.active-agent-count.lock/
.agent-pids
.task-verify-seen

${MD_HASH} Metrics & cost tracking
.metrics/
.cost-ledger.json

${MD_HASH} Caching
.cache/

${MD_HASH} Artifacts & events (v2/v3 feature-gated)
.artifacts/
.events/
.event-log.jsonl
EOF
}

write_transient_ignore_recovery() {
  local ignore_file="$1"
  cat >> "$ignore_file" <<EOF

${MD_HASH} Snapshots & recovery
.snapshots/

${MD_HASH} Logging & markers
.hook-errors.log
.hook-debug.log
.skill-decisions.log
.compaction-marker
.session-log.jsonl
.session-log.jsonl.tmp
.notification-log.jsonl
.watchdog-pid
.watchdog.log
.claude-md-migrated
.tmux-mode-patched
.delegated-workflow.json

${MD_HASH} Baselines
.baselines/

${MD_HASH} Codebase mapping
codebase/
EOF
}

ensure_transient_ignore() {
  local planning_dir=".lbwc-planning"
  local ignore_file="$planning_dir/.gitignore"
  [ -d "$planning_dir" ] || return 0
  write_transient_ignore_runtime "$ignore_file"
  write_transient_ignore_tracking "$ignore_file"
  write_transient_ignore_recovery "$ignore_file"
}


ensure_generated_agent_ignore() {
  local repo_root root_ignore pattern
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  root_ignore="$repo_root/.gitignore"
  pattern=".claude/agents/lbwc-*-*-*-*.md"

  if [ ! -f "$root_ignore" ]; then
    printf '%s\n' "$pattern" > "$root_ignore"
    return 0
  fi

  if ! grep -Fxq "$pattern" "$root_ignore"; then
    printf '\n%s\n' "$pattern" >> "$root_ignore"
  fi
}

sync_root_ignore() {
  local mode="$1"
  local root_ignore=".gitignore"

  if [ "$mode" = "ignore" ]; then
    if [ ! -f "$root_ignore" ]; then
      printf '.lbwc-planning/\n' > "$root_ignore"
      return 0
    fi

    if ! grep -qx '\.lbwc-planning/' "$root_ignore"; then
      printf '\n.lbwc-planning/\n' >> "$root_ignore"
    fi
    return 0
  fi

  if [ "$mode" = "commit" ] && [ -f "$root_ignore" ]; then
    local tmp
    tmp=$(mktemp)
    awk '$0 != ".lbwc-planning/"' "$root_ignore" > "$tmp"
    mv "$tmp" "$root_ignore"
  fi
}

push_if_configured() {
  local push_mode="$1"
  [ "$push_mode" = "always" ] || return 0

  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    return 0
  fi

  git push
}

if [ -z "$COMMAND" ]; then
  echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | ensure-generated-agent-ignore | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
  exit 1
fi

case "$COMMAND" in
  ensure-generated-agent-ignore)
    if ! is_git_repo; then
      exit 0
    fi

    ensure_generated_agent_ignore
    ;;

  sync-ignore)
    CONFIG_FILE="${ARG2:-.lbwc-planning/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"
    sync_root_ignore "$CFG_PLANNING_TRACKING"
    ensure_generated_agent_ignore
    ensure_transient_ignore
    ;;

  commit-boundary)
    ACTION="${ARG2:-}"
    CONFIG_FILE="${ARG3:-.lbwc-planning/config.json}"

    if [ -z "$ACTION" ]; then
      echo "Usage: planning-git.sh commit-boundary <action> [CONFIG_FILE]" >&2
      exit 1
    fi

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_PLANNING_TRACKING" != "commit" ]; then
      exit 0
    fi

    ensure_transient_ignore

    if [ -d ".lbwc-planning" ]; then
      git add .lbwc-planning
    fi

    if [ -f "CLAUDE.md" ]; then
      git add CLAUDE.md
    fi

    if git diff --cached --quiet; then
      exit 0
    fi

    git commit -m "chore(lbwc): $ACTION"
    push_if_configured "$CFG_AUTO_PUSH"
    ;;

  push-after-phase)
    CONFIG_FILE="${ARG2:-.lbwc-planning/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_AUTO_PUSH" = "after_phase" ]; then
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push
      fi
    fi
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | ensure-generated-agent-ignore | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
    exit 1
    ;;
esac

exit 0