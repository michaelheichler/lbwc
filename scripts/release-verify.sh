#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  printf 'Usage: release-verify.sh\n'
}

[ "$#" -eq 0 ] || { usage >&2; exit 2; }
bash "$ROOT/scripts/version-bump.sh" --verify
jq -e '.name == "lbwc" and (has("hooks") | not)' "$ROOT/.claude-plugin/plugin.json" >/dev/null
[ -x "$ROOT/scripts/rtk-manager.sh" ] || { printf 'release verify: rtk-manager.sh is not executable\n' >&2; exit 2; }
printf 'release verify: local release metadata is ready for a separate publish decision\n'
