#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SETTINGS_PATH=""
CONFIRMED=false
REPLACE=false

usage() {
  printf 'Usage: statusline-install.sh [--settings PATH] --yes [--replace]\n' >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --settings) [ "$#" -ge 2 ] || usage; SETTINGS_PATH="$2"; shift 2 ;;
    --yes) CONFIRMED=true; shift ;;
    --replace) REPLACE=true; shift ;;
    *) usage ;;
  esac
done

if [ -z "$SETTINGS_PATH" ]; then
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    SETTINGS_PATH="$CLAUDE_CONFIG_DIR/settings.json"
  elif [ -d "$HOME/.config/claude-code" ]; then
    SETTINGS_PATH="$HOME/.config/claude-code/settings.json"
  else
    SETTINGS_PATH="$HOME/.claude/settings.json"
  fi
fi

command -v jq >/dev/null 2>&1 || { printf 'statusline_install=jq_unavailable\n' >&2; exit 2; }
[ "$CONFIRMED" = true ] || { printf 'statusline_install=confirmation_required\n'; exit 2; }

mkdir -p "$(dirname "$SETTINGS_PATH")"
[ -f "$SETTINGS_PATH" ] || printf '{}\n' > "$SETTINGS_PATH"
jq -e 'type == "object"' "$SETTINGS_PATH" >/dev/null 2>&1 || { printf 'statusline_install=settings_malformed\n' >&2; exit 2; }

CURRENT=$(jq -r '.statusLine.command // .statusLine // empty' "$SETTINGS_PATH")
if [ -n "$CURRENT" ] && [[ "$CURRENT" != *lbwc-statusline.sh* ]] && [ "$REPLACE" != true ]; then
  printf 'statusline_install=replacement_confirmation_required\n'
  exit 2
fi

COMMAND=$(printf 'bash %q' "$SCRIPT_DIR/lbwc-statusline.sh")
TMP=$(mktemp "$(dirname "$SETTINGS_PATH")/.lbwc-settings.XXXXXX")
BACKUP="${SETTINGS_PATH}.lbwc-statusline.bak"
cp "$SETTINGS_PATH" "$BACKUP"
if jq --arg command "$COMMAND" '.statusLine = {type:"command", command:$command, refreshInterval:15}' "$SETTINGS_PATH" > "$TMP" && mv "$TMP" "$SETTINGS_PATH"; then
  printf 'statusline_install=installed refresh_interval=15 backup=%s\n' "$BACKUP"
  exit 0
fi
cp "$BACKUP" "$SETTINGS_PATH"
rm -f "$TMP"
printf 'statusline_install=failed_restored\n' >&2
exit 2
