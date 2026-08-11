#!/usr/bin/env bash
set -euo pipefail

# R: success prints the canonical first valid root and repairs its exact session link. Failure follows the selected fatal or nonfatal contract.

required_script="hook-wrapper.sh"
nonfatal=false

# Invariant: parsed options are valid and remaining arguments are untouched. Variant: $# decreases.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-script)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "Usage: resolve-plugin-root.sh [--require-script <name>] [--nonfatal]" >&2
        exit 2
      fi
      required_script="$2"
      shift 2
      ;;
    --nonfatal)
      nonfatal=true
      shift
      ;;
    *)
      echo "Usage: resolve-plugin-root.sh [--require-script <name>] [--nonfatal]" >&2
      exit 2
      ;;
  esac
done

case "$required_script" in
  */* | . | ..)
    echo "resolve-plugin-root.sh: --require-script expects a script name" >&2
    exit 2
    ;;
esac

valid_root() {
  local candidate="${1:-}"
  [ -n "$candidate" ] &&
    [ -d "$candidate" ] &&
    [ -f "$candidate/scripts/$required_script" ]
}

session_link="/tmp/.lbwc-plugin-root-link-${CLAUDE_SESSION_ID:-default}"

fail_resolution() {
  if [ "$nonfatal" = true ]; then
    exit 0
  fi
  echo "LBWC: plugin root unavailable. Restart this session to recreate $session_link." >&2
  exit 1
}

fail_link() {
  if [ "$nonfatal" = true ]; then
    exit 0
  fi
  echo "LBWC: plugin root link unavailable. Restart this session to recreate $session_link." >&2
  exit 1
}

resolved_root=""

if valid_root "${CLAUDE_PLUGIN_ROOT:-}"; then
  resolved_root="$CLAUDE_PLUGIN_ROOT"
fi

if [ -z "$resolved_root" ] && valid_root "$session_link"; then
  resolved_root="$session_link"
fi

[ -n "$resolved_root" ] || fail_resolution
canonical_root=$(cd "$resolved_root" 2>/dev/null && pwd -P) || fail_resolution

if ! bash "$canonical_root/scripts/ensure-plugin-root-link.sh" \
  "$session_link" "$canonical_root" >/dev/null 2>&1; then
  fail_link
fi

printf '%s\n' "$canonical_root"
