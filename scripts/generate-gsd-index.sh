#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SOURCE="${1:-}"
OUTPUT="${2:-}"
if [ -z "$SOURCE" ]; then
  for candidate in .planning .lbwc-planning/gsd-archive .lbwc-planning/archive; do
    if [ -d "$candidate" ]; then
      SOURCE="$candidate"
      break
    fi
  done
fi
[ -n "$SOURCE" ] || exit 0

SOURCE=$(cd -P "$SOURCE" && pwd -P)
temporary=$(mktemp "${TMPDIR:-/tmp}/lbwc-gsd-index.XXXXXX")
trap 'rm -f "$temporary"' EXIT
bash "$SCRIPT_DIR/plan-import.sh" normalize --adapter gsd --source "$SOURCE" --output "$temporary"

jq \
  --arg imported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg source_root "${SOURCE#"$(cd -P . && pwd -P)"/}" \
  ' {
      imported_at: $imported_at,
      gsd_version: (.source.gsd_version // "unknown"),
      phases_total: (.phases | length),
      phases_complete: ([.phases[] | select(.status == "complete")] | length),
      milestones: [.milestones[].name],
      quick_paths: {
        roadmap: ($source_root + "/ROADMAP.md"),
        project: ($source_root + "/PROJECT.md"),
        phases: ($source_root + "/phases/"),
        config: ($source_root + "/config.json")
      },
      phases: [.phases[] | {
        num: .number,
        slug: .slug,
        plans: (.plans | length),
        status: (.status // "unknown")
      }]
    }' "$temporary" > "${OUTPUT:-/dev/stdout}"
