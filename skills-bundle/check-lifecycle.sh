#!/usr/bin/env bash
set -euo pipefail

base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() { echo "LIFECYCLE CHECK FAILED: $1"; exit 1; }

check_skill() {
  local path="$base/$1"
  test -f "$path" || fail "missing SKILL.md at $path"
}

check_skill "algorithmic-thinking/SKILL.md"
check_skill "clean-code-principles-python-silen/skills/clean-code-principles-python-silen/SKILL.md"
check_skill "discipline-of-programming-dijkstra/SKILL.md"
check_skill "fluent-python/SKILL.md"

echo "LIFECYCLE CHECK OK: $base"
