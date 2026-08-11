#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
GUARD="$SCRIPT_DIR/../hooks/user_question_guard.py"

fail() {
  printf 'pending-decision: %s\n' "$1" >&2
  exit 2
}

case "${1:-}" in
  state|get)
    exec python3 "$GUARD" decision-read "$@"
    ;;
  create|record-bounded|record-freeform)
    fail "direct decision transitions are disabled; Claude Code hooks own decision state"
    ;;
  *)
    fail "only read-only state and get commands are available"
    ;;
esac
